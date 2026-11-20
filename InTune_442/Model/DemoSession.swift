import Foundation
import Combine

struct DemoPerson: Identifiable {
    let id: String
    let name: String
    let age: Int
    let bio: String
    let taste: MusicTaste
}

/// Fictional fixtures never enter Spotify's credential or imported-profile storage.
enum DemoMusic {
    static let artists: [SpotifyArtist] = [
        .init(id: "demo-artist-1", name: "Velvet Hours", genres: ["indie pop", "dream pop"], external_urls: nil),
        .init(id: "demo-artist-2", name: "June Avenue", genres: ["alternative r&b", "soul"], external_urls: nil),
        .init(id: "demo-artist-3", name: "Satellite Club", genres: ["indie pop", "electronic"], external_urls: nil),
        .init(id: "demo-artist-4", name: "Paper Suns", genres: ["indie rock", "alternative"], external_urls: nil),
        .init(id: "demo-artist-5", name: "Afterglow FM", genres: ["electronic", "dance"], external_urls: nil)
    ]
    static let tracks: [SpotifyTrack] = zip(
        ["Midnight Windows", "Sunday in Stereo", "Passenger Seat", "Golden Static", "Last Train Home"], artists
    ).enumerated().map { index, pair in
        SpotifyTrack(id: "demo-track-\(index)", name: pair.0, artists: [pair.1],
                     album: .init(name: "InTune Sessions", images: []), external_urls: nil)
    }
    static func taste(_ artistIndices: [Int], _ trackIndices: [Int]) -> MusicTaste {
        MusicTasteBuilder.build(artists: artistIndices.map { artists[$0] },
                                tracks: trackIndices.map { tracks[$0] },
                                previousShowcase: tracks[trackIndices[0]].id,
                                now: Date(timeIntervalSince1970: 1792886400))
    }
    static let mine = taste([0, 1, 2, 3], [0, 1, 2, 3])
    static let people: [DemoPerson] = [
        .init(id: "demo-maya", name: "Maya", age: 23,
              bio: "Always making playlists for walks that turn into adventures. Tell me your favorite no-skip album.",
              taste: taste([0, 2, 3], [2, 0, 3])),
        .init(id: "demo-jordan", name: "Jordan", age: 24,
              bio: "Small venues, big headphones, and a coffee before every record-store trip.",
              taste: taste([1, 0, 3], [1, 3, 0])),
        .init(id: "demo-alex", name: "Alex", age: 22,
              bio: "Looking for someone who takes the aux as seriously as the road-trip snacks.",
              taste: taste([4, 2], [4, 2])),
        .init(id: "demo-riley", name: "Riley", age: 25,
              bio: "My ideal night starts with a live band and ends with finding a new favorite song.",
              taste: taste([3, 0], [3, 0]))
    ]
}

@MainActor
final class DemoSession: ObservableObject {
    static let shared = DemoSession()
    @Published private(set) var spotifyConnected = false
    @Published private(set) var communityConnected = false
    var isActive: Bool { enabled && !spotifyConnected && !communityConnected }
    func setCommunityConnected(_ connected: Bool) {
        communityConnected = connected
        if connected { enabled = false }
    }
    func setSpotifyConnected(_ connected: Bool) {
        spotifyConnected = connected
        if connected { enabled = false }
    }
    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "intune.demo.enabled") }
    }
    @Published private(set) var likedIDs: [String] {
        didSet { defaults.set(likedIDs, forKey: "intune.demo.likes") }
    }
    @Published private(set) var passedIDs: [String] {
        didSet { defaults.set(passedIDs, forKey: "intune.demo.passes") }
    }
    @Published var taste: MusicTaste {
        didSet {
            if let data = try? JSONEncoder().encode(taste) { defaults.set(data, forKey: "intune.demo.taste") }
        }
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "intune.demo.enabled") as? Bool ?? true
        likedIDs = defaults.stringArray(forKey: "intune.demo.likes") ?? []
        passedIDs = defaults.stringArray(forKey: "intune.demo.passes") ?? []
        if let data = defaults.data(forKey: "intune.demo.taste"),
           let saved = try? JSONDecoder().decode(MusicTaste.self, from: data) { taste = saved }
        else { taste = DemoMusic.mine }
    }
    var remaining: [DemoPerson] { DemoMusic.people.filter { !likedIDs.contains($0.id) && !passedIDs.contains($0.id) } }
    var liked: [DemoPerson] { DemoMusic.people.filter { likedIDs.contains($0.id) } }
    func decide(_ person: DemoPerson, like: Bool) {
        guard remaining.contains(where: { $0.id == person.id }) else { return }
        if like { likedIDs.append(person.id) } else { passedIDs.append(person.id) }
    }
    func resetCards() { likedIDs = []; passedIDs = [] }
    func selectShowcase(_ id: String?) { taste.showcaseTrackID = id }
    func sharedGenres(with person: DemoPerson) -> [String] {
        let theirs = Set(person.taste.genres.map(\.name))
        return taste.genres.map(\.name).filter { theirs.contains($0) }
    }
}
