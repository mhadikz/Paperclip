import Foundation
import Combine
import AppKit

@MainActor
final class SettingsViewModel: ObservableObject {
    let settings: AppSettings

    @Published var availabilityText = "Checking…"
    @Published private(set) var isFoundationModelsAvailable = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var loginItemStatus = ""
    @Published private(set) var hotKeyError: String?
    @Published private(set) var storageSummary = StorageSummary()
    @Published private(set) var aiPendingCount = 0

    struct StorageSummary: Equatable {
        var clipCount = 0
        var imageCount = 0
        var byteCount = 0
    }

    private let appRouter: AppRouter
    private let clipboard: ClipboardRepositoryProtocol
    private let aiMemory: AIMemoryRepositoryProtocol
    private let updateAIMemory: UpdateAIMemoryUseCase
    private let deleteClips: DeleteClipsUseCase
    private let pasteService: PasteServing
    private let launchAtLogin: LaunchAtLoginService
    private let ai: AIMemoryServicing
    private let aiQueue: AIProcessingQueuing
    private let hotKeyApplier: () -> Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AppSettings,
        appRouter: AppRouter,
        clipboard: ClipboardRepositoryProtocol,
        aiMemory: AIMemoryRepositoryProtocol,
        updateAIMemory: UpdateAIMemoryUseCase,
        deleteClips: DeleteClipsUseCase,
        pasteService: PasteServing,
        launchAtLogin: LaunchAtLoginService,
        ai: AIMemoryServicing,
        aiQueue: AIProcessingQueuing,
        hotKeyApplier: @escaping () -> Bool
    ) {
        self.settings = settings
        self.appRouter = appRouter
        self.clipboard = clipboard
        self.aiMemory = aiMemory
        self.updateAIMemory = updateAIMemory
        self.deleteClips = deleteClips
        self.pasteService = pasteService
        self.launchAtLogin = launchAtLogin
        self.ai = ai
        self.aiQueue = aiQueue
        self.hotKeyApplier = hotKeyApplier

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshSystemStatus() }
            .store(in: &cancellables)
        clipboard.clipsPublisher
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStorage() }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    func refreshAll() {
        refreshSystemStatus()
        refreshStorage()
        Task { await refreshAvailability() }
    }

    func refreshSystemStatus() {
        accessibilityGranted = pasteService.canSendKeystrokes
        loginItemStatus = launchAtLogin.statusDescription
    }

    func refreshAvailability() async {
        availabilityText = await ai.availabilityMessage()
        isFoundationModelsAvailable = await ai.isFoundationModelsAvailable()
        aiPendingCount = await aiQueue.pendingCount()
    }

    func refreshStorage() {
        let clips = clipboard.clips
        let count = clips.count
        let images = clips.filter { $0.contentType == .image }.count
        Task { [weak self] in
            let bytes = await Task.detached(priority: .utility) { AppDataLocation.totalByteCount() }.value
            self?.storageSummary = StorageSummary(clipCount: count, imageCount: images, byteCount: bytes)
        }
    }

    // MARK: - Shortcut

    func applyHotKey(_ spec: HotKeySpec) {
        guard spec.isValid else {
            hotKeyError = "Add ⌘, ⌃ or ⌥ so the shortcut does not interfere with typing."
            return
        }
        let previous = settings.hotKey
        settings.hotKey = spec
        if hotKeyApplier() {
            hotKeyError = nil
        } else {
            hotKeyError = "\(spec.displayString) could not be registered. It may be reserved by macOS or another app."
            settings.hotKey = previous
            _ = hotKeyApplier()
        }
    }

    func resetHotKey() {
        applyHotKey(.default)
    }

    // MARK: - System

    func requestAccessibility() {
        accessibilityGranted = pasteService.requestAccessibility()
    }

    func openAccessibilitySettings() {
        appRouter.openAccessibilitySettings()
    }

    func openLoginItemsSettings() {
        appRouter.openLoginItemsSettings()
    }

    func revealDataFolder() {
        appRouter.revealDataFolder()
    }

    // MARK: - AI maintenance

    func reprocessAllAI() {
        let ids = clipboard.clips.map(\.id)
        let queue = aiQueue
        Task {
            await queue.enqueueMany(ids)
            await refreshAvailability()
        }
    }

    func clearAIMetadata() {
        updateAIMemory.clearAll()
    }

    // MARK: - Clips

    func delete(_ items: [ClipItem]) {
        deleteClips.execute(items)
    }

    func deleteAllHistory() {
        deleteClips.executeDeleteAllHistory()
    }
}
