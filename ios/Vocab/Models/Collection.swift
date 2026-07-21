import Foundation

struct WordCollection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var targetLanguage: String
    var nativeLanguage: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        targetLanguage: String,
        nativeLanguage: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.targetLanguage = targetLanguage
        self.nativeLanguage = nativeLanguage
        self.createdAt = createdAt
    }
}
