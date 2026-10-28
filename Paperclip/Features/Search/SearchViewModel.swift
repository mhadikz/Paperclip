import Foundation
import Combine

/// Memory search in two phases: instant heuristic results on every keystroke, then an
/// optional model-refined pass that only replaces the list if the query is unchanged.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var results: [MemorySearchResult] = []
    @Published private(set) var isRefining = false

    let appState: AppState

    private let clipboard: ClipboardRepositoryProtocol
    private let pinboards: PinboardRepositoryProtocol
    private let aiMemory: AIMemoryRepositoryProtocol
    private let searchMemory: SearchMemoryUseCase
    private var cancellables = Set<AnyCancellable>()
    private var refineTask: Task<Void, Never>?

    private static let refineDelay: UInt64 = 450_000_000

    init(
        appState: AppState,
        clipboard: ClipboardRepositoryProtocol,
        pinboards: PinboardRepositoryProtocol,
        aiMemory: AIMemoryRepositoryProtocol,
        searchMemory: SearchMemoryUseCase
    ) {
        self.appState = appState
        self.clipboard = clipboard
        self.pinboards = pinboards
        self.aiMemory = aiMemory
        self.searchMemory = searchMemory

        appState.$searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        appState.$navigationMode
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        clipboard.clipsPublisher
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.appState.navigationMode != .clipboard else { return }
                self.refresh()
            }
            .store(in: &cancellables)

        aiMemory.metadataPublisher
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.appState.navigationMode != .clipboard else { return }
                self.refresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        refineTask?.cancel()
        isRefining = false

        let mode = appState.navigationMode
        guard mode != .clipboard else {
            results = []
            return
        }

        let input = SearchMemoryUseCase.Input(
            query: appState.searchText,
            mode: mode,
            clips: clipboard.clips,
            metadata: aiMemory.metadata,
            pinnedIDs: pinboards.allPinnedIDs()
        )
        results = searchMemory.quickSearch(input)

        guard searchMemory.shouldRefineWithAI(query: input.query) else { return }
        isRefining = true
        let query = input.query
        refineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.refineDelay)
            guard !Task.isCancelled, let self else { return }
            let refined = await self.searchMemory.refinedSearch(input)
            guard !Task.isCancelled, self.appState.searchText == query else { return }
            self.results = refined
            self.isRefining = false
        }
    }
}
