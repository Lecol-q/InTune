import Foundation

/// Additional public artist metadata, joined by Spotify ID rather than artist name.
@MainActor
final class WikidataGenreService {
    static let shared = WikidataGenreService()
    private struct Entry: Codable {
        let genres: [String]
        let sourceURL: String?
        let date: Date
    }
    private struct Response: Decodable {
        struct Value: Decodable { let type: String; let value: String }
        struct Row: Decodable {
            let spotify: Value
            let item: Value
            let genreLabel: Value?
        }
        struct Results: Decodable { let bindings: [Row] }
        let results: Results
    }
    private var cache: [String: Entry]
    private var version = UUID()
    private var nextRequest = Date.distantPast
    private let http: URLSession
    private let spacing: TimeInterval

    init(http: URLSession = .shared, spacing: TimeInterval = 1) {
        self.http = http
        self.spacing = spacing
        cache = (try? MusicVault.read("wikidata-genres", as: [String: Entry].self)) ?? [:]
    }

    func cachedEnrichment(_ artists: [SpotifyArtist]) -> [SpotifyArtist] {
        artists.map { artist in
            guard !ArtistGenreCatalog.hasGenres(artist), let entry = cache[artist.id],
                  !entry.genres.isEmpty, Date().timeIntervalSince(entry.date) < 7 * 86400 else { return artist }
            return apply(entry, to: artist)
        }
    }

    func enrich(_ artists: [SpotifyArtist], retryMissing: Bool = false) async throws -> [SpotifyArtist] {
        var result = cachedEnrichment(artists)
        // One small batch for the app's top ten. Reject unsafe identifiers before building SPARQL.
        let pending = result.filter { artist in
            guard !ArtistGenreCatalog.hasGenres(artist), Self.validID(artist.id) else { return false }
            if !retryMissing, let saved = cache[artist.id], saved.genres.isEmpty,
               Date().timeIntervalSince(saved.date) < 3600 { return false }
            return true
        }.prefix(MusicTasteBuilder.artistLimit)
        guard !pending.isEmpty else { return result }
        let ids = Set(pending.map(\.id))
        let capturedVersion = version
        let values = ids.sorted().map { "\"\($0)\"" }.joined(separator: " ")
        let query = """
        PREFIX wdt: <http://www.wikidata.org/prop/direct/>
        PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
        SELECT DISTINCT ?spotify ?item ?genreLabel WHERE {
          VALUES ?spotify { \(values) }
          ?item wdt:P1902 ?spotify.
          OPTIONAL { ?item wdt:P136 ?genre. ?genre rdfs:label ?genreLabel.
                     FILTER(LANG(?genreLabel) = "en") }
        }
        """
        let response = try await fetch(query)
        try Task.checkCancellation()
        guard capturedVersion == version else { throw CancellationError() }
        let rows = response.results.bindings.filter {
            ids.contains($0.spotify.value) && $0.spotify.type == "literal" && $0.item.type == "uri" && Self.entityID($0.item.value) != nil
        }
        for id in ids {
            let matches = rows.filter { $0.spotify.value == id }
            let entities = Set(matches.map { $0.item.value })
            // Ambiguous cross-references must not combine two different artists' genres.
            let itemID = entities.count == 1 ? entities.first.flatMap(Self.entityID) : nil
            let tags = itemID == nil ? [] : Array(Set(matches.compactMap { row -> String? in
                guard let label = row.genreLabel, label.type == "literal" else { return nil }
                let tag = label.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return tag.isEmpty || tag.count > 80 ? nil : tag
            })).sorted().prefix(8).map { $0 }
            cache[id] = Entry(genres: tags, sourceURL: itemID.map { "https://www.wikidata.org/wiki/" + $0 }, date: Date())
        }
        try? MusicVault.write(cache, key: "wikidata-genres")
        for index in result.indices {
            if ids.contains(result[index].id), let entry = cache[result[index].id] {
                result[index] = apply(entry, to: result[index])
            }
        }
        return result
    }

    func clearCache() throws {
        try MusicVault.delete("wikidata-genres")
        version = UUID()
        cache = [:]
    }

    private func apply(_ entry: Entry, to artist: SpotifyArtist) -> SpotifyArtist {
        guard !entry.genres.isEmpty, !ArtistGenreCatalog.hasGenres(artist) else { return artist }
        var result = artist
        result.genres = entry.genres
        result.genreSourceName = "Wikidata"
        result.genreSourceURL = entry.sourceURL
        return result
    }

    private static func validID(_ id: String) -> Bool {
        id.count == 22 && id.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value)
        }
    }
    private static func entityID(_ value: String) -> String? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme ?? ""),
              url.host == "www.wikidata.org", url.path.hasPrefix("/entity/Q") else { return nil }
        let id = url.lastPathComponent
        guard id.first == "Q", id.dropFirst().allSatisfy({ $0.isNumber }), id.count > 1,
              url.path == "/entity/" + id, url.query == nil, url.fragment == nil else { return nil }
        return id
    }

    private func fetch(_ query: String) async throws -> Response {
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "format", value: "json")]
        for attempt in 0..<3 {
            try Task.checkCancellation()
            while nextRequest.timeIntervalSinceNow > 0 {
                try await Task.sleep(nanoseconds: UInt64(max(0, nextRequest.timeIntervalSinceNow) * 1_000_000_000))
            }
            nextRequest = Date().addingTimeInterval(spacing)
            var request = URLRequest(url: components.url!, timeoutInterval: 12)
            request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
            request.setValue("InTuneStudentPrototype/0.1 (https://github.com/Lecol-q/InTune)", forHTTPHeaderField: "User-Agent")
            let (data, raw) = try await http.data(for: request)
            guard let response = raw as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 200 { return try JSONDecoder().decode(Response.self, from: data) }
            if [429, 500, 502, 503, 504].contains(response.statusCode) {
                let delay = max(spacing * Double(attempt + 1), Self.retryAfter(response))
                nextRequest = max(nextRequest, Date().addingTimeInterval(delay))
                if attempt < 2, delay <= 20 { continue }
            }
            throw URLError(.badServerResponse)
        }
        throw URLError(.badServerResponse)
    }

    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return 0 }
        if let seconds = Double(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return max(0, formatter.date(from: value)?.timeIntervalSinceNow ?? 0)
    }
}
