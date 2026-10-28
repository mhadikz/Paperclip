import Foundation

enum HistoryNavigationMode: String, CaseIterable, Identifiable {
    case clipboard
    case aiMemory
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .aiMemory: return "AI Memory"
        case .favorites: return "Favorites"
        }
    }

    var windowTitle: String {
        switch self {
        case .clipboard: return "Clipboard History"
        case .aiMemory: return "AI Memory"
        case .favorites: return "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .clipboard: return "paperclip"
        case .aiMemory: return "brain.head.profile"
        case .favorites: return "star"
        }
    }
}
