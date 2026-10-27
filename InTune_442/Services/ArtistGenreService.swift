import Foundation

/// Source priority: existing/user tags, MusicBrainz, then Wikidata for remaining gaps.
@MainActor
final class ArtistGenreService {
    static let shared = ArtistGenreService()
    private let musicBrainz: MusicBrainzGenreService
    private let wikidata: WikidataGenreService

    init(musicBrainz: MusicBrainzGenreService? = nil, wikidata: WikidataGenreService? = nil) {
        self.musicBrainz = musicBrainz ?? .shared
        self.wikidata = wikidata ?? .shared
    }
    func cachedEnrichment(_ artists: [SpotifyArtist]) -> [SpotifyArtist] {
        wikidata.cachedEnrichment(musicBrainz.cachedEnrichment(Array(artists.prefix(MusicTasteBuilder.artistLimit))))
    }
    func enrich(_ artists: [SpotifyArtist], retryMissing: Bool = false,
                onProgress: (([SpotifyArtist], Int, Int, Bool) -> Void)? = nil) async -> [SpotifyArtist] {
        let initial = cachedEnrichment(artists)
        let total = initial.filter { !ArtistGenreCatalog.hasGenres($0) }.count
        let first = await musicBrainz.enrich(initial, retryMissing: retryMissing, onProgress: onProgress)
        guard !Task.isCancelled else { return first }
        do {
            let result = try await wikidata.enrich(first, retryMissing: retryMissing)
            guard !Task.isCancelled else { return first }
            onProgress?(result, total, total, false)
            return result
        } catch {
            if !Task.isCancelled { onProgress?(first, total, total, true) }
            return first
        }
    }
    func clearCache() throws {
        try musicBrainz.clearCache()
        try wikidata.clearCache()
    }
}
