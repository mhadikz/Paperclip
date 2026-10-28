import Foundation

/// What to do when captured text looks like a secret (password, token, key, card number).
enum SensitiveStoragePolicy: String, Codable, CaseIterable, Identifiable {
    case neverStore
    case storeWithoutAI
    case storeEncryptedPlaceholder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neverStore: return "Never store"
        case .storeWithoutAI: return "Store without AI processing"
        case .storeEncryptedPlaceholder: return "Store redacted placeholder"
        }
    }

    var detail: String {
        switch self {
        case .neverStore: return "Likely secrets are left on the system clipboard but never written to history."
        case .storeWithoutAI: return "Secrets are kept in history but never sent to the on-device model."
        case .storeEncryptedPlaceholder: return "Only a short “[redacted]” marker is stored, never the secret itself."
        }
    }
}
