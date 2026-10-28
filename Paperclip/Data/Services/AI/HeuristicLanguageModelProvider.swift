import Foundation

/// Always-available provider using heuristics. Used when Foundation Models are off/unavailable,
/// and as a fast first pass before optional AI enrichment.
struct HeuristicLanguageModelProvider: LanguageModelProvider {
    let id = "heuristic"
    let displayName = "Heuristic Classifier"

    var availability: AIProviderAvailability { .available }

    func classify(text: String, contentType: ClipContentType, sourceApp: String?) async throws -> AIClassificationResult {
        let clip = ClipItem(contentType: contentType, text: text, sourceAppName: sourceApp)
        return HeuristicClassifier.classify(clip: clip)
    }

    func summarize(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { return trimmed }
        return String(trimmed.prefix(140)) + "…"
    }

    func generateTags(text: String, contentType: ClipContentType) async throws -> [String] {
        try await classify(text: text, contentType: contentType, sourceApp: nil).tags
    }

    func rewrite(text: String, style: SmartRewriteStyle) async throws -> String {
        switch style {
        case .concise:
            return String(text.prefix(280))
        case .formatJSON:
            return try Self.prettyPrintedJSON(text)
        default:
            throw AIProviderError.unsupported("“\(style.title)” needs Apple Intelligence (macOS 26+). Format JSON works everywhere.")
        }
    }

    func interpretQuery(_ query: String) async throws -> AIQueryInterpretation {
        QueryInterpreter.heuristic(query)
    }

    static func prettyPrintedJSON(_ text: String) throws -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else {
            throw AIProviderError.generationFailed("The text is not valid JSON.")
        }
        return string
    }
}
