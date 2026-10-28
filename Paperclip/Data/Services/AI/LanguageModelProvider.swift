import Foundation

enum AIProviderAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var userFacingMessage: String {
        switch self {
        case .available:
            return "Apple Foundation Models are available on this Mac."
        case .unavailable(let reason):
            return reason
        }
    }
}

/// Abstraction over on-device (or, only ever by explicit opt-in, remote) language models.
protocol LanguageModelProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var availability: AIProviderAvailability { get }

    func classify(text: String, contentType: ClipContentType, sourceApp: String?) async throws -> AIClassificationResult
    func summarize(text: String) async throws -> String
    func generateTags(text: String, contentType: ClipContentType) async throws -> [String]
    func rewrite(text: String, style: SmartRewriteStyle) async throws -> String
    func interpretQuery(_ query: String) async throws -> AIQueryInterpretation
}
