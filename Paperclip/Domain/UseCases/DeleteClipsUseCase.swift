import Foundation

/// Deleting a clip cascades to media files, AI metadata, paste stack and pinboards.
@MainActor
struct DeleteClipsUseCase {
    let clipboard: ClipboardRepositoryProtocol
    let pinboards: PinboardRepositoryProtocol
    let aiMemory: AIMemoryRepositoryProtocol
    let stack: PasteStackStoreProtocol

    func execute(_ items: [ClipItem]) {
        execute(ids: Set(items.map(\.id)))
    }

    func execute(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        clipboard.delete(ids: ids)
        aiMemory.remove(ids: ids)
        pinboards.unpinEverywhere(clipIDs: ids)
        for id in ids {
            stack.remove(id)
        }
    }

    /// Clears history but keeps anything pinned to a pinboard.
    func executeDeleteAllHistory() {
        let keep = pinboards.allPinnedIDs()
        let removableIDs = Set(clipboard.clips.filter { !keep.contains($0.id) }.map(\.id))
        clipboard.deleteAll(keeping: keep)
        aiMemory.remove(ids: removableIDs)
        for id in removableIDs {
            stack.remove(id)
        }
    }
}
