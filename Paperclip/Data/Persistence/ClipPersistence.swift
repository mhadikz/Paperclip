import Foundation

/// History + pinboard JSON files (coalesced background writes).
final class ClipPersistence: @unchecked Sendable {
    private let history: JSONFileStore<[ClipItem]>
    private let pinboards: JSONFileStore<[Pinboard]>

    init(rootURL: URL = AppDataLocation.rootURL) {
        history = JSONFileStore(url: rootURL.appendingPathComponent("history.json"), label: "history")
        pinboards = JSONFileStore(url: rootURL.appendingPathComponent("pinboards.json"), label: "pinboards")
    }

    func loadClips() -> [ClipItem] { history.load() ?? [] }
    func saveClips(_ clips: [ClipItem]) { history.scheduleSave(clips) }
    func flushClips() { history.flush() }

    func loadPinboards() -> [Pinboard] { pinboards.load() ?? [] }
    func savePinboards(_ boards: [Pinboard]) { pinboards.scheduleSave(boards) }
    func flushPinboards() { pinboards.flush() }
}
