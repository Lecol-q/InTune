import Foundation

/// Explicit user corrections stay distinguishable from catalog-provided metadata.
struct ArtistGenreCorrection: Codable {
    let tags: [String]
    let original: SpotifyArtist

    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func apply(_ corrections: [String: Self], to artists: [SpotifyArtist]) -> [SpotifyArtist] {
        artists.map { artist in
            guard let correction = corrections[artist.id] else { return artist }
            var result = artist
            result.genres = correction.tags
            result.genreSourceName = "Your tags"
            result.genreSourceURL = nil
            return result
        }
    }
}
