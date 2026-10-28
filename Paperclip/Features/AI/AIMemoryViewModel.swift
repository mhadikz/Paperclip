import Foundation
import Combine

@MainActor
final class AIMemoryViewModel: ObservableObject {
    let appState: AppState
    let settings: AppSettings

    @Published private(set) var clips: [ClipItem] = []
    @Published private(set) var metadata: [UUID: AIMemoryMetadata] = [:]
    @Published var actionOutput: String?
    @Published var runningAction: SmartRewriteStyle?
    @Published var actionError: String?

    private let appRouter: AppRouter
    private let clipboard: ClipboardRepositoryProtocol
    private let aiMemory: AIMemoryRepositoryProtocol
    private let pasteClip: PasteClipUseCase
    private let searchMemory: SearchMemoryUseCase
    private let updateAIMemory: UpdateAIMemoryUseCase
    private let ai: AIMemoryServicing
    private var cancellables = Set<AnyCancellable>()
    private var actionTask: Task<Void, Never>?

    init(
        appState: AppState,
        appRouter: AppRouter,
        clipboard: ClipboardRepositoryProtocol,
        aiMemory: AIMemoryRepositoryProtocol,
        settings: AppSettings,
        pasteClip: PasteClipUseCase,
        searchMemory: SearchMemoryUseCase,
        updateAIMemory: UpdateAIMemoryUseCase,
        ai: AIMemoryServicing
    ) {
        self.appState = appState
        self.appRouter = appRouter
        self.clipboard = clipboard
        self.aiMemory = aiMemory
        self.settings = settings
        self.pasteClip = pasteClip
        self.searchMemory = searchMemory
        self.updateAIMemory = updateAIMemory
        self.ai = ai

        self.clips = clipboard.clips
        self.metadata = aiMemory.metadata

        clipboard.clipsPublisher
            .sink { [weak self] in self?.clips = $0 }
            .store(in: &cancellables)
        aiMemory.metadataPublisher
            .sink { [weak self] in self?.metadata = $0 }
            .store(in: &cancellables)
        appState.$selectedMemoryID
            .removeDuplicates()
            .sink { [weak self] _ in self?.clearActionOutput() }
            .store(in: &cancellables)
    }

    var favoriteClips: [ClipItem] {
        clips.filter { metadata[$0.id]?.isFavorite == true }
    }

    var selectedClip: ClipItem? {
        guard let id = appState.selectedClipID else { return nil }
        return clips.first { $0.id == id }
    }

    func metadata(for clip: ClipItem) -> AIMemoryMetadata? {
        metadata[clip.id]
    }

    func related(for clip: ClipItem) -> [ClipItem] {
        searchMemory.related(to: clip, metadata: metadata, clips: clips)
    }

    // MARK: - Actions

    func paste(_ clip: ClipItem, plainText: Bool = false) {
        appRouter.hideHistory()
        pasteClip.execute(clip, plainText: plainText)
    }

    func pasteSelected(plainText: Bool = false) {
        guard let clip = selectedClip else { return }
        paste(clip, plainText: plainText)
    }

    func pasteTransformed(_ text: String) {
        appRouter.hideHistory()
        pasteClip.executeTransformed(text: text)
    }

    func copyOnly(_ clip: ClipItem) {
        pasteClip.execute(clip, pasteImmediately: false)
    }

    func copySelected() {
        guard let clip = selectedClip else { return }
        copyOnly(clip)
    }

    func copyText(_ text: String) {
        pasteClip.executeTransformed(text: text, pasteImmediately: false)
    }

    func toggleFavorite(_ clip: ClipItem) {
        updateAIMemory.toggleFavorite(clipID: clip.id)
    }

    func updateTags(_ clip: ClipItem, tags: [String]) {
        updateAIMemory.updateTags(clipID: clip.id, tags: tags)
    }

    func selectMemory(_ id: UUID) {
        appState.selectedMemoryID = id
        appState.selectedClipID = id
    }

    func clearActionOutput() {
        actionTask?.cancel()
        actionOutput = nil
        actionError = nil
        runningAction = nil
    }

    func runSmartAction(_ style: SmartRewriteStyle, on clip: ClipItem) {
        guard let text = clip.text ?? clip.searchableText, !text.isEmpty else { return }
        actionTask?.cancel()
        runningAction = style
        actionError = nil
        let useAI = settings.useFoundationModels && settings.aiFeaturesEnabled
        let service = ai
        actionTask = Task { [weak self] in
            do {
                let output = try await service.rewrite(text: text, style: style, useAI: useAI)
                guard !Task.isCancelled else { return }
                self?.actionOutput = output
            } catch {
                guard !Task.isCancelled else { return }
                self?.actionError = error.localizedDescription
            }
            self?.runningAction = nil
        }
    }
}
