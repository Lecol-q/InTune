import Foundation

struct SpotifyArtist: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var genres: [String]?
    var genreSourceName: String? = nil
    var genreSourceURL: String? = nil
    let external_urls: [String: String]?
}

struct SpotifyTrack: Codable, Identifiable, Equatable {
    struct Album: Codable, Equatable {
        struct Image: Codable, Equatable { let url: String }
        let name: String
        let images: [Image]
    }
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: Album
    let external_urls: [String: String]?
}

struct SpotifyPage<Item: Decodable>: Decodable { let items: [Item] }

struct GenreWeight: Codable, Identifiable, Equatable {
    let name: String
    /// Share of rank-weighted genre evidence, not listening time or play count.
    let weight: Double
    var id: String { name }
}

/// Only this music summary belongs in a future public pre-match profile.
/// Tokens and Spotify account identifiers must stay outside that document.
struct MusicTaste: Codable, Equatable {
    let updatedAt: Date
    let timeRange: String
    let topArtists: [SpotifyArtist]
    let topTracks: [SpotifyTrack]
    let genres: [GenreWeight]
    var showcaseTrackID: String?

    var showcaseTrack: SpotifyTrack? { topTracks.first { $0.id == showcaseTrackID } }
    var summary: String {
        if !genres.isEmpty {
            return "Mostly " + genres.prefix(3).map(\.name).joined(separator: ", ") + "."
        }
        if !topArtists.isEmpty {
            return "Listening to " + topArtists.prefix(3).map(\.name).joined(separator: ", ") + "."
        }
        return "Not enough listening history yet. Listen on Spotify, then refresh your music."
    }
}

/// A transparent summary algorithm. Higher-ranked artists contribute more evidence.
/// Each artist's vote is split across its unique tags so many tags don't inflate its vote.
enum MusicTasteBuilder {
    static let artistLimit = 10
    static func build(artists: [SpotifyArtist], tracks: [SpotifyTrack],
                      previousShowcase: String? = nil, now: Date = Date()) -> MusicTaste {
        var artistIDs = Set<String>()
        let uniqueArtists = artists.filter { artistIDs.insert($0.id).inserted }.prefix(artistLimit)
            .map(ArtistGenreCatalog.enrich)
        var trackIDs = Set<String>()
        let uniqueTracks = tracks.filter { trackIDs.insert($0.id).inserted }
        var scores: [String: Double] = [:]
        for (rank, artist) in uniqueArtists.enumerated() {
            let tags = Set((artist.genres ?? []).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty })
            guard !tags.isEmpty else { continue }
            let vote = 1.0 / Double(rank + 1) / Double(tags.count)
            for tag in tags { scores[tag, default: 0] += vote }
        }
        let total = scores.values.reduce(0, +)
        var genres: [GenreWeight] = []
        if total > 0 {
            for (name, score) in scores { genres.append(GenreWeight(name: name, weight: score / total)) }
        }
        genres.sort { left, right in
            if left.weight == right.weight { return left.name < right.name }
            return left.weight > right.weight
        }
        let showcase = uniqueTracks.contains { $0.id == previousShowcase } ? previousShowcase : nil
        return MusicTaste(updatedAt: now, timeRange: "medium_term", topArtists: uniqueArtists,
                          topTracks: uniqueTracks, genres: genres, showcaseTrackID: showcase)
    }
}

/// Small verified bootstrap catalog for immediate offline coverage. Missing artists can
/// also be resolved through their exact Spotify URL by MusicBrainzGenreService.
enum ArtistGenreCatalog {
    struct Entry {
        let genres: [String]
        let musicBrainzID: String
    }
    // MusicBrainz artist pages and their Spotify relationships checked 2026-10-25.
    // Summrs genres and exact Spotify relationship verified via API 2026-10-27.
    static let entries: [String: Entry] = [
        "3TVXtAsR1Inumwj472S9r4": Entry(
            genres: ["hip hop", "r&b", "contemporary r&b", "pop rap", "alternative r&b"],
            musicBrainzID: "9fff2f8a-21e6-47de-a2b8-7f449929d43f"),
        "5K4W6rqBFWDnAN6FQUkS6x": Entry(
            genres: ["hip hop", "pop rap", "experimental hip hop", "pop", "christian hip hop"],
            musicBrainzID: "164f0d73-1234-4e2c-8743-d77bf2191051"),
        "0Y4inQK6OespitzD6ijMwb": Entry(
            genres: ["gangsta rap", "hip hop", "hardcore hip hop", "alternative hip hop", "jazz rap"],
            musicBrainzID: "21645c31-fe1c-45a4-955c-3e172b12c3f9"),
        "5L15t6I0PQS9SBXbiklPEN": Entry(
            genres: ["plugg", "pluggnb", "southern hip hop", "trap"],
            musicBrainzID: "d538d883-3889-44ad-8f32-6167cf4d85ec")
    ]
    static func hasGenres(_ artist: SpotifyArtist) -> Bool {
        (artist.genres ?? []).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    static func enrich(_ artist: SpotifyArtist) -> SpotifyArtist {
        guard !hasGenres(artist), let entry = entries[artist.id] else { return artist }
        var enriched = artist
        enriched.genres = entry.genres
        enriched.genreSourceName = "MusicBrainz"
        enriched.genreSourceURL = "https://musicbrainz.org/artist/" + entry.musicBrainzID
        return enriched
    }
}
