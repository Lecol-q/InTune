import Foundation

@main struct ArtistGenreCorrectionChecks {
    static func main() throws {
        let artist = SpotifyArtist(id: "fixture", name: "Fixture", genres: ["hip hop"], external_urls: nil)
        let tags = ArtistGenreCorrection.parse(" Jazz Rap, jazz rap,\n Alternative Hip Hop ,  ")
        precondition(tags == ["jazz rap", "alternative hip hop"])
        let saved = [artist.id: ArtistGenreCorrection(tags: tags, original: artist)]
        let reloaded = try JSONDecoder().decode([String: ArtistGenreCorrection].self,
            from: JSONEncoder().encode(saved))
        let edited = ArtistGenreCorrection.apply(reloaded, to: [artist])[0]
        precondition(edited.genres == tags && edited.genreSourceName == "Your tags" && edited.genreSourceURL == nil)
        precondition(reloaded[artist.id]?.original == artist, "Preserve original metadata for restoring catalog tags")
        var refreshed = artist
        refreshed.genres = ["rap"]
        precondition(ArtistGenreCorrection.apply(reloaded, to: [refreshed])[0].genres == tags,
            "Saved edits must survive a new Spotify import")
        let other = SpotifyArtist(id: "other", name: "Other", genres: ["pop"], external_urls: nil)
        precondition(ArtistGenreCorrection.apply(reloaded, to: [other])[0] == other,
            "Edits must be scoped to exact artist identity")
        print("Artist correction checks passed: parsing, persistence round trip, source attribution, original metadata, refresh precedence, artist identity.")
    }
}
