import Foundation

/// Which smart actions make sense for a clip, given its type and (optional) AI category.
enum SmartActionCatalog {
    static func actions(for clip: ClipItem, metadata: AIMemoryMetadata?) -> [SmartRewriteStyle] {
        let category = metadata?.category
        switch clip.contentType {
        case .image:
            // Actions operate on OCR text; nothing to do without it.
            return (clip.searchableText?.isEmpty == false) ? [.summarize, .extractKeyPoints, .explain] : []
        case .file:
            return []
        case .link:
            return [.summarize, .explain]
        case .text:
            break
        }

        switch category {
        case .sql, .code, .shell, .command:
            return [.explainCode, .findBugs, .refactor, .optimize, .addComments, .unitTests]
        case .json:
            return [.formatJSON, .explainJSON, .generateSwiftModel, .generateTypeScriptType]
        case .xml, .configuration:
            return [.explain, .summarize]
        case .email, .meetingNotes, .article, .documentation, .markdown, .plainText, .none:
            return [.summarize, .rewrite, .improveGrammar, .professional, .concise, .extractKeyPoints, .translate, .explain]
        case .url:
            return [.summarize, .concise]
        case .credentials:
            return []
        default:
            return [.summarize, .explain, .rewrite]
        }
    }
}
