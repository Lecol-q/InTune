import Foundation
import Combine

struct LocalTestProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let age: Int
    let bio: String
    let genres: [String]
    let showcaseSong: ShowcaseSong
    let greeting: String

    static let women: [LocalTestProfile] = [
        .init(id: "test-ava", name: "Ava", age: 22,
              bio: "Small concerts, long walks, and a playlist for every mood. Send me your favorite late-night song.",
              genres: ["indie pop", "dream pop", "alternative r&b"],
              showcaseSong: ShowcaseSong(title: "Space Song", artist: "Beach House", appleTrackID: 997914096,
                  spotifyURL: "https://open.spotify.com/track/7H0ya83CMmgFcOhw0UB6ow"),
              greeting: "Hey! What's one song you could listen to on repeat all day?"),
        .init(id: "test-maya", name: "Maya", age: 23,
              bio: "R&B and soul on the daily. My favorite way to get to know someone is trading playlists.",
              genres: ["contemporary r&b", "neo soul", "alternative r&b"],
              showcaseSong: ShowcaseSong(title: "Snooze", artist: "SZA", appleTrackID: 1796270661,
                  spotifyURL: "https://open.spotify.com/track/4iZ4pt7kvcaH6Yo8UoZ4s2"),
              greeting: "Hi! We matched 🎶 What have you been listening to lately?"),
        .init(id: "test-zoe", name: "Zoe", age: 24,
              bio: "Dusty samples, underground records, and jazz-rap deep cuts. Always looking for a new project to get lost in.",
              genres: ["underground hip hop", "jazz rap", "boom bap"],
              showcaseSong: ShowcaseSong(title: "Crime Pays", artist: "Freddie Gibbs & Madlib", appleTrackID: 1464243887,
                  spotifyURL: "https://open.spotify.com/track/4w5m4X0OZ2IslxNOgtntTN"),
              greeting: "Hey! Put me onto an underrated album—I need something new for tonight.")
    ]
}

/// Fictional test profiles and scripted greetings; no real messages leave the device.
@MainActor
final class LocalTestProfiles: ObservableObject {
    static let shared = LocalTestProfiles()
    struct Entry: Codable, Equatable {
        var matched = false
        var passed = false
        var messages: [TestChatMessage] = []
    }
    @Published private(set) var entries: [String: Entry]
    @Published private(set) var error: String?
    private let persist: ([String: Entry]) throws -> Void
    init(initial: [String: Entry]? = nil, persist: (([String: Entry]) throws -> Void)? = nil) {
        entries = initial ?? (try? MusicVault.read("test-profile-matches", as: [String: Entry].self)) ?? [:]
        self.persist = persist ?? { try MusicVault.write($0, key: "test-profile-matches") }
    }
    var remaining: [LocalTestProfile] {
        LocalTestProfile.women.filter { entries[$0.id]?.matched != true && entries[$0.id]?.passed != true }
    }
    var matched: [LocalTestProfile] { LocalTestProfile.women.filter { entries[$0.id]?.matched == true } }
    func messages(for profile: LocalTestProfile) -> [TestChatMessage] { entries[profile.id]?.messages ?? [] }
    func isMatched(_ profile: LocalTestProfile) -> Bool { entries[profile.id]?.matched == true }

    @discardableResult func like(_ profile: LocalTestProfile, signedIn: Bool) -> Bool {
        guard signedIn, LocalTestProfile.women.contains(profile) else { return false }
        if isMatched(profile) { return true }
        var next = entries
        next[profile.id] = Entry(matched: true, passed: false, messages: [
            TestChatMessage(id: UUID(), text: profile.greeting, sentByMe: false, createdAt: Date())
        ])
        return save(next)
    }
    func pass(_ profile: LocalTestProfile, signedIn: Bool) {
        guard signedIn, LocalTestProfile.women.contains(profile), !isMatched(profile) else { return }
        var next = entries
        next[profile.id] = Entry(matched: false, passed: true)
        _ = save(next)
    }
    func restorePassed() {
        var next = entries
        for profile in LocalTestProfile.women where next[profile.id]?.passed == true {
            next[profile.id] = Entry()
        }
        _ = save(next)
    }
    @discardableResult func send(_ text: String, to profile: LocalTestProfile, signedIn: Bool) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard signedIn, isMatched(profile), !cleaned.isEmpty, cleaned.count <= 2000 else { return false }
        var next = entries
        next[profile.id]?.messages.append(TestChatMessage(id: UUID(), text: cleaned, sentByMe: true, createdAt: Date()))
        return save(next)
    }
    /// Restart the fictional swipe flow and its chats using the same persistent store.
    @discardableResult func reset() -> Bool { save([:]) }

    func clear() throws {
        try MusicVault.delete("test-profile-matches")
        entries = [:]; error = nil
    }
    private func save(_ next: [String: Entry]) -> Bool {
        do {
            try persist(next)
            entries = next; error = nil
            return true
        } catch {
            self.error = "Couldn't save your test chat. Please try again."
            return false
        }
    }
}
