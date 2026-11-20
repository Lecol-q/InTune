import Foundation
import Combine

@MainActor
final class CommunityStore: ObservableObject {
    static let shared = CommunityStore()
    @Published private(set) var uid: String?
    @Published private(set) var profile: CommunityProfile?
    @Published private(set) var candidates: [CommunityProfile] = []
    @Published private(set) var matches: [CommunityMatch] = []
    @Published private(set) var people: [String: CommunityProfile] = [:]
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var notices: String?
    private let client: FirebaseCommunityClient
    var configured: Bool { client.config.configured }
    init(client: FirebaseCommunityClient? = nil) {
        let resolved = client ?? FirebaseCommunityClient()
        self.client = resolved
        uid = resolved.uid
        DemoSession.shared.setCommunityConnected(uid != nil)
    }

    func signIn(email: String, password: String, create: Bool) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await client.signIn(email: email, password: password, create: create)
            uid = client.uid
            DemoSession.shared.setCommunityConnected(uid != nil)
            profile = nil; candidates = []; matches = []; people = [:]
            try await load()
        } catch { self.error = error.localizedDescription }
    }
    func signOut() {
        guard !busy else { return }
        do {
            try LocalTestProfiles.shared.clear()
            try client.signOut()
            uid = nil
            DemoSession.shared.setCommunityConnected(false)
            profile = nil; candidates = []; matches = []; people = [:]
            error = nil; notices = nil
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard uid != nil, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await load() } catch { self.error = error.localizedDescription }
    }
    private func load() async throws {
        guard let uid else { return }
        profile = try await client.get("profiles/" + uid).flatMap(CommunityProfile.init(document:))
        let documents = try await client.query(collection: "profiles", field: "active", operation: "EQUAL", value: .bool(true))
        let loaded = documents.compactMap(CommunityProfile.init(document:))
        let swipes = try await client.list("swipes/" + uid + "/outgoing")
        let reviewed = Set(swipes.map(\.id))
        candidates = loaded.filter { $0.id != uid && !reviewed.contains($0.id) }
        people = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        matches = try await fetchMatches(uid: uid)
        // Recover a mutual like if either client lost its response before creating a match.
        if profile?.active == true {
            let activeIDs = Set(loaded.map(\.id))
            for swipe in swipes where swipe.fields["decision"]?.stringValue == "like" && activeIDs.contains(swipe.id) {
                let id = CommunityMatch.identifier(uid, swipe.id)
                if !matches.contains(where: { $0.id == id }),
                   let reverse = try await client.get("swipes/\(swipe.id)/outgoing/\(uid)"),
                   reverse.fields["decision"]?.stringValue == "like" {
                    try await createMatch(uid: uid, other: swipe.id)
                }
            }
            matches = try await fetchMatches(uid: uid)
        }
        // Hidden profiles may still be readable by their existing match partner.
        for match in matches {
            if let other = match.otherID(than: uid), people[other] == nil,
               let document = try await client.get("profiles/" + other), let person = CommunityProfile(document: document) {
                people[other] = person
            }
        }
    }
    private func fetchMatches(uid: String) async throws -> [CommunityMatch] {
        try await client.query(collection: "matches", field: "members", operation: "ARRAY_CONTAINS", value: .string(uid))
            .compactMap { document in
                let members = document.fields["members"]?.strings ?? []
                guard members.count == 2, members.contains(uid) else { return nil }
                return CommunityMatch(id: document.id, members: members,
                    createdAt: Self.date(document.fields["createdAt"]?.timestampValue))
            }.sorted { $0.createdAt > $1.createdAt }
    }

    func publish(name: String, age: Int, bio: String, taste: MusicTaste?) async {
        guard let uid, !busy else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 60, (18...120).contains(age), bio.count <= 500 else {
            error = "Use a name up to 60 characters, age 18–120, and a bio up to 500 characters."; return
        }
        busy = true; error = nil; notices = nil
        defer { busy = false }
        let next = CommunityProfile(id: uid, name: cleaned, age: age, bio: bio,
            artists: taste?.topArtists.prefix(10).map(\.name) ?? [],
            genres: taste?.genres.prefix(12).map(\.name) ?? [],
            showcase: taste?.showcaseTrack.map { $0.name + " — " + $0.artists.map(\.name).joined(separator: ", ") } ?? "",
            active: true)
        do {
            try await client.put("profiles/" + uid, fields: next.fields)
            profile = next
            notices = "Your profile is shared with signed-in InTune users on this Firebase project."
            try await load()
        } catch { self.error = error.localizedDescription }
    }
    func hideProfile() async {
        guard let uid, var next = profile, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        next.active = false
        do {
            try await client.put("profiles/" + uid, fields: next.fields)
            profile = next
            notices = "Your profile is hidden from discovery. Existing matches can still chat."
        } catch { self.error = error.localizedDescription }
    }

    func swipe(_ person: CommunityProfile, like: Bool) async {
        guard let uid, !busy else { return }
        guard profile?.active == true else { error = "Share your profile before swiping."; return }
        busy = true; error = nil; notices = nil
        defer { busy = false }
        do {
            try await client.put("swipes/\(uid)/outgoing/\(person.id)", fields: [
                "fromID": .string(uid), "toID": .string(person.id), "decision": .string(like ? "like" : "pass")
            ], timestamp: "createdAt")
            candidates.removeAll { $0.id == person.id }
            if like, let reverse = try await client.get("swipes/\(person.id)/outgoing/\(uid)"),
               reverse.fields["decision"]?.stringValue == "like" {
                try await createMatch(uid: uid, other: person.id)
                notices = "You matched with \(person.name)! Open Matches to send a message."
            }
            matches = try await fetchMatches(uid: uid)
        } catch { self.error = error.localizedDescription }
    }

    private func createMatch(uid: String, other: String) async throws {
        let id = CommunityMatch.identifier(uid, other)
        do {
            try await client.put("matches/" + id, fields: ["members": .strings([uid, other].sorted())],
                                 timestamp: "createdAt", createOnly: true)
        } catch {
            let existing = try await fetchMatches(uid: uid)
            guard existing.contains(where: { $0.id == id }) else { throw error }
        }
    }

    func messages(in match: CommunityMatch) async throws -> [CommunityMessage] {
        guard let uid, match.members.contains(uid) else { throw CommunityError(message: "This chat is not available to your account.") }
        return try await client.list("matches/\(match.id)/messages", orderBy: "sentAt")
            .compactMap { doc in
                guard let text = doc.fields["text"]?.stringValue, let sender = doc.fields["senderID"]?.stringValue else { return nil }
                return CommunityMessage(id: doc.id, senderID: sender, text: text,
                                        sentAt: Self.date(doc.fields["sentAt"]?.timestampValue))
            }
    }
    func send(_ text: String, in match: CommunityMatch, messageID: String) async throws {
        guard let uid, match.members.contains(uid) else { throw CommunityError(message: "Match before messaging.") }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 2000 else { throw CommunityError(message: "Messages must contain 1–2,000 characters.") }
        try await client.put("matches/\(match.id)/messages/\(messageID)", fields: ["senderID": .string(uid), "text": .string(cleaned)],
                             timestamp: "sentAt", createOnly: true)
    }
    private static func date(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
