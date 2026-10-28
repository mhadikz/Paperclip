import Foundation

struct ClipItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var contentType: ClipContentType
    var text: String?
    var title: String?
    var createdAt: Date
    var sourceBundleID: String?
    var sourceAppName: String?
    /// Relative filename under Application Support/Paperclip/Media (PNG for images).
    var mediaFileName: String?
    /// Relative filename of the RTF sidecar that preserves formatting for text clips.
    var richTextFileName: String?
    var filePaths: [String]
    /// OCR / extracted searchable text for images.
    var searchableText: String?
    /// SHA-256 of the stored payload (images) so identical copies collapse into one clip.
    var contentHash: String?
    /// Size of the stored media file in bytes (images), used for storage statistics.
    var mediaByteCount: Int?

    init(
        id: UUID = UUID(),
        contentType: ClipContentType,
        text: String? = nil,
        title: String? = nil,
        createdAt: Date = Date(),
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        mediaFileName: String? = nil,
        richTextFileName: String? = nil,
        filePaths: [String] = [],
        searchableText: String? = nil,
        contentHash: String? = nil,
        mediaByteCount: Int? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.text = text
        self.title = title
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.mediaFileName = mediaFileName
        self.richTextFileName = richTextFileName
        self.filePaths = filePaths
        self.searchableText = searchableText
        self.contentHash = contentHash
        self.mediaByteCount = mediaByteCount
    }

    /// Backward-compatible decoding: v1 history (text-only clips) and v1.2 (no rich text / hash).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        mediaFileName = try container.decodeIfPresent(String.self, forKey: .mediaFileName)
        richTextFileName = try container.decodeIfPresent(String.self, forKey: .richTextFileName)
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        searchableText = try container.decodeIfPresent(String.self, forKey: .searchableText)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        mediaByteCount = try container.decodeIfPresent(Int.self, forKey: .mediaByteCount)
        title = try container.decodeIfPresent(String.self, forKey: .title)

        if let type = try container.decodeIfPresent(ClipContentType.self, forKey: .contentType) {
            contentType = type
            text = try container.decodeIfPresent(String.self, forKey: .text)
        } else if let legacyText = try container.decodeIfPresent(String.self, forKey: .text) {
            text = legacyText
            contentType = Self.inferType(from: legacyText)
        } else {
            text = nil
            contentType = .text
        }
    }

    // MARK: - Derived

    /// One-line preview for menus and compact rows.
    var preview: String {
        if let title, !title.isEmpty { return title }
        switch contentType {
        case .text, .link:
            return Self.collapse(text ?? "")
        case .image:
            if let searchableText, !searchableText.isEmpty {
                return Self.collapse(searchableText)
            }
            return "Image"
        case .file:
            if filePaths.count > 1 {
                return "\(filePaths.count) files"
            }
            if let first = filePaths.first {
                return URL(fileURLWithPath: first).lastPathComponent
            }
            return "File"
        }
    }

    /// Bounded excerpt for History cards. Laying out a 100 KB string just to show four lines
    /// is the single biggest scroll-performance cost, so cards never receive the full body.
    var cardExcerpt: String {
        Self.excerpt(text ?? "", maxLines: 8, maxCharacters: 480)
    }

    var lineCount: Int {
        guard let text, !text.isEmpty else { return 0 }
        return text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
    }

    var characterCount: Int { text?.count ?? 0 }

    /// Approximate bytes this clip occupies on disk (text + media sidecars).
    var estimatedByteCount: Int {
        (text?.utf8.count ?? 0) + (searchableText?.utf8.count ?? 0) + (mediaByteCount ?? 0)
    }

    var url: URL? {
        guard contentType == .link, let text else { return nil }
        return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var searchBlob: String {
        [
            title,
            text,
            searchableText,
            sourceAppName,
            sourceBundleID,
            filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    /// Identity used to collapse repeated copies into one clip (which is then bumped to the top).
    var duplicateKey: String {
        switch contentType {
        case .text, .link:
            return "text:" + (text ?? "")
        case .image:
            return "image:" + (contentHash ?? mediaFileName ?? id.uuidString)
        case .file:
            return "file:" + filePaths.joined(separator: "|")
        }
    }

    static func inferType(from text: String) -> ClipContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return .text }
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return .link
        }
        return .text
    }

    static func excerpt(_ value: String, maxLines: Int, maxCharacters: Int) -> String {
        guard !value.isEmpty else { return value }
        var lines: [Substring] = []
        var truncated = false
        for line in value.split(separator: "\n", maxSplits: maxLines, omittingEmptySubsequences: false) {
            if lines.count == maxLines { truncated = true; break }
            lines.append(line)
        }
        var joined = lines.joined(separator: "\n")
        if joined.count > maxCharacters {
            joined = String(joined.prefix(maxCharacters))
            truncated = true
        }
        return truncated ? joined + "…" : joined
    }

    private static func collapse(_ value: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in value {
            let isSpace = ch.isWhitespace || ch.isNewline
            if isSpace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
            if out.count > 90 { break }
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(77)) + "…"
    }
}
