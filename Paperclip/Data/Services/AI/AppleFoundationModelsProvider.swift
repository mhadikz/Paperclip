import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Intelligence provider. Soft-depends on macOS 26 + FoundationModels.
struct AppleFoundationModelsProvider: LanguageModelProvider {
    let id = "apple.foundationModels"
    let displayName = "Apple Foundation Models"

    var availability: AIProviderAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: "This Mac is not eligible for Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: "Turn on Apple Intelligence in System Settings to enable on-device AI.")
            case .unavailable(.modelNotReady):
                return .unavailable(reason: "The on-device model is still downloading or not ready.")
            case .unavailable(let other):
                return .unavailable(reason: "Apple Foundation Models unavailable (\(String(describing: other))).")
            @unknown default:
                return .unavailable(reason: "Apple Foundation Models unavailable.")
            }
        }
        #endif
        return .unavailable(reason: "Requires macOS 26 or later with Apple Intelligence.")
    }

    func classify(text: String, contentType: ClipContentType, sourceApp: String?) async throws -> AIClassificationResult {
        let fallback = HeuristicClassifier.classify(
            clip: ClipItem(contentType: contentType, text: text, sourceAppName: sourceApp)
        )
        let raw = try await generate(
            instructions: AIPrompts.classifierInstructions,
            prompt: AIPrompts.classificationPrompt(
                contentType: contentType.rawValue,
                sourceApp: sourceApp,
                text: text
            )
        )
        return Self.parseClassification(raw, fallback: fallback)
    }

    func summarize(text: String) async throws -> String {
        let raw = try await generate(
            instructions: AIPrompts.summaryInstructions,
            prompt: String(text.prefix(4000))
        )
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateTags(text: String, contentType: ClipContentType) async throws -> [String] {
        let raw = try await generate(
            instructions: AIPrompts.taggingInstructions,
            prompt: "Type: \(contentType.rawValue)\n\n\(String(text.prefix(3000)))"
        )
        if let tags = Self.decodeStringArray(raw) {
            return AIMemoryMetadata.normalizeTags(tags)
        }
        return HeuristicClassifier.classify(clip: ClipItem(contentType: contentType, text: text)).tags
    }

    func rewrite(text: String, style: SmartRewriteStyle) async throws -> String {
        try await generate(
            instructions: AIPrompts.rewriteInstructions,
            prompt: AIPrompts.rewritePrompt(action: style.promptAction, text: text)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func interpretQuery(_ query: String) async throws -> AIQueryInterpretation {
        let fallback = QueryInterpreter.heuristic(query)
        let raw = try await generate(
            instructions: AIPrompts.queryInstructions,
            prompt: AIPrompts.queryPrompt(query)
        )
        return Self.parseQuery(raw, fallback: fallback)
    }

    // MARK: - Generation

    private func generate(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = availability else {
                throw AIProviderError.unavailable(availability.userFacingMessage)
            }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return response.content
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal:
                    throw AIProviderError.refused
                case .exceededContextWindowSize:
                    throw AIProviderError.generationFailed("The text is too long for the on-device model.")
                default:
                    throw AIProviderError.generationFailed(error.localizedDescription)
                }
            } catch {
                throw AIProviderError.generationFailed(error.localizedDescription)
            }
        }
        #endif
        throw AIProviderError.unavailable(availability.userFacingMessage)
    }

    // MARK: - Parsing (model output is JSON-in-text; @Generable is not used so CLI builds work)

    static func parseClassification(_ raw: String, fallback: AIClassificationResult) -> AIClassificationResult {
        guard let json = extractJSONObject(raw) else { return fallback }
        let category = (json["category"] as? String).flatMap(MemoryCategory.init(rawValue:)) ?? fallback.category
        let tags = AIMemoryMetadata.normalizeTags((json["tags"] as? [String]) ?? fallback.tags)
        let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = json["language"] as? String
        let codeLanguage = json["codeLanguage"] as? String
        let entities = ((json["entities"] as? [String]) ?? []).prefix(6).map { $0 }
        let importance = (json["importance"] as? Double) ?? fallback.importance
        return AIClassificationResult(
            category: category,
            tags: tags.isEmpty ? fallback.tags : tags,
            summary: (summary?.isEmpty == false) ? summary : fallback.summary,
            language: language?.isEmpty == true ? nil : language,
            codeLanguage: codeLanguage?.isEmpty == true ? nil : codeLanguage,
            entities: entities,
            importance: min(max(importance, 0), 1)
        )
    }

    static func parseQuery(_ raw: String, fallback: AIQueryInterpretation) -> AIQueryInterpretation {
        guard let json = extractJSONObject(raw) else { return fallback }
        let keywords = (json["keywords"] as? [String]) ?? fallback.keywords
        let category = (json["category"] as? String).flatMap(MemoryCategory.init(rawValue:))
        let source = json["sourceAppHint"] as? String
        let relativeRaw = json["relativeTime"] as? String
        let relative = AIQueryInterpretation.RelativeTimeHint(rawValue: relativeRaw ?? "") ?? fallback.relativeTime
        let intent = (json["intent"] as? String) ?? fallback.intent
        return AIQueryInterpretation(
            keywords: keywords.isEmpty ? fallback.keywords : keywords,
            category: category ?? fallback.category,
            sourceAppHint: (source?.isEmpty == false) ? source : fallback.sourceAppHint,
            relativeTime: relative,
            intent: intent
        )
    }

    static func decodeStringArray(_ raw: String) -> [String]? {
        if let data = raw.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }
        return extractJSONArray(raw)
    }

    static func extractJSONObject(_ raw: String) -> [String: Any]? {
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func extractJSONArray(_ raw: String) -> [String]? {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"), start < end else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return nil }
        return array
    }
}
