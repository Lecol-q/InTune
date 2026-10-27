import Foundation

struct ShowcaseSong: Identifiable, Equatable {
    let title: String
    let artist: String
    var appleTrackID: Int? = nil
    var spotifyURL: String? = nil
    var id: String { "\(title)|\(artist)|\(appleTrackID ?? 0)" }

    var directSpotifyURL: URL? {
        guard let spotifyURL, let url = URL(string: spotifyURL), url.scheme == "https",
              url.host == "open.spotify.com", url.user == nil, url.password == nil else { return nil }
        return url
    }
    var spotifyDestination: URL {
        if let directSpotifyURL { return directSpotifyURL }
        var search = URLComponents(string: "https://open.spotify.com")!
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        search.percentEncodedPath = "/search/" + (title + " " + artist).addingPercentEncoding(withAllowedCharacters: allowed)!
        return search.url!
    }

    static func selected(_ track: SpotifyTrack) -> Self {
        Self(title: track.name, artist: track.artists.map(\.name).joined(separator: ", "),
             spotifyURL: track.external_urls?["spotify"])
    }
    static func shared(_ display: String) -> Self? {
        let parts = display.components(separatedBy: " — ")
        guard parts.count >= 2, let title = parts.first, !title.isEmpty else { return nil }
        let artist = parts.dropFirst().joined(separator: " — ")
        guard !artist.isEmpty else { return nil }
        return Self(title: title, artist: artist)
    }
}

struct SongPreviewMetadata: Decodable, Equatable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let previewUrl: String?
    let artworkUrl100: String?
    let trackViewUrl: String?

    var audioURL: URL? {
        Self.secure(previewUrl, domain: "itunes.apple.com")
    }
    var artworkURL: URL? { Self.secure(artworkUrl100, domain: "mzstatic.com") }
    var storeURL: URL? {
        Self.secure(trackViewUrl, domain: "apple.com")
    }
    private static func secure(_ text: String?, domain: String) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", let host = url.host,
              host == domain || host.hasSuffix("." + domain) else { return nil }
        return url
    }
    func matches(_ song: ShowcaseSong) -> Bool {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        guard !normalized(song.title).isEmpty, !normalized(song.artist).isEmpty else { return false }
        return normalized(trackName) == normalized(song.title) && normalized(artistName) == normalized(song.artist)
    }
}
