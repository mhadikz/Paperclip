import Foundation

enum ClipContentType: String, Codable, CaseIterable, Identifiable {
    case text
    case link
    case image
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Links"
        case .image: return "Images"
        case .file: return "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "doc.plaintext"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}
