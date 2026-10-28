import Foundation

/// Centralized prompts for on-device language models. Bump `AIPromptVersion.current`
/// (Domain) when wording changes materially so stale metadata can be reprocessed.
enum AIPrompts {
    static let classifierInstructions = """
    You classify clipboard snippets for a private macOS clipboard manager.
    Return ONLY compact JSON with keys:
    category (one of: plainText,url,email,code,sql,json,xml,markdown,command,shell,configuration,address,phoneNumber,financial,credentials,documentation,meetingNotes,article,shopping,travel,image,file,other),
    tags (array of up to 6 short tags),
    summary (one short sentence or empty if content is already short),
    language (ISO language code if clear),
    codeLanguage (programming language if code, else empty),
    entities (up to 6 notable proper nouns or identifiers),
    importance (0 to 1).
    Never invent secrets. Never repeat passwords. Keep tags short and useful.
    """

    static func classificationPrompt(contentType: String, sourceApp: String?, text: String) -> String {
        let app = sourceApp ?? "Unknown"
        let body = String(text.prefix(3500))
        return """
        Content type: \(contentType)
        Source app: \(app)
        Clipboard text:
        ---
        \(body)
        ---
        """
    }

    static let summaryInstructions = """
    Summarize the clipboard text in one concise sentence for later retrieval.
    Do not invent facts. If the text is already a short title-like phrase, return it unchanged.
    """

    static let taggingInstructions = """
    Generate up to 6 short useful tags for this clipboard snippet.
    Return ONLY a JSON array of strings, e.g. ["SQL","PostgreSQL"].
    """

    static let queryInstructions = """
    You turn a natural-language request into retrieval cues for a clipboard history.
    Return ONLY compact JSON with keys:
    keywords (array of lowercase search terms),
    category (one of the clipboard categories or null),
    sourceAppHint (app name or null),
    relativeTime (one of: any,today,yesterday,lastWeek,lastMonth or null),
    intent (short phrase).
    Do not include clipboard content. Focus on retrieval cues.
    """

    static func queryPrompt(_ query: String) -> String {
        "User query: \(query)"
    }

    static let rewriteInstructions = """
    Rewrite the text as requested. Preserve meaning. Return only the rewritten text.
    """

    static func rewritePrompt(action: String, text: String) -> String {
        "Action: \(action)\n\nText:\n\(String(text.prefix(4000)))"
    }
}
