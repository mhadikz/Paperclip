import Foundation

/// Coordinates provider selection and high-level AI operations for the app.
/// Heuristics run first; Apple Foundation Models refine when enabled and available.
actor AIService: AIMemoryServicing {
    private let heuristic: any LanguageModelProvider
    private let apple: any LanguageModelProvider

    init(
        heuristic: any LanguageModelProvider = HeuristicLanguageModelProvider(),
        apple: any LanguageModelProvider = AppleFoundationModelsProvider()
    ) {
        self.heuristic = heuristic
        self.apple = apple
    }

    private func activeProvider(useAI: Bool) -> any LanguageModelProvider {
        if useAI, apple.availability.isAvailable {
            return apple
        }
        return heuristic
    }

    func activeProviderID(useAI: Bool) -> String {
        activeProvider(useAI: useAI).id
    }

    func availabilityMessage() -> String {
        apple.availability.userFacingMessage
    }

    func isFoundationModelsAvailable() -> Bool {
        apple.availability.isAvailable
    }

    func classify(clip: ClipItem, useAI: Bool) async -> AIClassificationResult {
        let base = HeuristicClassifier.classify(clip: clip)
        guard useAI, let text = primaryText(for: clip), !text.isEmpty else {
            return base
        }
        // Heuristics are definitive for structured content; the model adds value for prose.
        if [.sql, .json, .xml, .shell, .url, .credentials, .image, .file, .phoneNumber].contains(base.category) {
            return base
        }
        do {
            var refined = try await activeProvider(useAI: true).classify(
                text: text,
                contentType: clip.contentType,
                sourceApp: clip.sourceAppName
            )
            if refined.tags.isEmpty { refined.tags = base.tags }
            if refined.codeLanguage == nil { refined.codeLanguage = base.codeLanguage }
            return refined
        } catch {
            AppLogger.error("Model classification failed; using heuristics", logger: AppLogger.ai)
            return base
        }
    }

    func summarize(clip: ClipItem, useAI: Bool) async -> String? {
        guard let text = primaryText(for: clip) else { return nil }
        guard text.count >= 160 else { return nil }
        let fallback = String(text.prefix(140)) + "…"
        guard useAI else { return fallback }
        do {
            let summary = try await activeProvider(useAI: true).summarize(text: text)
            return summary.isEmpty ? fallback : summary
        } catch {
            return fallback
        }
    }

    func rewrite(text: String, style: SmartRewriteStyle, useAI: Bool) async throws -> String {
        if style.isDeterministic {
            return try await heuristic.rewrite(text: text, style: style)
        }
        return try await activeProvider(useAI: useAI).rewrite(text: text, style: style)
    }

    func interpretQuery(_ query: String, useAI: Bool) async -> AIQueryInterpretation {
        let fallback = QueryInterpreter.heuristic(query)
        guard useAI, apple.availability.isAvailable else { return fallback }
        do {
            return try await apple.interpretQuery(query)
        } catch {
            return fallback
        }
    }

    private func primaryText(for clip: ClipItem) -> String? {
        switch clip.contentType {
        case .text, .link, .file:
            return clip.text
        case .image:
            return clip.searchableText
        }
    }
}
