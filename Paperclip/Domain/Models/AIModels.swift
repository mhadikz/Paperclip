import Foundation

/// Result of classifying one clip (heuristics or a language model).
struct AIClassificationResult: Equatable, Sendable {
    var category: MemoryCategory
    var tags: [String]
    var summary: String?
    var language: String?
    var codeLanguage: String?
    var entities: [String]
    var importance: Double
}

/// Retrieval cues extracted from a natural-language query.
struct AIQueryInterpretation: Equatable, Sendable {
    var keywords: [String]
    var category: MemoryCategory?
    var sourceAppHint: String?
    var relativeTime: RelativeTimeHint
    var intent: String

    enum RelativeTimeHint: String, Equatable, Sendable {
        case any
        case today
        case yesterday
        case lastWeek
        case lastMonth
    }
}

/// Contextual transformations offered in the memory detail pane.
enum SmartRewriteStyle: String, CaseIterable, Identifiable, Sendable {
    case summarize
    case rewrite
    case improveGrammar
    case professional
    case concise
    case explain
    case translate
    case extractKeyPoints
    case explainCode
    case findBugs
    case refactor
    case optimize
    case unitTests
    case addComments
    case formatJSON
    case explainJSON
    case generateSwiftModel
    case generateTypeScriptType

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: return "Summarize"
        case .rewrite: return "Rewrite"
        case .improveGrammar: return "Improve Grammar"
        case .professional: return "Make Professional"
        case .concise: return "Make Concise"
        case .explain: return "Explain"
        case .translate: return "Translate"
        case .extractKeyPoints: return "Extract Key Points"
        case .explainCode: return "Explain Code"
        case .findBugs: return "Find Potential Bugs"
        case .refactor: return "Refactor"
        case .optimize: return "Optimize"
        case .unitTests: return "Generate Unit Tests"
        case .addComments: return "Add Comments"
        case .formatJSON: return "Format JSON"
        case .explainJSON: return "Explain JSON"
        case .generateSwiftModel: return "Generate Swift Model"
        case .generateTypeScriptType: return "Generate TypeScript Type"
        }
    }

    var systemImage: String {
        switch self {
        case .summarize: return "text.redaction"
        case .rewrite: return "pencil.line"
        case .improveGrammar: return "textformat.abc"
        case .professional: return "briefcase"
        case .concise: return "arrow.down.right.and.arrow.up.left"
        case .explain: return "questionmark.bubble"
        case .translate: return "globe"
        case .extractKeyPoints: return "list.bullet"
        case .explainCode: return "chevron.left.forwardslash.chevron.right"
        case .findBugs: return "ant"
        case .refactor: return "arrow.triangle.2.circlepath"
        case .optimize: return "speedometer"
        case .unitTests: return "checkmark.shield"
        case .addComments: return "text.bubble"
        case .formatJSON: return "curlybraces"
        case .explainJSON: return "curlybraces.square"
        case .generateSwiftModel: return "swift"
        case .generateTypeScriptType: return "t.square"
        }
    }

    /// Instruction sent to the model. Deterministic styles are handled locally first.
    var promptAction: String {
        switch self {
        case .summarize: return "Summarize"
        case .rewrite: return "Rewrite clearly"
        case .improveGrammar: return "Improve grammar and spelling"
        case .professional: return "Rewrite in a professional tone"
        case .concise: return "Make shorter while keeping meaning"
        case .explain: return "Explain"
        case .translate: return "Translate to English if needed, otherwise keep English and clarify"
        case .extractKeyPoints: return "Extract key points as a short bullet list"
        case .explainCode: return "Explain this code"
        case .findBugs: return "Find potential bugs"
        case .refactor: return "Refactor for clarity"
        case .optimize: return "Suggest optimizations"
        case .unitTests: return "Generate unit tests"
        case .addComments: return "Add helpful comments"
        case .formatJSON: return "Format this JSON prettily"
        case .explainJSON: return "Explain this JSON structure"
        case .generateSwiftModel: return "Generate a Swift Codable model"
        case .generateTypeScriptType: return "Generate a TypeScript type"
        }
    }

    /// Works without any language model.
    var isDeterministic: Bool {
        self == .formatJSON
    }
}

enum AIProviderError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case unsupported(String)
    case generationFailed(String)
    case refused

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .unsupported(let message): return message
        case .generationFailed(let message): return message
        case .refused: return "The on-device model declined to process this content."
        }
    }
}
