import Foundation

enum MusicVault {
    static var deletedKeys: [String] = []
    static func read<T: Decodable>(_ key: String, as: T.Type) throws -> T? { nil }
    static func write<T: Encodable>(_ value: T, key: String) throws {}
    static func delete(_ key: String) throws { deletedKeys.append(key) }
}

@main struct MarcMatchChecks {
    @MainActor static func main() throws {
        var saved = MarcTestMatch.Snapshot()
        let match = MarcTestMatch(initial: saved, persist: { saved = $0 })
        precondition(!match.like(connected: false))
        precondition(!match.send("hello", connected: true), "No messages before matching")
        match.pass(connected: true)
        precondition(match.state.passed && !match.state.matched)
        match.showCardAgain()
        precondition(!match.state.passed)
        precondition(match.like(connected: true))
        precondition(match.state.matched && match.state.messages.count == 1)
        precondition(match.like(connected: true))
        precondition(match.state.messages.count == 1, "Repeat likes must not duplicate the greeting")
        precondition(!match.send("   \n", connected: true))
        precondition(!match.send("hello", connected: false))
        precondition(!match.send(String(repeating: "x", count: 2001), connected: true))
        precondition(match.send("  What underground projects are you into?  ", connected: true))
        precondition(match.state.messages.last?.text == "What underground projects are you into?")
        precondition(match.state.messages.last?.sentByMe == true)
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(MarcTestMatch.Snapshot.self, from: data)
        let restored = MarcTestMatch(initial: loaded, persist: { _ in })
        precondition(restored.state.matched && restored.state.messages.count == 2)
        match.pass(connected: true)
        precondition(match.state.matched && !match.state.passed)
        struct SaveFailure: Error {}
        let failing = MarcTestMatch(initial: .init(), persist: { _ in throw SaveFailure() })
        precondition(!failing.like(connected: true) && !failing.state.matched && failing.error != nil)
        try restored.clear()
        precondition(!restored.state.matched && restored.state.messages.isEmpty)
        precondition(MusicVault.deletedKeys == ["marc-test-match"])
        print("Marc test checks passed: login gate, pass/retry, matching, idempotency, message validation, persistence, save failures, clearing.")
    }
}
