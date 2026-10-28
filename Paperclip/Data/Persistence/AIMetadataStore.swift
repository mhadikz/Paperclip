import Foundation

/// AI sidecar file. Stored as an array (stable, diff-friendly) and loaded into a dictionary.
final class AIMetadataStore: @unchecked Sendable {
    private let store: JSONFileStore<[AIMemoryMetadata]>

    init(url: URL = AppDataLocation.aiMetadataURL) {
        store = JSONFileStore(url: url, label: "ai-metadata")
    }

    func load() -> [UUID: AIMemoryMetadata] {
        guard let array = store.load() else { return [:] }
        return Dictionary(array.map { ($0.clipID, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func save(_ map: [UUID: AIMemoryMetadata]) {
        store.scheduleSave(map.values.sorted { $0.clipID.uuidString < $1.clipID.uuidString })
    }

    func flush() { store.flush() }
}
