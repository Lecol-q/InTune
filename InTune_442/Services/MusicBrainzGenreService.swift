import Foundation

/// Requests contain public artist URLs only, never Spotify credentials or user IDs.
/// Resolve by the Spotify relationship, not artist names, to avoid ambiguous matches.
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
    private var cache: [String: CacheEntry] = [:]
    private var lastRequest = Date.distantPast
    private let http: URLSession

    init(http: URLSession = .shared) {
        self.http = http
        cache = (try? MusicVault.read("genre-metadata", as: [String: CacheEntry].self)) ?? [:]
    }

    func enrich(_ artists: [SpotifyArtist]) async -> [SpotifyArtist] {
        var result = artists.map(ArtistGenreCatalog.enrich)
        // Bound each refresh to five new lookups. Cached/seeded tags need no requests.
        var remaining = 5
        for index in result.indices where !ArtistGenreCatalog.hasGenres(result[index]) {
            let id = result[index].id
            if let saved = cache[id], Date().timeIntervalSince(saved.date) < 7 * 24 * 3600 {
                apply(saved, to: &result[index])
                continue
            }
            guard remaining > 0 else { continue }
            remaining -= 1
            do {
                let saved = try await resolve(id)
                cache[id] = saved
                apply(saved, to: &result[index])
            } catch {
                // Optional genre enrichment must never prevent importing songs/artists.
                // Stop on service failures instead of repeatedly hitting an unavailable API.
                break
            }
        }
        try? MusicVault.write(cache, key: "genre-metadata")
        return result
    }

    func clearCache() throws {
        try MusicVault.delete("genre-metadata")
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
            .sorted { ($0.count ?? 0) > ($1.count ?? 0) }
            .prefix(8).map(\.name)
        return CacheEntry(genres: genres, sourceURL: "https://musicbrainz.org/artist/" + id, date: Date())
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T? {
        // MusicBrainz permits at most one request per second per client.
        let delay = 1.1 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        lastRequest = Date()
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/" + path)!
        url.queryItems = query + [URLQueryItem(name: "fmt", value: "json")]
        var request = URLRequest(url: url.url!, timeoutInterval: 5)
        request.setValue("InTuneStudentPrototype/0.1 (https://github.com/Lecol-q/InTune)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
