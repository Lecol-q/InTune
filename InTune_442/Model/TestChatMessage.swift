import Foundation

struct TestChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let sentByMe: Bool
    let createdAt: Date
}
