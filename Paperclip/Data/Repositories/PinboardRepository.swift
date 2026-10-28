import Foundation
import Combine

@MainActor
final class PinboardRepository: PinboardRepositoryProtocol, ObservableObject {
    @Published private(set) var pinboards: [Pinboard] = []

    var pinboardsPublisher: AnyPublisher<[Pinboard], Never> {
        $pinboards.eraseToAnyPublisher()
    }

    private let persistence: ClipPersistence

    init(persistence: ClipPersistence) {
        self.persistence = persistence
        self.pinboards = persistence.loadPinboards()
    }

    func create(name: String, colorHex: String) -> Pinboard {
        let board = Pinboard(name: name, colorHex: colorHex)
        pinboards.append(board)
        persist()
        return board
    }

    func rename(id: UUID, name: String) {
        update(id) { $0.name = name }
    }

    func setColor(id: UUID, colorHex: String) {
        update(id) { $0.colorHex = colorHex }
    }

    func delete(id: UUID) {
        pinboards.removeAll { $0.id == id }
        persist()
    }

    func pin(clipID: UUID, to boardID: UUID) {
        update(boardID) { board in
            if !board.clipIDs.contains(clipID) {
                board.clipIDs.insert(clipID, at: 0)
            }
        }
    }

    func unpin(clipID: UUID, from boardID: UUID) {
        update(boardID) { $0.clipIDs.removeAll { $0 == clipID } }
    }

    func unpinEverywhere(clipIDs: Set<UUID>) {
        guard !clipIDs.isEmpty else { return }
        var changed = false
        var boards = pinboards
        for index in boards.indices {
            let before = boards[index].clipIDs.count
            boards[index].clipIDs.removeAll { clipIDs.contains($0) }
            if boards[index].clipIDs.count != before { changed = true }
        }
        guard changed else { return }
        pinboards = boards
        persist()
    }

    func isPinned(_ clipID: UUID) -> Bool {
        pinboards.contains { $0.clipIDs.contains(clipID) }
    }

    func allPinnedIDs() -> Set<UUID> {
        Set(pinboards.flatMap(\.clipIDs))
    }

    func flush() {
        persistence.flushPinboards()
    }

    private func persist() {
        persistence.savePinboards(pinboards)
    }

    private func update(_ id: UUID, _ body: (inout Pinboard) -> Void) {
        guard let index = pinboards.firstIndex(where: { $0.id == id }) else { return }
        var boards = pinboards
        body(&boards[index])
        pinboards = boards
        persist()
    }
}
