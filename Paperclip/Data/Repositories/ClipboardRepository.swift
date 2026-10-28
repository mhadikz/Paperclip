import Foundation
import Combine

@MainActor
final class ClipboardRepository: ClipboardRepositoryProtocol, ObservableObject {
    @Published private(set) var clips: [ClipItem] = []

    var clipsPublisher: AnyPublisher<[ClipItem], Never> {
        $clips.eraseToAnyPublisher()
    }

    private let persistence: ClipPersistence
    private let mediaStore: MediaStoring
    private let appearance: () -> AppearanceMode
    private let publishSnapshot: ([ClipItem], AppearanceMode) -> Void

    /// - Parameter publishSnapshot: receives the clips after every change so the widget stays current.
    ///   Tests and previews pass a no-op so they never write into the real Application Support folder.
    init(
        persistence: ClipPersistence,
        mediaStore: MediaStoring,
        appearance: @escaping () -> AppearanceMode = { .system },
        publishSnapshot: @escaping ([ClipItem], AppearanceMode) -> Void = { WidgetSnapshotWriter.write(clips: $0, appearance: $1) }
    ) {
        self.persistence = persistence
        self.mediaStore = mediaStore
        self.appearance = appearance
        self.publishSnapshot = publishSnapshot
        self.clips = persistence.loadClips()
    }

    func clip(id: UUID) -> ClipItem? {
        clips.first { $0.id == id }
    }

    @discardableResult
    func insert(_ item: ClipItem) -> ClipInsertResult {
        let key = item.duplicateKey
        if let index = clips.firstIndex(where: { $0.duplicateKey == key }) {
            var existing = clips.remove(at: index)
            existing.createdAt = item.createdAt
            clips.insert(existing, at: 0)
            persist()
            return .bumped(existing)
        }
        clips.insert(item, at: 0)
        persist()
        return .inserted(item)
    }

    func update(_ item: ClipItem) {
        guard let index = clips.firstIndex(where: { $0.id == item.id }) else { return }
        clips[index] = item
        persist()
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for clip in clips where ids.contains(clip.id) {
            removeMedia(for: clip)
        }
        clips.removeAll { ids.contains($0.id) }
        persist()
    }

    func deleteAll(keeping keepForever: Set<UUID>) {
        let removable = clips.filter { !keepForever.contains($0.id) }
        guard !removable.isEmpty else { return }
        for clip in removable {
            removeMedia(for: clip)
        }
        let removableIDs = Set(removable.map(\.id))
        clips.removeAll { removableIDs.contains($0.id) }
        persist()
    }

    func bumpToTop(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }), index != 0 else { return }
        let value = clips.remove(at: index)
        clips.insert(value, at: 0)
        persist()
    }

    @discardableResult
    func trim(limit: Int, keepForever: Set<UUID>) -> [ClipItem] {
        var kept: [ClipItem] = []
        var removed: [ClipItem] = []
        var unpinnedCount = 0
        for clip in clips {
            if keepForever.contains(clip.id) {
                kept.append(clip)
            } else if unpinnedCount < limit {
                kept.append(clip)
                unpinnedCount += 1
            } else {
                removed.append(clip)
            }
        }
        guard !removed.isEmpty else { return [] }
        for clip in removed {
            removeMedia(for: clip)
        }
        clips = kept
        persist()
        return removed
    }

    func flush() {
        persistence.flushClips()
    }

    private func removeMedia(for clip: ClipItem) {
        mediaStore.delete(fileName: clip.mediaFileName)
        mediaStore.delete(fileName: clip.richTextFileName)
    }

    private func persist() {
        persistence.saveClips(clips)
        publishSnapshot(clips, appearance())
    }
}
