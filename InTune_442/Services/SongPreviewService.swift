import Foundation

/// Fetches public song metadata only. Audio previews are streamed by AVPlayer, not saved.
@MainActor
final class SongPreviewService {
    static let shared = SongPreviewService()
    private struct Response: Decodable { let results: [SongPreviewMetadata] }
    private var cache: [String: SongPreviewMetadata] = [:]
    private let http: URLSession
    init(http: URLSession = .shared) { self.http = http }

    func lookup(_ song: ShowcaseSong, country: String = Locale.current.region?.identifier ?? "US") async throws -> SongPreviewMetadata? {
        let storefront = country.count == 2 ? country.uppercased() : "US"
        let key = song.id + "|" + storefront
        if let saved = cache[key] { return saved }
        var url = URLComponents(string: song.appleTrackID == nil ? "https://itunes.apple.com/search" : "https://itunes.apple.com/lookup")!
        url.queryItems = [URLQueryItem(name: "country", value: storefront), URLQueryItem(name: "entity", value: "song")]
        if let id = song.appleTrackID {
            url.queryItems?.append(URLQueryItem(name: "id", value: String(id)))
        } else {
            url.queryItems? += [URLQueryItem(name: "term", value: song.title + " " + song.artist),
                               URLQueryItem(name: "limit", value: "10")]
        }
        let (data, response) = try await http.data(for: URLRequest(url: url.url!, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let songs = try JSONDecoder().decode(Response.self, from: data).results
        // Do not silently preview a remix, cover, or another artist's recording.
        let match = songs.first { $0.matches(song) && $0.audioURL != nil && $0.storeURL != nil }
            ?? songs.first { $0.matches(song) && $0.storeURL != nil }
        if let match { cache[key] = match }
        return match
    }
}
