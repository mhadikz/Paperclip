import Foundation

@MainActor
struct ManagePinboardUseCase {
    let pinboards: PinboardRepositoryProtocol

    func create(name: String, colorHex: String = Pinboard.defaultColorHex) -> Pinboard {
        pinboards.create(name: name, colorHex: colorHex)
    }

    func rename(_ board: Pinboard, name: String) {
        pinboards.rename(id: board.id, name: name)
    }

    func setColor(_ board: Pinboard, colorHex: String) {
        pinboards.setColor(id: board.id, colorHex: colorHex)
    }

    func delete(_ board: Pinboard) {
        pinboards.delete(id: board.id)
    }

    func pin(_ clip: ClipItem, to board: Pinboard) {
        pinboards.pin(clipID: clip.id, to: board.id)
    }

    func unpin(_ clip: ClipItem, from board: Pinboard) {
        pinboards.unpin(clipID: clip.id, from: board.id)
    }
}
