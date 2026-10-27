import Foundation

/// Requests contain public artist URLs only, never Spotify credentials or user IDs.
/// Exact Spotify relationships avoid confusing artists with similar names.
@MainActor
final class MusicBrainzGenreService {
    static let shared = MusicBrainzGenreService()
    private struct CacheEntry: Codable {
        let genres: [String]
        let sourceURL: String?
        let date: Date
    }
    private struct Relation: Decodable {
        struct Artist: Decodable { let id: String }
        let artist: Artist?
    }
    private struct URLResult: Decodable { let relations: [Relation]? }
    private struct ArtistResult: Decodable {
        struct Genre: Decodable { let name: String; let count: Int? }
        let genres: [Genre]?
    }
    private struct HTTPFailure: Error { let status: Int }
    private var cache: [String: CacheEntry] = [:]
    private var nextRequest = Date.distantPast
    private var cacheVersion = UUID()
    private let http: URLSession
    private let requestSpacing: TimeInterval
    private let retryDelay: TimeInterval

    init(http: URLSession = .shared, requestSpacing: TimeInterval = 1.1, retryDelay: TimeInterval = 2) {
        self.http = http
        self.requestSpacing = requestSpacing
        self.retryDelay = retryDelay
        cache = (try? MusicVault.read("genre-metadata", as: [String: CacheEntry].self)) ?? [:]
    }

    func cachedEnrichment(_ artists: [SpotifyArtist]) -> [SpotifyArtist] {
        artists.map { artist in
            var result = ArtistGenreCatalog.enrich(artist)
            if !ArtistGenreCatalog.hasGenres(result), let saved = cache[artist.id],
               !saved.genres.isEmpty, Date().timeIntervalSince(saved.date) < 7 * 24 * 3600 {
                apply(saved, to: &result)
            }
            return result
        }
    }

    /// Progress reports artists checked, not a promise that every artist has source tags.
    func enrich(_ artists: [SpotifyArtist], retryMissing: Bool = false,
                onProgress: (([SpotifyArtist], Int, Int, Bool) -> Void)? = nil) async -> [SpotifyArtist] {
        var result = cachedEnrichment(artists)
        let pending = result.indices.filter { !ArtistGenreCatalog.hasGenres(result[$0]) }
        let version = cacheVersion
        var checked = 0
        onProgress?(result, 0, pending.count, false)
        for index in pending {
            guard !Task.isCancelled, cacheVersion == version else { return result }
            let id = result[index].id
            if !retryMissing, let saved = cache[id], saved.genres.isEmpty,
               Date().timeIntervalSince(saved.date) < 3600 {
                checked += 1
                onProgress?(result, checked, pending.count, false)
                continue
            }
            do {
                let saved = try await resolve(id)
                guard !Task.isCancelled, cacheVersion == version else { return result }
                cache[id] = saved
                apply(saved, to: &result[index])
                // Save each success so interruption doesn't discard earlier lookups.
                try? MusicVault.write(cache, key: "genre-metadata")
                checked += 1
                onProgress?(result, checked, pending.count, false)
            } catch {
                guard !Task.isCancelled, cacheVersion == version else { return result }
                if error is DecodingError {
                    // One malformed artist response must not strand every later artist.
                    checked += 1
                    onProgress?(result, checked, pending.count, true)
                    continue
                }
                // Requests already retry temporary failures. Pause network-wide outages
                // or throttling; the foreground/Retry action resumes unfinished artists.
                onProgress?(result, checked, pending.count, true)
                break
            }
        }
        return result
    }

    func clearCache() throws {
        try MusicVault.delete("genre-metadata")
        cacheVersion = UUID()
        cache = [:]
    }
    private func apply(_ saved: CacheEntry, to artist: inout SpotifyArtist) {
        guard !saved.genres.isEmpty else { return }
        artist.genres = saved.genres
        artist.genreSourceName = "MusicBrainz"
        artist.genreSourceURL = saved.sourceURL
    }
    private func resolve(_ spotifyID: String) async throws -> CacheEntry {
        let url: URLResult? = try await get(path: "url", query: [
            URLQueryItem(name: "resource", value: "https://open.spotify.com/artist/" + spotifyID),
            URLQueryItem(name: "inc", value: "artist-rels")
        ])
        let ids = Set((url?.relations ?? []).compactMap { $0.artist?.id })
        guard ids.count == 1, let id = ids.first, UUID(uuidString: id) != nil else {
            return CacheEntry(genres: [], sourceURL: nil, date: Date())
        }
        let details: ArtistResult? = try await get(path: "artist/" + id,
            query: [URLQueryItem(name: "inc", value: "genres")])
        let genres = (details?.genres ?? []).filter { ($0.count ?? 0) > 0 }
            .sorted { ($0.count ?? 0) > ($1.count ?? 0) }.prefix(8).map(\.name)
        return CacheEntry(genres: genres, sourceURL: "https://musicbrainz.org/artist/" + id, date: Date())
    }
    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T? {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            // Re-check after sleeping so canceled/restarted passes still share one rate gate.
            while nextRequest.timeIntervalSinceNow > 0 {
                try await Task.sleep(nanoseconds: UInt64(max(0, nextRequest.timeIntervalSinceNow) * 1_000_000_000))
            }
            nextRequest = Date().addingTimeInterval(requestSpacing)
            var url = URLComponents(string: "https://musicbrainz.org/ws/2/" + path)!
            url.queryItems = query + [URLQueryItem(name: "fmt", value: "json")]
            var request = URLRequest(url: url.url!, timeoutInterval: 8)
            request.setValue("InTuneStudentPrototype/0.1 (https://github.com/Lecol-q/InTune)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await http.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 404 { return nil }
                if response.statusCode == 200 { return try JSONDecoder().decode(T.self, from: data) }
                let failure = HTTPFailure(status: response.statusCode)
                if [429, 500, 502, 503, 504].contains(response.statusCode) {
                    let delay = max(retryDelay * Double(attempt + 1), Self.retryAfter(response))
                    nextRequest = max(nextRequest, Date().addingTimeInterval(delay))
                    if delay > 20 || attempt == 2 { throw failure } // Keep the future gate; don't retry early.
                    continue
                }
                throw failure
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                guard attempt < 2 else { throw error }
                nextRequest = max(nextRequest, Date().addingTimeInterval(retryDelay * Double(attempt + 1)))
            }
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
