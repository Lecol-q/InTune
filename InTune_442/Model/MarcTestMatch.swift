import Foundation
import Combine

struct TestChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let sentByMe: Bool
    let createdAt: Date
}

/// Explicitly local test fixture. It never creates a real user, match, or network message.
@MainActor
final class MarcTestMatch: ObservableObject {
    static let shared = MarcTestMatch()
    struct Snapshot: Codable {
        var matched = false
        var passed = false
        var messages: [TestChatMessage] = []
    }
    @Published private(set) var state: Snapshot
    @Published private(set) var error: String?
    private let persist: (Snapshot) throws -> Void

    init(initial: Snapshot? = nil, persist: ((Snapshot) throws -> Void)? = nil) {
        state = initial ?? (try? MusicVault.read("marc-test-match", as: Snapshot.self)) ?? Snapshot()
        self.persist = persist ?? { try MusicVault.write($0, key: "marc-test-match") }
    }

    @discardableResult func like(connected: Bool) -> Bool {
        guard connected else { return false }
        if state.matched { return true }
        var next = state
        next.matched = true
        next.passed = false
        next.messages = [TestChatMessage(id: UUID(),
            text: "Yo! What have you been listening to lately?", sentByMe: false, createdAt: Date())]
        return save(next)
    }
    func pass(connected: Bool) {
        guard connected, !state.matched else { return }
        var next = state
        next.passed = true
        _ = save(next)
    }
    func showCardAgain() {
        guard !state.matched else { return }
        var next = state
        next.passed = false
        _ = save(next)
    }
    @discardableResult func send(_ text: String, connected: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard connected, state.matched, !trimmed.isEmpty, trimmed.count <= 2000 else { return false }
        var next = state
        next.messages.append(TestChatMessage(id: UUID(), text: trimmed, sentByMe: true, createdAt: Date()))
        return save(next)
    }
    func clear() throws {
        try MusicVault.delete("marc-test-match")
        state = Snapshot()
        error = nil
    }
    private func save(_ next: Snapshot) -> Bool {
        do {
            try persist(next)
            state = next
            error = nil
            return true
        } catch {
            self.error = "Could not save the test conversation. Please try again."
            return false
        }
    }
}
