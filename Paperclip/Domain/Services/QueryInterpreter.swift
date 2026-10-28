import Foundation

/// Extracts retrieval cues (category, app, time window, keywords) from a query without AI.
enum QueryInterpreter {
    static func heuristic(_ query: String) -> AIQueryInterpretation {
        let lower = query.lowercased()
        var category: MemoryCategory?
        var sourceApp: String?
        var relative: AIQueryInterpretation.RelativeTimeHint = .any

        if lower.contains("sql") || lower.contains("query") && lower.contains("database") { category = .sql }
        else if lower.contains("docker") || lower.contains("shell") || lower.contains("command") || lower.contains("terminal") { category = .shell }
        else if lower.contains("github") || lower.contains("url") || lower.contains("link") || lower.contains("website") { category = .url }
        else if lower.contains("email") || lower.contains("mail") { category = .email }
        else if lower.contains("json") { category = .json }
        else if lower.contains("code") || lower.contains("swift") || lower.contains("function") || lower.contains("snippet") { category = .code }
        else if lower.contains("image") || lower.contains("screenshot") || lower.contains("picture") { category = .image }
        else if lower.contains("file") || lower.contains("document") { category = .file }
        else if lower.contains("phone") || lower.contains("number") { category = .phoneNumber }

        let apps: [(String, String)] = [
            ("xcode", "Xcode"), ("terminal", "Terminal"), ("safari", "Safari"), ("chrome", "Chrome"),
            ("slack", "Slack"), ("mail", "Mail"), ("notes", "Notes"), ("datagrip", "DataGrip"),
            ("vscode", "Code"), ("vs code", "Code"), ("cursor", "Cursor"), ("figma", "Figma"),
            ("finder", "Finder"), ("messages", "Messages"), ("teams", "Teams"), ("notion", "Notion")
        ]
        for (needle, name) in apps where lower.contains(needle) {
            sourceApp = name
            break
        }

        if lower.contains("yesterday") { relative = .yesterday }
        else if lower.contains("today") || lower.contains("this morning") { relative = .today }
        else if lower.contains("last week") || lower.contains("past week") || lower.contains("this week") { relative = .lastWeek }
        else if lower.contains("last month") || lower.contains("past month") || lower.contains("this month") { relative = .lastMonth }

        let stop: Set<String> = [
            "find", "show", "me", "the", "a", "an", "i", "copied", "about", "that", "this",
            "where", "is", "my", "from", "last", "week", "yesterday", "today", "month", "please",
            "with", "for", "and", "what", "was", "did", "have", "get", "give", "clip", "clipboard",
            "thing", "something", "past", "recent", "recently"
        ]
        let keywords = query
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
            .filter { $0.count > 2 && !stop.contains($0) }

        return AIQueryInterpretation(
            keywords: keywords,
            category: category,
            sourceAppHint: sourceApp,
            relativeTime: relative,
            intent: query
        )
    }
}
