import Foundation

// In-memory no-op vault for isolated metadata service checks. No real profile is read.
enum MusicVault {
    static func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? { nil }
    static func write<T: Encodable>(_ value: T, key: String) throws {}
    static func delete(_ key: String) throws {}
}

final class GenreMockProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var offline = false
    static var transientFailures = 0
    static var malformed = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        precondition(request.url?.host == "musicbrainz.org")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "User-Agent")?.contains("InTune") == true)
        if Self.offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        if Self.transientFailures > 0 {
            Self.transientFailures -= 1
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 503,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let id = "11111111-1111-4111-8111-111111111111"
        let body: String
        let status: Int
        if request.url!.path == "/ws/2/url" {
            let resource = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "resource" }!.value!
            if Self.malformed && resource.hasSuffix("broken") { body = "invalid"; status = 200 }
            else if resource.hasSuffix("unmapped") { body = "{}"; status = 404 }
            else { body = "{\"relations\":[{\"artist\":{\"id\":\"\(id)\"}}]}"; status = 200 }
        } else {
            precondition(request.url!.path == "/ws/2/artist/" + id)
            body = #"{"genres":[{"name":"jazz rap","count":5},{"name":"alternative hip hop","count":3},{"name":"rejected-tag","count":-1}]}"#
            status = 200
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct MusicBrainzGenreChecks {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GenreMockProtocol.self]
        let http = URLSession(configuration: config)
        let service = MusicBrainzGenreService(http: http, requestSpacing: 0, retryDelay: 0)
        let artist = SpotifyArtist(id: "fixture", name: "Fixture artist", genres: nil, external_urls: nil)
        let result = await service.enrich([artist])
        precondition(result[0].genres == ["jazz rap", "alternative hip hop"])
        precondition(result[0].genreSourceName == "MusicBrainz")
        precondition(GenreMockProtocol.requests.count == 2)
        _ = await service.enrich([artist])
        precondition(GenreMockProtocol.requests.count == 2, "Cached lookups must avoid network requests")
        let unknown = SpotifyArtist(id: "unmapped", name: "Unmapped", genres: nil, external_urls: nil)
        let missing = await service.enrich([unknown])
        precondition(missing[0].genres == nil, "Never invent tags for unmapped artists")
        let before = GenreMockProtocol.requests.count
        _ = await service.enrich([unknown])
        precondition(GenreMockProtocol.requests.count == before, "Cache missing relationships too")
        _ = await service.enrich([unknown], retryMissing: true)
        precondition(GenreMockProtocol.requests.count == before + 1, "Explicit retry must recheck negative cache")
        let many = (0..<12).map { SpotifyArtist(id: "batch\($0)", name: "Artist \($0)", genres: nil, external_urls: nil) }
        var progress: [Int] = []
        let batch = await service.enrich(many) { _, checked, total, _ in
            precondition(total == 12)
            progress.append(checked)
        }
        precondition(batch.allSatisfy { $0.genres?.contains("jazz rap") == true }, "No five-artist limit")
        precondition(progress == Array(0...12), "Publish each artist progressively")
        GenreMockProtocol.transientFailures = 1
        let retry = await MusicBrainzGenreService(http: http, requestSpacing: 0, retryDelay: 0).enrich([artist])
        precondition(retry[0].genres?.contains("jazz rap") == true, "Retry service throttling")
        GenreMockProtocol.malformed = true
        let broken = SpotifyArtist(id: "broken", name: "Broken", genres: nil, external_urls: nil)
        let recovery = await MusicBrainzGenreService(http: http, requestSpacing: 0, retryDelay: 0).enrich([broken, artist])
        precondition(recovery[0].genres == nil && recovery[1].genres != nil, "One malformed response must not block later artists")
        GenreMockProtocol.offline = true
        let unavailable = await MusicBrainzGenreService(http: http, requestSpacing: 0, retryDelay: 0).enrich([artist])
        precondition(unavailable[0] == artist, "Metadata outages must not break artist imports")
        print("Genre service checks passed: full batch, incremental progress, transient retry, malformed response recovery, negative-cache retry, identity lookup, specific genres, provenance, caching, no credentials, missing data, offline fallback.")
    }
}
