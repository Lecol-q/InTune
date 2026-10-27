import Foundation

@main struct MusicTasteChecks {
    static func main() throws {
        func artist(_ id: String, _ genres: [String]?) -> SpotifyArtist {
            SpotifyArtist(id: id, name: id, genres: genres, external_urls: nil)
        }
        let artists = [artist("A", [" Rock ", "rock", "pop"]), artist("B", ["rock"]), artist("A", ["jazz"])]
        let taste = MusicTasteBuilder.build(artists: artists, tracks: [], now: Date(timeIntervalSince1970: 0))
        precondition(taste.topArtists.count == 2, "Deduplicate artist IDs")
        precondition(taste.genres.map(\.name) == ["rock", "pop"], "Normalize tags and rank deterministically")
        precondition(abs(taste.genres[0].weight - 2.0 / 3.0) < 0.000001, "Split each artist's rank vote across tags")
        precondition(abs(taste.genres.map(\.weight).reduce(0, +) - 1) < 0.000001)
        let many = (0..<42).map { artist("artist\($0)", ["genre\($0)"]) }
        let capped = MusicTasteBuilder.build(artists: many, tracks: [])
        precondition(capped.topArtists.count == 10 && capped.topArtists.last?.id == "artist9",
            "Limit new and previously cached profiles to top ten in Spotify rank order")
        precondition(!capped.genres.contains { $0.name == "genre10" }, "Hidden artists must not affect genre ranking")
        let missing = MusicTasteBuilder.build(artists: [artist("A", nil)], tracks: [])
        precondition(missing.genres.isEmpty && missing.summary.contains("A"), "Missing genres still allow artist overview")
        let empty = MusicTasteBuilder.build(artists: [], tracks: [])
        precondition(empty.genres.isEmpty && empty.summary.contains("Not enough"))
        let json = Data(#"{"items":[{"id":"t1","name":"Song","artists":[{"id":"a1","name":"Artist"}],"album":{"name":"Album","images":[]}}]}"#.utf8)
        let page = try JSONDecoder().decode(SpotifyPage<SpotifyTrack>.self, from: json)
        let selected = MusicTasteBuilder.build(artists: [], tracks: page.items + page.items, previousShowcase: "t1")
        precondition(selected.topTracks.count == 1 && selected.showcaseTrack?.id == "t1")
        let expiredSelection = MusicTasteBuilder.build(artists: [], tracks: [], previousShowcase: "t1")
        precondition(expiredSelection.showcaseTrackID == nil, "Removed songs clear showcase")
        let saved = try JSONEncoder().encode(selected)
        let restored = try JSONDecoder().decode(MusicTaste.self, from: saved)
        precondition(restored == selected)
        let drake = artist("3TVXtAsR1Inumwj472S9r4", nil)
        let kanye = artist("5K4W6rqBFWDnAN6FQUkS6x", [])
        let gibbs = artist("0Y4inQK6OespitzD6ijMwb", [" "])
        let fallback = MusicTasteBuilder.build(artists: [drake, kanye, gibbs], tracks: [])
        precondition(fallback.genres.contains { $0.name == "jazz rap" })
        precondition(fallback.genres.contains { $0.name == "experimental hip hop" })
        precondition(fallback.genres.contains { $0.name == "pop rap" })
        precondition(fallback.topArtists.allSatisfy { $0.genreSourceName == "MusicBrainz" })
        let withSpotify = artist("3TVXtAsR1Inumwj472S9r4", ["spotify-specific-tag"])
        precondition(ArtistGenreCatalog.enrich(withSpotify).genres == ["spotify-specific-tag"], "Never overwrite Spotify's supplied tags")
        let sameName = SpotifyArtist(id: "unknown", name: "Drake", genres: nil, external_urls: nil)
        precondition(ArtistGenreCatalog.enrich(sameName).genres == nil, "Resolve by exact Spotify identity, not name")
        let summrs = artist("5L15t6I0PQS9SBXbiklPEN", nil)
        let summrsTaste = MusicTasteBuilder.build(artists: [summrs], tracks: [])
        precondition(summrsTaste.topArtists[0].genres == ["plugg", "pluggnb", "southern hip hop", "trap"],
            "Summrs must receive verified specific genres immediately, including from an older empty cached profile")
        precondition(summrsTaste.topArtists[0].genreSourceURL == "https://musicbrainz.org/artist/d538d883-3889-44ad-8f32-6167cf4d85ec")
        let taggedSummrs = artist(summrs.id, ["user-tag"])
        precondition(MusicTasteBuilder.build(artists: [taggedSummrs], tracks: []).topArtists[0].genres == ["user-tag"],
            "Verified fallback must preserve existing tags")
        let unrelatedSummrs = SpotifyArtist(id: "other-summrs", name: "Summrs", genres: nil, external_urls: nil)
        precondition(ArtistGenreCatalog.enrich(unrelatedSummrs).genres == nil, "Never assign Summrs tags by name alone")
        let oldArtist = Data(#"{"id":"old","name":"Artist","genres":[]}"#.utf8)
        _ = try JSONDecoder().decode(SpotifyArtist.self, from: oldArtist)
        print("Music taste checks passed: genre weighting, normalization, duplicates, missing data, showcase, Codable.")
    }
}
