import Foundation

/// Serial background AI enrichment. Never blocks clipboard capture.
///
/// IDs stay queued until a handler is installed, so work enqueued during startup is not lost.
actor AIProcessingQueue: AIProcessingQueuing {
    typealias Handler = @MainActor (UUID) async -> Void

    private var handler: Handler?
    private var pending: [UUID] = []
    private var queued = Set<UUID>()
    private var running = false
    private let pauseBetweenItems: UInt64 = 60_000_000

    init() {}

    func setHandler(_ handler: @escaping Handler) {
        self.handler = handler
        Task { await processLoop() }
    }

    func enqueue(_ clipID: UUID) {
        if queued.insert(clipID).inserted {
            pending.append(clipID)
        }
        Task { await processLoop() }
    }

    func enqueueMany(_ clipIDs: [UUID]) {
        for id in clipIDs where queued.insert(id).inserted {
            pending.append(id)
        }
        Task { await processLoop() }
    }

    func pendingCount() -> Int {
        pending.count
    }

    private func processLoop() async {
        guard !running, handler != nil else { return }
        running = true
        defer { running = false }

        while let next = pending.first, let handler {
            pending.removeFirst()
            queued.remove(next)
            await handler(next)
            try? await Task.sleep(nanoseconds: pauseBetweenItems)
        }
    }
}
