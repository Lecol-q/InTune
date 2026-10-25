import Foundation

struct CommunityProfile: Identifiable, Equatable {
    let id: String
    var name: String
    var age: Int
    var bio: String
    var artists: [String]
    var genres: [String]
    var showcase: String
    var active: Bool
}
struct CommunityMatch: Identifiable, Equatable {
    let id: String
    let members: [String]
    let createdAt: Date
    func otherID(than uid: String) -> String? { members.first { $0 != uid } }
    static func identifier(_ first: String, _ second: String) -> String {
        [first, second].sorted().joined(separator: "__")
    }
}
struct CommunityMessage: Identifiable, Equatable {
    let id: String
    let senderID: String
    let text: String
    let sentAt: Date
}

struct FirebaseCommunityConfig: Codable {
    let projectID: String
    let apiKey: String
    var configured: Bool {
        !projectID.isEmpty && !apiKey.isEmpty &&
        projectID.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
    }
    static func load() -> Self {
        guard let url = Bundle.main.url(forResource: "CommunityConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(projectID: "", apiKey: "")
        }
        return config
    }
}

struct CommunityError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Explicit allowlist for fields published before matching. No photos or tokens.
struct FirestoreValue: Codable, Equatable {
    struct ArrayValue: Codable, Equatable { var values: [FirestoreValue]? }
    var stringValue: String?
    var integerValue: String?
    var booleanValue: Bool?
    var timestampValue: String?
    var arrayValue: ArrayValue?
    static func string(_ value: String) -> Self { Self(stringValue: value) }
    static func integer(_ value: Int) -> Self { Self(integerValue: String(value)) }
    static func bool(_ value: Bool) -> Self { Self(booleanValue: value) }
    static func strings(_ values: [String]) -> Self { Self(arrayValue: ArrayValue(values: values.map(Self.string))) }
    var strings: [String] { arrayValue?.values?.compactMap(\.stringValue) ?? [] }
}

struct FirestoreDocument: Codable {
    let name: String
    let fields: [String: FirestoreValue]
    var id: String { name.components(separatedBy: "/").last ?? "" }
}

extension CommunityProfile {
    var fields: [String: FirestoreValue] {
        ["ownerID": .string(id), "name": .string(name), "age": .integer(age),
         "bio": .string(bio), "artists": .strings(Array(artists.prefix(10))),
         "genres": .strings(Array(genres.prefix(12))), "showcase": .string(showcase), "active": .bool(active)]
    }
    init?(document: FirestoreDocument) {
        let f = document.fields
        guard let name = f["name"]?.stringValue, let age = Int(f["age"]?.integerValue ?? ""),
              f["ownerID"]?.stringValue == document.id else { return nil }
        self.init(id: document.id, name: name, age: age, bio: f["bio"]?.stringValue ?? "",
                  artists: f["artists"]?.strings ?? [], genres: f["genres"]?.strings ?? [],
                  showcase: f["showcase"]?.stringValue ?? "", active: f["active"]?.booleanValue ?? false)
    }
}
