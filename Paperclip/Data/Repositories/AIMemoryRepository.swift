import Foundation
import Combine

@MainActor
final class AIMemoryRepository: AIMemoryRepositoryProtocol, ObservableObject {
    @Published private(set) var metadata: [UUID: AIMemoryMetadata] = [:]

    var metadataPublisher: AnyPublisher<[UUID: AIMemoryMetadata], Never> {
        $metadata.eraseToAnyPublisher()
    }

    private let store: AIMetadataStore

    init(store: AIMetadataStore) {
        self.store = store
        self.metadata = store.load()
    }

    func metadata(for clipID: UUID) -> AIMemoryMetadata? {
        metadata[clipID]
    }

    func upsert(_ meta: AIMemoryMetadata) {
        metadata[meta.clipID] = meta
        persist()
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var changed = false
        for id in ids where metadata.removeValue(forKey: id) != nil {
            changed = true
        }
        if changed { persist() }
    }

    func clearAll() {
        guard !metadata.isEmpty else { return }
        metadata.removeAll()
        persist()
    }

    func prune(keeping clipIDs: Set<UUID>) {
        let before = metadata.count
        metadata = metadata.filter { clipIDs.contains($0.key) }
        if metadata.count != before {
            persist()
        }
    }

    func favoriteIDs() -> Set<UUID> {
        Set(metadata.lazy.filter { $0.value.isFavorite }.map(\.key))
    }

    func flush() {
        store.flush()
    }

    private func persist() {
        store.save(metadata)
    }
}
