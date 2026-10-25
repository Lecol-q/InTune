import Foundation

enum MusicVault {
    static var deleted: [String] = []
    static func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? { nil }
    static func write<T: Encodable>(_ value: T, key: String) throws {}
    static func delete(_ key: String) throws { deleted.append(key) }
}
@main struct LocalTestProfileChecks {
    @MainActor static func main() throws {
        var saved: [String: LocalTestProfiles.Entry] = [:]
        let tests = LocalTestProfiles(initial: [:], persist: { saved = $0 })
        let people = LocalTestProfile.women
        precondition(people.count == 3 && Set(people.map(\.id)).count == 3)
        precondition(people.allSatisfy { $0.age >= 18 })
        precondition(!tests.like(people[0], signedIn: false))
        precondition(!tests.send("hello", to: people[0], signedIn: true))
        tests.pass(people[1], signedIn: true)
        precondition(tests.remaining.count == 2)
        precondition(tests.like(people[0], signedIn: true))
        tests.restorePassed()
        precondition(tests.isMatched(people[0]) && tests.remaining.count == 2)
        for person in people {
            precondition(tests.like(person, signedIn: true))
            precondition(tests.messages(for: person).count == 1)
            precondition(tests.messages(for: person)[0].text == person.greeting)
            precondition(!tests.messages(for: person)[0].sentByMe)
            precondition(tests.like(person, signedIn: true))
            precondition(tests.messages(for: person).count == 1, "Don't repeat scripted greetings")
        }
        precondition(tests.matched.count == 3 && tests.remaining.isEmpty)
        precondition(tests.send("  hi Ava  ", to: people[0], signedIn: true))
        precondition(tests.messages(for: people[0]).last?.text == "hi Ava")
        precondition(tests.messages(for: people[1]).count == 1 && tests.messages(for: people[2]).count == 1)
        precondition(!tests.send("hello", to: people[1], signedIn: false))
        precondition(!tests.send(" \n ", to: people[1], signedIn: true))
        precondition(!tests.send(String(repeating: "x", count: 2001), to: people[1], signedIn: true))
        let stored = try JSONEncoder().encode(saved)
        let restored = LocalTestProfiles(initial: try JSONDecoder().decode([String: LocalTestProfiles.Entry].self, from: stored), persist: { _ in })
        precondition(restored.matched.count == 3 && restored.messages(for: people[0]).count == 2)
        struct SaveError: Error {}
        let failing = LocalTestProfiles(initial: [:], persist: { _ in throw SaveError() })
        precondition(!failing.like(people[0], signedIn: true) && failing.matched.isEmpty && failing.error != nil)
        try restored.clear()
        precondition(restored.matched.isEmpty && restored.remaining.count == 3)
        precondition(MusicVault.deleted == ["test-profile-matches"])
        print("Local test profile checks passed: three adult fixtures, sign-in gate, automatic matches, first messages, separate chats, persistence, validation, reset, save failures.")
    }
}
