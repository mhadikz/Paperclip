import Foundation
import Combine

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published private(set) var clips: [ClipItem] = []
    @Published private(set) var pinboards: [Pinboard] = []
    @Published private(set) var stack: [UUID] = []
    /// What the History list shows: pinboard + type filter + keyword search applied once.
    @Published private(set) var visibleClips: [ClipItem] = []

    let appState: AppState
    let settings: AppSettings

    private let appRouter: AppRouter
    private let clipboard: ClipboardRepositoryProtocol
    private let pinboardRepo: PinboardRepositoryProtocol
    private let aiMemory: AIMemoryRepositoryProtocol
    private let stackStore: PasteStackStoreProtocol
    private let pasteClip: PasteClipUseCase
    private let deleteClips: DeleteClipsUseCase
    private let managePinboards: ManagePinboardUseCase
    private let updateClip: UpdateClipUseCase
    private let updateAIMemory: UpdateAIMemoryUseCase
    private let confirmation: ConfirmationPrompting
    private var cancellables = Set<AnyCancellable>()
    private var didPromptAccessibility = false
    // `@Published` publishers fire on willSet, so the filter uses these mirrors, not AppState.
    private var query = ""
    private var typeFilter: ClipContentType?
    private var boardID: UUID?

    init(
        appState: AppState,
        appRouter: AppRouter,
        clipboard: ClipboardRepositoryProtocol,
        pinboards: PinboardRepositoryProtocol,
        aiMemory: AIMemoryRepositoryProtocol,
        stack: PasteStackStoreProtocol,
        settings: AppSettings,
        pasteClip: PasteClipUseCase,
        deleteClips: DeleteClipsUseCase,
        managePinboards: ManagePinboardUseCase,
        updateClip: UpdateClipUseCase,
        updateAIMemory: UpdateAIMemoryUseCase,
        confirmation: ConfirmationPrompting
    ) {
        self.appState = appState
        self.appRouter = appRouter
        self.clipboard = clipboard
        self.pinboardRepo = pinboards
        self.aiMemory = aiMemory
        self.stackStore = stack
        self.settings = settings
        self.pasteClip = pasteClip
        self.deleteClips = deleteClips
        self.managePinboards = managePinboards
        self.updateClip = updateClip
        self.updateAIMemory = updateAIMemory
        self.confirmation = confirmation

        self.clips = clipboard.clips
        self.pinboards = pinboards.pinboards
        self.stack = stack.stack
        self.query = appState.searchText
        self.typeFilter = appState.filterType
        self.boardID = appState.selectedPinboardID

        clipboard.clipsPublisher
            .sink { [weak self] in self?.clips = $0; self?.recomputeVisible() }
            .store(in: &cancellables)
        pinboards.pinboardsPublisher
            .sink { [weak self] in self?.pinboards = $0; self?.recomputeVisible() }
            .store(in: &cancellables)
        aiMemory.metadataPublisher
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.query.isEmpty else { return }
                self.recomputeVisible()
            }
            .store(in: &cancellables)
        stack.stackPublisher
            .sink { [weak self] in self?.stack = $0 }
            .store(in: &cancellables)
        appState.$searchText.removeDuplicates().dropFirst()
            .sink { [weak self] in self?.query = $0; self?.recomputeVisible() }
            .store(in: &cancellables)
        appState.$filterType.removeDuplicates().dropFirst()
            .sink { [weak self] in self?.typeFilter = $0; self?.recomputeVisible() }
            .store(in: &cancellables)
        appState.$selectedPinboardID.removeDuplicates().dropFirst()
            .sink { [weak self] in self?.boardID = $0; self?.recomputeVisible() }
            .store(in: &cancellables)
        recomputeVisible()
    }

    // MARK: - Derived

    /// Menu bar — never filtered by History search.
    var displayedClips: [ClipItem] {
        Array(clips.prefix(settings.displayCount))
    }

    var activePinboard: Pinboard? {
        guard let id = boardID else { return nil }
        return pinboards.first { $0.id == id }
    }

    var selectedClip: ClipItem? {
        guard let id = appState.selectedClipID else { return nil }
        return clips.first { $0.id == id }
    }

    var previewClip: ClipItem? {
        guard let id = appState.previewClipID else { return nil }
        return clips.first { $0.id == id }
    }

    var stackClips: [ClipItem] {
        let map = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return stack.compactMap { map[$0] }
    }

    var hotKeyDisplay: String { settings.hotKey.displayString }

    var pastesIntoFrontmostApp: Bool { settings.pasteAndEnter && pasteClip.canPasteIntoOtherApps }

    func metadata(for clip: ClipItem) -> AIMemoryMetadata? {
        aiMemory.metadata(for: clip.id)
    }

    func isFavorite(_ clip: ClipItem) -> Bool {
        aiMemory.metadata(for: clip.id)?.isFavorite == true
    }

    func isPinned(_ clip: ClipItem) -> Bool {
        pinboardRepo.isPinned(clip.id)
    }

    func isPinned(_ item: ClipItem, to board: Pinboard) -> Bool {
        (pinboards.first { $0.id == board.id } ?? board).clipIDs.contains(item.id)
    }

    func pinboards(containing clip: ClipItem) -> [Pinboard] {
        pinboards.filter { $0.clipIDs.contains(clip.id) }
    }

    private func recomputeVisible() {
        let source: [ClipItem]
        if let board = activePinboard {
            let map = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            source = board.clipIDs.compactMap { map[$0] }
        } else {
            source = clips
        }
        visibleClips = filter(source)
        let selected = appState.selectedClipID
        if let selected, !visibleClips.contains(where: { $0.id == selected }) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.appState.selectedClipID == selected else { return }
                self.appState.selectedClipID = self.visibleClips.first?.id
            }
        }
    }

    private func filter(_ items: [ClipItem]) -> [ClipItem] {
        var result = items
        if let filterType = typeFilter {
            result = result.filter { $0.contentType == filterType }
        }
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
            result = result.filter { clip in
                let blob = clip.searchBlob + " " + (aiMemory.metadata(for: clip.id)?.memorySearchBlob ?? "")
                return terms.allSatisfy { blob.contains($0) }
            }
        }
        return result
    }

    // MARK: - Selection & navigation

    func selectFirstIfNeeded() {
        if selectedClip == nil || !visibleClips.contains(where: { $0.id == appState.selectedClipID }) {
            appState.selectedClipID = visibleClips.first?.id
        }
    }

    func moveSelection(by offset: Int) {
        guard !visibleClips.isEmpty else { return }
        let currentIndex = visibleClips.firstIndex { $0.id == appState.selectedClipID } ?? -1
        let next = min(max(currentIndex + offset, 0), visibleClips.count - 1)
        appState.selectedClipID = visibleClips[next].id
    }

    func togglePreview(_ clip: ClipItem? = nil) {
        let target = clip ?? selectedClip
        if appState.previewClipID != nil, clip == nil || appState.previewClipID == clip?.id {
            appState.previewClipID = nil
        } else if let target {
            appState.selectedClipID = target.id
            appState.previewClipID = target.id
        }
    }

    func closePreview() {
        appState.previewClipID = nil
    }

    // MARK: - Windows

    func showHistory() { appRouter.showHistory() }
    func hideHistory() { appRouter.hideHistory() }
    func showPreferences() { appRouter.showPreferences() }
    func quit() { appRouter.quit() }

    // MARK: - Paste / copy

    /// Closes History first so ⌘V lands in the app the user came from.
    func paste(_ item: ClipItem, plainText: Bool = false) {
        promptForAccessibilityOnce()
        appRouter.hideHistory()
        pasteClip.execute(item, plainText: plainText)
    }

    /// Menu-bar paste: the menu never stole focus, so no window to close.
    func pasteFromMenu(_ item: ClipItem) {
        promptForAccessibilityOnce()
        pasteClip.execute(item)
    }

    func pasteSelected(plainText: Bool = false) {
        guard let target = selectedClip ?? visibleClips.first else { return }
        paste(target, plainText: plainText)
    }

    func copyOnly(_ item: ClipItem) {
        pasteClip.execute(item, pasteImmediately: false)
    }

    func copySelected() {
        guard let target = selectedClip else { return }
        copyOnly(target)
    }

    func copyText(_ text: String) {
        pasteClip.executeTransformed(text: text, pasteImmediately: false)
    }

    private func promptForAccessibilityOnce() {
        guard !didPromptAccessibility else { return }
        didPromptAccessibility = true
        pasteClip.requestAccessibilityIfNeeded()
    }

    // MARK: - Paste stack

    func pasteNextFromStack() {
        guard let id = stackStore.popNext(), let item = clipboard.clip(id: id) else { return }
        pasteFromMenu(item)
    }

    func addToStack(_ item: ClipItem) { stackStore.push(item.id) }
    func clearStack() { stackStore.clear() }

    // MARK: - Edit / delete

    func rename(_ item: ClipItem, title: String) {
        updateClip.rename(item, title: title)
    }

    func openLink(_ item: ClipItem) {
        guard let url = item.url else { return }
        appRouter.hideHistory()
        appRouter.open(url)
    }

    func revealInFinder(_ item: ClipItem) {
        guard !item.filePaths.isEmpty else { return }
        appRouter.hideHistory()
        appRouter.revealInFinder(paths: item.filePaths)
    }

    func delete(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        if settings.confirmBeforeDeleting {
            let title = items.count == 1 ? "Delete this clip?" : "Delete \(items.count) clips?"
            guard confirmation.confirm(title: title, message: "This cannot be undone.", confirmTitle: "Delete") else { return }
        }
        if let preview = appState.previewClipID, items.contains(where: { $0.id == preview }) {
            appState.previewClipID = nil
        }
        deleteClips.execute(items)
    }

    func deleteSelected() {
        guard let target = selectedClip else { return }
        let index = visibleClips.firstIndex { $0.id == target.id }
        delete([target])
        if let index, !visibleClips.isEmpty {
            appState.selectedClipID = visibleClips[min(index, visibleClips.count - 1)].id
        }
    }

    func confirmDeleteAllIfNeeded() {
        if settings.confirmBeforeDeleting {
            guard confirmation.confirm(
                title: "Delete All History?",
                message: "Items pinned to a pinboard are kept. Everything else is removed.",
                confirmTitle: "Delete"
            ) else { return }
        }
        appState.previewClipID = nil
        deleteClips.executeDeleteAllHistory()
    }

    func toggleFavorite(_ item: ClipItem) {
        updateAIMemory.toggleFavorite(clipID: item.id)
    }

    // MARK: - Pinboards

    func createPinboard(name: String, colorHex: String = Pinboard.defaultColorHex) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let board = managePinboards.create(name: trimmed, colorHex: colorHex)
        appState.selectedPinboardID = board.id
    }

    func renamePinboard(_ board: Pinboard, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        managePinboards.rename(board, name: trimmed)
    }

    func setPinboardColor(_ board: Pinboard, colorHex: String) {
        managePinboards.setColor(board, colorHex: colorHex)
    }

    func deletePinboard(_ board: Pinboard) {
        managePinboards.delete(board)
        if appState.selectedPinboardID == board.id {
            appState.selectedPinboardID = nil
        }
    }

    func confirmDeletePinboard(_ board: Pinboard) {
        if settings.confirmBeforeDeleting {
            guard confirmation.confirm(
                title: "Delete “\(board.name)”?",
                message: "Clips stay in history. Only this pinboard is removed.",
                confirmTitle: "Delete"
            ) else { return }
        }
        deletePinboard(board)
    }

    func pin(_ item: ClipItem, to board: Pinboard) {
        managePinboards.pin(item, to: board)
    }

    func unpin(_ item: ClipItem, from board: Pinboard) {
        managePinboards.unpin(item, from: board)
    }

    func togglePin(_ item: ClipItem, on board: Pinboard) {
        if isPinned(item, to: board) {
            unpin(item, from: board)
        } else {
            pin(item, to: board)
        }
    }
}
