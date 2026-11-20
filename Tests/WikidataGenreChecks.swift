import Foundation

enum MusicVault {
    static func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? { nil }
    static func write<T: Encodable>(_ value: T, key: String) throws {}
    static func delete(_ key: String) throws {}
}
final class WikidataMock: URLProtocol {
    static var requests: [URLRequest] = []
    static var failures = 0
    static var offline = false
    static var rows: [[String: [String: String]]] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "User-Agent")?.contains("InTune") == true)
        if Self.offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status: Int
        let data: Data
        if request.url?.host == "musicbrainz.org" { status = 404; data = Data("{}".utf8) }
        else {
            precondition(request.url?.host == "query.wikidata.org")
            if Self.failures > 0 { Self.failures -= 1; status = 503; data = Data() }
            else {
                status = 200
                data = try! JSONSerialization.data(withJSONObject: ["results": ["bindings": Self.rows]])
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct WikidataGenreChecks {
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WikidataMock.self]
        let http = URLSession(configuration: configuration)
        func artist(_ id: String, tags: [String]? = nil) -> SpotifyArtist {
            SpotifyArtist(id: id, name: "Same name", genres: tags, external_urls: nil)
        }
        func row(_ id: String, _ item: String, _ tag: String) -> [String: [String: String]] {
            ["spotify": ["type": "literal", "value": id],
             "item": ["type": "uri", "value": "http://www.wikidata.org/entity/" + item],
             "genreLabel": ["type": "literal", "value": tag]]
        }
        let a = String(repeating: "A", count: 22), b = String(repeating: "B", count: 22)
        let c = String(repeating: "C", count: 22), d = String(repeating: "D", count: 22)
        WikidataMock.rows = [row(a, "Q42", "Jazz Rap"), row(a, "Q42", "Jazz Rap"),
            row(a, "Q42", "Alternative hip-hop"), row(b, "Q1", "rock"), row(b, "Q2", "pop"),
            row(d, "Q3", "replace-me"), row("unrequested", "Q4", "wrong-artist")]
        let service = WikidataGenreService(http: http, spacing: 0)
        let input = [artist(a), artist(b), artist(c), artist(d, tags: ["spotify-tag"])]
        let result = try await service.enrich(input)
        precondition(result[0].genres == ["alternative hip-hop", "jazz rap"])
        precondition(result[0].genreSourceName == "Wikidata" && result[0].genreSourceURL == "https://www.wikidata.org/wiki/Q42")
        precondition(result[1].genres == nil, "Ambiguous Spotify cross-references must not merge artists")
        precondition(result[2].genres == nil, "No name-only matches or invented tags")
        precondition(result[3] == input[3], "Existing Spotify or user tags take priority")
        let query = URLComponents(url: WikidataMock.requests.last!.url!, resolvingAgainstBaseURL: false)!
            .queryItems!.first { $0.name == "query" }!.value!
        precondition(query.contains(a) && query.contains(b) && query.contains(c) && !query.contains(d))
        precondition(query.contains("P1902") && query.contains("P136") && !query.contains("Same name"))
        let before = WikidataMock.requests.count
        _ = try await service.enrich(input)
        precondition(WikidataMock.requests.count == before, "Cache both positive and empty results")
        _ = try await service.enrich(input, retryMissing: true)
        precondition(WikidataMock.requests.count == before + 1, "Explicit retry checks missing metadata again")
        WikidataMock.failures = 1
        _ = try await WikidataGenreService(http: http, spacing: 0).enrich([artist(a)])
        precondition(WikidataMock.failures == 0, "Recover from transient throttling")
        let unsafe = artist("\" } UNION { ?s ?p ?o")
        let count = WikidataMock.requests.count
        _ = try await service.enrich([unsafe])
        precondition(WikidataMock.requests.count == count, "Reject query injection")
        let combined = ArtistGenreService(musicBrainz: MusicBrainzGenreService(http: http, requestSpacing: 0, retryDelay: 0),
            wikidata: WikidataGenreService(http: http, spacing: 0))
        let fortyTwo = (0..<42).map { artist(String(repeating: "Z", count: 20) + String(format: "%02d", $0)) }
        WikidataMock.requests = []
        let capped = await combined.enrich(fortyTwo)
        precondition(capped.count == 10)
        precondition(WikidataMock.requests.filter { $0.url?.host == "musicbrainz.org" }.count == 10,
            "Never enrich artist 11 through 42")
        let filled = await combined.enrich([artist(a)])
        precondition(filled[0].genreSourceName == "Wikidata" && filled[0].genres?.contains("jazz rap") == true,
            "Automatically consult the second source when MusicBrainz has no relationship")
        WikidataMock.offline = true
        let offline = await combined.enrich([artist(a, tags: ["keep-me"])])
        precondition(offline[0].genres == ["keep-me"])
        let unknownOffline = await combined.enrich([artist(String(repeating: "E", count: 22))])
        precondition(unknownOffline[0].genres == nil, "Both source outages leave the import intact")
        // Optional live fixture produced by the exact production query.
        if CommandLine.arguments.count > 1 {
            let live = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
            WikidataMock.offline = false
            WikidataMock.rows = (live["results"] as! [String: Any])["bindings"] as! [[String: [String: String]]]
            let kendrick = artist("2YZyLoL8N0Wb9xBt1NhZWg")
            let liveTags = try await WikidataGenreService(http: http, spacing: 0).enrich([kendrick])
            precondition(liveTags[0].genres?.contains("jazz rap") == true)
        }
        print("Wikidata checks passed: exact IDs, batch query, specific tags, attribution, ambiguity rejection, cache, retry, existing-tag priority, unsafe IDs, top-ten cap, offline fallback.")
    }
}
