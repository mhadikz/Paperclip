import Foundation
import Combine

@MainActor
final class PasteStackStore: PasteStackStoreProtocol, ObservableObject {
    @Published private(set) var stack: [UUID] = []

    var stackPublisher: AnyPublisher<[UUID], Never> {
        $stack.eraseToAnyPublisher()
    }

    func push(_ id: UUID) {
        if !stack.contains(id) {
            stack.append(id)
        }
    }

    func remove(_ id: UUID) {
        stack.removeAll { $0 == id }
    }

    func popNext() -> UUID? {
        guard !stack.isEmpty else { return nil }
        return stack.removeFirst()
    }

    func clear() {
        stack.removeAll()
    }
}
