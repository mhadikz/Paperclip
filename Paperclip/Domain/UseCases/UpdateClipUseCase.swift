import Foundation

/// Small edits to a stored clip that never touch its body.
@MainActor
struct UpdateClipUseCase {
    let clipboard: ClipboardRepositoryProtocol

    func rename(_ clip: ClipItem, title: String) {
        var updated = clip
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? nil : trimmed
        clipboard.update(updated)
    }
}
