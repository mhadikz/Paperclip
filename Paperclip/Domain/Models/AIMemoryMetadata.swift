import Foundation

enum AIProcessingStatus: String, Codable, Hashable {
    case pending
    case processing
    case completed
    case skipped
    case failed
    case unavailable
}

/// AI-generated metadata for a clipboard item. Does not duplicate clip content.
struct AIMemoryMetadata: Identifiable, Codable, Equatable, Hashable {
    var id: UUID { clipID }

    let clipID: UUID
    var status: AIProcessingStatus
    var category: MemoryCategory?
    var tags: [String]
    var summary: String?
    var language: String?
    var codeLanguage: String?
    var entities: [String]
    var importance: Double
    var isFavorite: Bool
    var searchableRepresentation: String?
    var processedAt: Date?
    var modelIdentifier: String?
    var promptVersion: String?
    var lastError: String?

    init(
        clipID: UUID,
        status: AIProcessingStatus = .pending,
        category: MemoryCategory? = nil,
        tags: [String] = [],
        summary: String? = nil,
        language: String? = nil,
        codeLanguage: String? = nil,
        entities: [String] = [],
        importance: Double = 0.5,
        isFavorite: Bool = false,
        searchableRepresentation: String? = nil,
        processedAt: Date? = nil,
        modelIdentifier: String? = nil,
        promptVersion: String? = nil,
        lastError: String? = nil
    ) {
        self.clipID = clipID
        self.status = status
        self.category = category
        self.tags = tags
        self.summary = summary
        self.language = language
        self.codeLanguage = codeLanguage
        self.entities = entities
        self.importance = importance
        self.isFavorite = isFavorite
        self.searchableRepresentation = searchableRepresentation
        self.processedAt = processedAt
        self.modelIdentifier = modelIdentifier
        self.promptVersion = promptVersion
        self.lastError = lastError
    }

    var memorySearchBlob: String {
        [
            category?.title,
            tags.joined(separator: " "),
            summary,
            language,
            codeLanguage,
            entities.joined(separator: " "),
            searchableRepresentation
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    mutating func replaceTags(_ newTags: [String]) {
        tags = AIMemoryMetadata.normalizeTags(newTags)
    }

    static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
            if result.count >= 8 { break }
        }
        return result
    }
}
