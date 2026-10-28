import Foundation

/// Fine-grained memory categories beyond the coarse ClipContentType.
enum MemoryCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case plainText
    case url
    case email
    case code
    case sql
    case json
    case xml
    case markdown
    case command
    case shell
    case configuration
    case address
    case phoneNumber
    case financial
    case credentials
    case documentation
    case meetingNotes
    case article
    case shopping
    case travel
    case image
    case file
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: return "Plain Text"
        case .url: return "URL"
        case .email: return "Email"
        case .code: return "Code"
        case .sql: return "SQL"
        case .json: return "JSON"
        case .xml: return "XML"
        case .markdown: return "Markdown"
        case .command: return "Command"
        case .shell: return "Shell"
        case .configuration: return "Configuration"
        case .address: return "Address"
        case .phoneNumber: return "Phone"
        case .financial: return "Financial"
        case .credentials: return "Credentials"
        case .documentation: return "Documentation"
        case .meetingNotes: return "Meeting Notes"
        case .article: return "Article"
        case .shopping: return "Shopping"
        case .travel: return "Travel"
        case .image: return "Image"
        case .file: return "File"
        case .other: return "Other"
        }
    }

    /// Categories that should render as a code card in History.
    var isCodeLike: Bool {
        switch self {
        case .code, .sql, .json, .xml, .command, .shell, .configuration:
            return true
        default:
            return false
        }
    }

    var systemImage: String {
        switch self {
        case .plainText: return "doc.plaintext"
        case .url: return "link"
        case .email: return "envelope"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .sql: return "cylinder.split.1x2"
        case .json, .xml: return "curlybraces"
        case .markdown: return "text.alignleft"
        case .command, .shell: return "terminal"
        case .configuration: return "gearshape.2"
        case .address: return "mappin.and.ellipse"
        case .phoneNumber: return "phone"
        case .financial: return "creditcard"
        case .credentials: return "key"
        case .documentation: return "book"
        case .meetingNotes: return "person.3"
        case .article: return "newspaper"
        case .shopping: return "cart"
        case .travel: return "airplane"
        case .image: return "photo"
        case .file: return "doc"
        case .other: return "questionmark.circle"
        }
    }
}
