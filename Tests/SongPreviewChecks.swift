import Foundation

final class PreviewMock: URLProtocol {
    static var count = 0
    static var results: String = "[]"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        precondition(request.url?.host == "itunes.apple.com")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        let data = Data(("{\"results\":" + Self.results + "}").utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct SongPreviewChecks {
    @MainActor static func main() async throws {
        let sample = #"{"trackId":997914096,"trackName":"Space Song","artistName":"Beach House","previewUrl":"https://audio-ssl.itunes.apple.com/preview.m4a","artworkUrl100":"https://is1-ssl.mzstatic.com/art.jpg","trackViewUrl":"https://music.apple.com/us/song/997914096"}"#
        let info = try JSONDecoder().decode(SongPreviewMetadata.self, from: Data(sample.utf8))
        let song = ShowcaseSong(title: "Space Song", artist: "Beach House", appleTrackID: 997914096)
        precondition(info.matches(song) && info.audioURL != nil && info.storeURL != nil && info.artworkURL != nil)
        precondition(!info.matches(ShowcaseSong(title: "Space Song (Remix)", artist: "Beach House")))
        precondition(!info.matches(ShowcaseSong(title: "Space Song", artist: "Someone Else")))
        precondition(ShowcaseSong.shared("Snooze — SZA")?.artist == "SZA")
        precondition(ShowcaseSong.shared("unstructured old text") == nil)
        let direct = ShowcaseSong(title: "Snooze", artist: "SZA", spotifyURL: "https://open.spotify.com/track/fixture")
        precondition(direct.spotifyDestination.absoluteString == "https://open.spotify.com/track/fixture")
        let escaped = ShowcaseSong(title: "Song / ? # %", artist: "A & B")
        precondition(escaped.spotifyDestination.host == "open.spotify.com")
        precondition(escaped.spotifyDestination.query == nil && escaped.spotifyDestination.fragment == nil)
        let unsafeLink = ShowcaseSong(title: "Snooze", artist: "SZA", spotifyURL: "https://other.example/track/fixture")
        precondition(unsafeLink.directSpotifyURL == nil && unsafeLink.spotifyDestination.host == "open.spotify.com")
        let track = SpotifyTrack(id: "fixture", name: "Snooze", artists: [SpotifyArtist(id: "artist", name: "SZA", genres: nil,
            external_urls: nil)], album: .init(name: "SOS", images: []), external_urls: ["spotify":"https://open.spotify.com/track/fixture"])
        precondition(ShowcaseSong.selected(track).title == "Snooze")
        precondition(ShowcaseSong.selected(track).spotifyURL == "https://open.spotify.com/track/fixture")
        let unsafe = sample.replacingOccurrences(of: "https://audio-ssl.itunes.apple.com/preview.m4a", with: "http://other.example/preview.m4a")
        let unsafeInfo = try JSONDecoder().decode(SongPreviewMetadata.self, from: Data(unsafe.utf8))
        precondition(unsafeInfo.audioURL == nil)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PreviewMock.self]
        let service = SongPreviewService(http: URLSession(configuration: config))
        PreviewMock.results = "[" + sample + "]"
        let loaded = try await service.lookup(song, country: "US")
        precondition(loaded?.trackId == song.appleTrackID)
        _ = try await service.lookup(song, country: "US")
        precondition(PreviewMock.count == 1, "Cache metadata, not audio")
        let wrong = try await service.lookup(ShowcaseSong(title: "Snooze", artist: "SZA"), country: "US")
        precondition(wrong == nil, "Don't play another song when exact matching fails")
        if CommandLine.arguments.count > 1 {
            struct Lookup: Decodable { let results: [SongPreviewMetadata] }
            let live = try JSONDecoder().decode(Lookup.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            let chosen = [song, ShowcaseSong(title: "Snooze", artist: "SZA", appleTrackID: 1796270661),
                          ShowcaseSong(title: "Crime Pays", artist: "Freddie Gibbs & Madlib", appleTrackID: 1464243887)]
            for selection in chosen {
                precondition(live.results.contains { $0.matches(selection) && $0.audioURL != nil && $0.storeURL != nil })
            }
        }
        print("Song preview checks passed: exact song/artist matching, safe media URLs, selected-song preservation, shared-profile parsing, lookup, metadata caching, live test-song availability.")
    }
}
