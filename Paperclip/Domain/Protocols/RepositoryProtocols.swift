import Foundation
import Combine

// MARK: - Clipboard history

/// Outcome of inserting captured content.
enum ClipInsertResult: Equatable {
    /// A brand-new clip was stored.
    case inserted(ClipItem)
    /// The same content already existed; that clip kept its identity and moved to the top.
    case bumped(ClipItem)

    var clip: ClipItem {
        switch self {
        case .inserted(let clip), .bumped(let clip): return clip
        }
    }
}

@MainActor
protocol ClipboardRepositoryProtocol: AnyObject {
    var clips: [ClipItem] { get }
    var clipsPublisher: AnyPublisher<[ClipItem], Never> { get }

    func clip(id: UUID) -> ClipItem?
    /// Inserts at the top, or bumps the existing duplicate (same `duplicateKey`) to the top.
    @discardableResult
    func insert(_ item: ClipItem) -> ClipInsertResult
    func update(_ item: ClipItem)
    func delete(ids: Set<UUID>)
    func deleteAll(keeping keepForever: Set<UUID>)
    func bumpToTop(id: UUID)
    /// Drops the oldest unprotected clips beyond `limit`. Returns the removed clips.
    @discardableResult
    func trim(limit: Int, keepForever: Set<UUID>) -> [ClipItem]
    /// Writes any pending changes synchronously (called on quit).
    func flush()
}

// MARK: - Pinboards

@MainActor
protocol PinboardRepositoryProtocol: AnyObject {
    var pinboards: [Pinboard] { get }
    var pinboardsPublisher: AnyPublisher<[Pinboard], Never> { get }

    func create(name: String, colorHex: String) -> Pinboard
    func rename(id: UUID, name: String)
    func setColor(id: UUID, colorHex: String)
    func delete(id: UUID)
    func pin(clipID: UUID, to boardID: UUID)
    func unpin(clipID: UUID, from boardID: UUID)
    func unpinEverywhere(clipIDs: Set<UUID>)
    func isPinned(_ clipID: UUID) -> Bool
    func allPinnedIDs() -> Set<UUID>
    func flush()
}

// MARK: - AI metadata

@MainActor
protocol AIMemoryRepositoryProtocol: AnyObject {
    var metadata: [UUID: AIMemoryMetadata] { get }
    var metadataPublisher: AnyPublisher<[UUID: AIMemoryMetadata], Never> { get }

    func metadata(for clipID: UUID) -> AIMemoryMetadata?
    func upsert(_ meta: AIMemoryMetadata)
    func remove(ids: Set<UUID>)
    func clearAll()
    func prune(keeping clipIDs: Set<UUID>)
    func favoriteIDs() -> Set<UUID>
    func flush()
}

// MARK: - Paste stack

@MainActor
protocol PasteStackStoreProtocol: AnyObject {
    var stack: [UUID] { get }
    var stackPublisher: AnyPublisher<[UUID], Never> { get }

    func push(_ id: UUID)
    func remove(_ id: UUID)
    func popNext() -> UUID?
    func clear()
}
