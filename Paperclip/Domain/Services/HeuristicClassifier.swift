import Foundation

/// Fast, deterministic classification that runs before (and without) any language model.
enum HeuristicClassifier {
    static func classify(clip: ClipItem) -> AIClassificationResult {
        switch clip.contentType {
        case .image:
            return AIClassificationResult(
                category: .image,
                tags: ["Image"],
                summary: clip.searchableText.map { String($0.prefix(120)) },
                language: nil,
                codeLanguage: nil,
                entities: [],
                importance: 0.45
            )
        case .file:
            let name = clip.filePaths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "File"
            return AIClassificationResult(
                category: .file,
                tags: ["File", fileExtensionTag(name)].compactMap { $0 },
                summary: clip.filePaths.count > 1 ? "\(clip.filePaths.count) files" : name,
                language: nil,
                codeLanguage: nil,
                entities: [name],
                importance: 0.4
            )
        case .link:
            return classifyURL(clip.text ?? "")
        case .text:
            return classifyText(clip.text ?? "")
        }
    }

    static func classifyText(_ raw: String) -> AIClassificationResult {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return result(.other, [], summary: nil, importance: 0.2)
        }

        if SensitiveContentFilter.looksSensitive(text) {
            return AIClassificationResult(
                category: .credentials,
                tags: ["Sensitive"],
                summary: "Sensitive content (not summarized)",
                language: nil,
                codeLanguage: nil,
                entities: [],
                importance: 0.9
            )
        }

        if ClipItem.inferType(from: text) == .link {
            return classifyURL(text)
        }
        if looksLikeEmail(text) {
            return result(.email, ["Email", "Communication"], summary: firstLine(text), importance: 0.7)
        }
        if looksLikeSQL(text) {
            return result(.sql, ["SQL", "Database", "Backend"], summary: firstLine(text), codeLanguage: "sql", importance: 0.75)
        }
        if looksLikeJSON(text) {
            return result(.json, ["JSON", "Data"], summary: "JSON payload", codeLanguage: "json", importance: 0.65)
        }
        if looksLikeXML(text) {
            return result(.xml, ["XML", "Markup"], summary: "XML document", codeLanguage: "xml", importance: 0.55)
        }
        if looksLikeShell(text) {
            return result(.shell, shellTags(text), summary: firstLine(text), codeLanguage: "shell", importance: 0.7)
        }
        if looksLikeCode(text) {
            let lang = detectCodeLanguage(text)
            var tags = ["Code"]
            if let lang { tags.append(lang.capitalized) }
            return result(.code, tags, summary: firstLine(text), codeLanguage: lang, importance: 0.7)
        }
        if looksLikeMarkdown(text) {
            return result(.markdown, ["Markdown", "Notes"], summary: firstLine(text), importance: 0.55)
        }
        if looksLikeConfig(text) {
            return result(.configuration, ["Config"], summary: firstLine(text), importance: 0.6)
        }
        if looksLikePhone(text) {
            return result(.phoneNumber, ["Phone"], summary: text, importance: 0.5)
        }

        let tags = topicTags(from: text)
        let category: MemoryCategory = text.count > 400 ? .article : .plainText
        return result(category, tags, summary: text.count > 160 ? String(text.prefix(140)) + "…" : nil, importance: 0.45)
    }

    private static func classifyURL(_ text: String) -> AIClassificationResult {
        let lower = text.lowercased()
        var tags = ["URL", "Link"]
        let hosts: [(String, String)] = [
            ("github.com", "GitHub"), ("gitlab.com", "GitLab"), ("stackoverflow.com", "StackOverflow"),
            ("npmjs.com", "npm"), ("docker", "Docker"), ("azure", "Azure"), ("aws.amazon.com", "AWS"),
            ("developer.apple.com", "Apple Developer"), ("youtube.com", "YouTube"), ("youtu.be", "YouTube"),
            ("figma.com", "Figma"), ("notion.so", "Notion"), ("atlassian.net", "Jira"), ("linkedin.com", "LinkedIn")
        ]
        for (needle, tag) in hosts where lower.contains(needle) {
            tags.append(tag)
        }
        let host = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host
        return AIClassificationResult(
            category: .url,
            tags: AIMemoryMetadata.normalizeTags(tags),
            summary: text,
            language: nil,
            codeLanguage: nil,
            entities: host.map { [$0] } ?? [],
            importance: 0.6
        )
    }

    private static func result(
        _ category: MemoryCategory,
        _ tags: [String],
        summary: String?,
        language: String? = nil,
        codeLanguage: String? = nil,
        importance: Double
    ) -> AIClassificationResult {
        AIClassificationResult(
            category: category,
            tags: AIMemoryMetadata.normalizeTags(tags),
            summary: summary,
            language: language,
            codeLanguage: codeLanguage,
            entities: [],
            importance: importance
        )
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.prefix(160))
    }

    // MARK: - Detectors

    private static func looksLikeEmail(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("from:") && lower.contains("subject:") { return true }
        guard text.count < 320, !text.contains(where: \.isWhitespace), text.contains("@") else { return false }
        // user@host.tld — not git@host:path
        let parts = text.split(separator: "@")
        guard parts.count == 2, let domain = parts.last, domain.contains("."), !domain.contains(":") else { return false }
        return !text.contains("/")
    }

    private static func looksLikeSQL(_ text: String) -> Bool {
        let upper = text.uppercased()
        let starts = ["SELECT ", "INSERT INTO", "UPDATE ", "DELETE FROM", "CREATE TABLE", "ALTER TABLE", "WITH ", "DROP TABLE"]
        guard starts.contains(where: { upper.contains($0) }) else { return false }
        return upper.contains(" FROM ") || upper.contains(" INTO ") || upper.contains(" SET ") || upper.contains(" TABLE ") || upper.contains("SELECT ")
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (t.hasPrefix("{") && t.hasSuffix("}")) || (t.hasPrefix("[") && t.hasSuffix("]")) else { return false }
        return t.contains(":") || t.contains("\"")
    }

    private static func looksLikeXML(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("<?xml") || (t.hasPrefix("<") && t.contains("</") && t.hasSuffix(">"))
    }

    private static let shellStarters = [
        "docker ", "kubectl ", "git ", "npm ", "npx ", "yarn ", "pnpm ", "brew ", "ssh ", "curl ", "wget ",
        "cd ", "export ", "sudo ", "ls ", "rm ", "cp ", "mv ", "cat ", "grep ", "find ", "chmod ", "make ",
        "swift ", "python ", "python3 ", "pip ", "cargo ", "go ", "az ", "aws ", "gcloud ", "terraform ", "xcodebuild "
    ]

    private static func looksLikeShell(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#!") { return true }
        let lower = t.lowercased()
        return shellStarters.contains { lower.hasPrefix($0) } || lower.contains(" && ") || lower.hasPrefix("$ ") || lower.contains(" | grep ")
    }

    private static func shellTags(_ text: String) -> [String] {
        let lower = text.lowercased()
        var tags = ["Shell", "Command"]
        if lower.contains("docker") { tags.append("Docker") }
        if lower.contains("kubectl") || lower.contains("kubernetes") { tags.append("Kubernetes") }
        if lower.hasPrefix("git ") || lower.contains(" git ") { tags.append("Git") }
        if lower.contains("azure") || lower.hasPrefix("az ") { tags.append("Azure") }
        if lower.contains("aws ") { tags.append("AWS") }
        if lower.contains("brew ") { tags.append("Homebrew") }
        if lower.contains("npm ") || lower.contains("yarn ") || lower.contains("pnpm ") { tags.append("Node") }
        return tags
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let signals = ["func ", "import ", "package ", "public class", "def ", "const ", "let ", "var ", "=>", "{", "};", "#include", "return ", "class ", "struct "]
        let hits = signals.filter { text.contains($0) }.count
        return hits >= 2 || (text.contains("func ") && text.contains("{"))
    }

    private static func detectCodeLanguage(_ text: String) -> String? {
        if text.contains("func ") && (text.contains("import Foundation") || text.contains("import SwiftUI") || text.contains("let ")) { return "swift" }
        if text.contains("package ") && text.contains("func ") { return "go" }
        if text.contains("def ") && (text.contains("self") || text.contains("import ") || text.contains(":\n")) { return "python" }
        if text.contains("interface ") || text.contains(": string") || text.contains(": number") { return "typescript" }
        if text.contains("const ") || text.contains("=>") || text.contains("function ") { return "javascript" }
        if text.contains("public class") || text.contains("System.out") { return "java" }
        if text.contains("#include") { return "c" }
        if text.contains("fn ") && text.contains("let mut") { return "rust" }
        return nil
    }

    private static func looksLikeMarkdown(_ text: String) -> Bool {
        text.contains("\n## ") || text.hasPrefix("# ") || text.contains("```") || text.contains("- [ ]") || text.contains("\n- ") && text.contains("**")
    }

    private static func looksLikeConfig(_ text: String) -> Bool {
        let lower = text.lowercased()
        let lines = text.split(separator: "\n")
        let assignments = lines.filter { $0.contains("=") || $0.contains(": ") }.count
        return lower.contains("[server]") || lower.hasPrefix("---\n")
            || (lines.count >= 3 && assignments * 2 >= lines.count && !text.contains("{"))
    }

    private static func looksLikePhone(_ text: String) -> Bool {
        guard text.count <= 24, !text.contains("/"), !text.contains(":") else { return false }
        let digits = text.filter(\.isNumber).count
        let allowed = text.allSatisfy { $0.isNumber || $0 == "+" || $0 == "-" || $0 == " " || $0 == "(" || $0 == ")" || $0 == "." }
        return allowed && digits >= 10 && digits <= 15
    }

    private static func topicTags(from text: String) -> [String] {
        let lower = text.lowercased()
        var tags: [String] = ["Text"]
        let dictionary: [(String, String)] = [
            ("docker", "Docker"), ("kubernetes", "Kubernetes"), ("azure", "Azure"),
            ("aws", "AWS"), ("swift", "Swift"), ("macos", "macOS"), ("invoice", "Invoice"),
            ("auth", "Authentication"), ("payment", "Payments"), ("api", "API"), ("meeting", "Meeting"),
            ("deadline", "Deadline"), ("recipe", "Recipe"), ("address", "Address")
        ]
        for (needle, tag) in dictionary where lower.contains(needle) {
            tags.append(tag)
        }
        return AIMemoryMetadata.normalizeTags(tags)
    }

    private static func fileExtensionTag(_ name: String) -> String? {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return ext.uppercased()
    }
}
