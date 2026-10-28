import Foundation
import Combine
import WidgetKit
import AppKit
import Darwin

/// Composition root — builds and owns the object graph.
@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    // MARK: - Core

    let appState: AppState
    let appRouter: AppRouter
    let settings: AppSettings

    // MARK: - Data

    let clipboardRepository: ClipboardRepository
    let pinboardRepository: PinboardRepository
    let aiMemoryRepository: AIMemoryRepository
    let pasteStackStore: PasteStackStore
    let mediaStore: MediaStoring
    let pasteService: PasteService
    let monitor: ClipboardMonitor
    let hotKeyManager: HotKeyManager
    let launchAtLogin: LaunchAtLoginService
    let aiService: AIService
    let aiQueue: AIProcessingQueue
    let thumbnails: ThumbnailStore

    // MARK: - Use Cases

    private(set) lazy var captureClip: CaptureClipUseCase = makeCaptureClip()
    private(set) lazy var pasteClip: PasteClipUseCase = makePasteClip()
    private(set) lazy var deleteClips: DeleteClipsUseCase = makeDeleteClips()
    private(set) lazy var managePinboards: ManagePinboardUseCase = ManagePinboardUseCase(pinboards: pinboardRepository)
    private(set) lazy var updateClip: UpdateClipUseCase = UpdateClipUseCase(clipboard: clipboardRepository)
    private(set) lazy var searchMemory: SearchMemoryUseCase = SearchMemoryUseCase(settings: settings, ai: aiService)
    private(set) lazy var processAI: ProcessAIMemoryUseCase = makeProcessAI()
    private(set) lazy var enqueueAI: EnqueueAIProcessingUseCase = makeEnqueueAI()
    private(set) lazy var updateAIMemory: UpdateAIMemoryUseCase = UpdateAIMemoryUseCase(aiMemory: aiMemoryRepository)

    // MARK: - Feature ViewModels

    private(set) lazy var clipboardViewModel: ClipboardViewModel = makeClipboardViewModel()
    private(set) lazy var searchViewModel: SearchViewModel = makeSearchViewModel()
    private(set) lazy var aiMemoryViewModel: AIMemoryViewModel = makeAIMemoryViewModel()
    private(set) lazy var settingsViewModel: SettingsViewModel = makeSettingsViewModel()

    private var didStart = false
    private var lifetimeObservers: [NSObjectProtocol] = []
    private var widgetCommandSource: DispatchSourceFileSystemObject?

    private init() {
        appState = AppState()
        appRouter = AppRouter()
        let settings = AppSettings.shared
        self.settings = settings

        let persistence = ClipPersistence()
        let media = MediaStore()
        mediaStore = media
        pasteService = PasteService(mediaStore: media)
        monitor = ClipboardMonitor()
        hotKeyManager = HotKeyManager()
        launchAtLogin = LaunchAtLoginService()
        aiService = AIService()
        aiQueue = AIProcessingQueue()
        thumbnails = ThumbnailStore(mediaStore: media)

        clipboardRepository = ClipboardRepository(
            persistence: persistence,
            mediaStore: media,
            appearance: { [settings] in settings.appearanceMode }
        )
        pinboardRepository = PinboardRepository(persistence: persistence)
        aiMemoryRepository = AIMemoryRepository(store: AIMetadataStore())
        pasteStackStore = PasteStackStore()

        aiMemoryRepository.prune(keeping: Set(clipboardRepository.clips.map(\.id)))
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        let queue = aiQueue
        let process = processAI
        Task {
            await queue.setHandler { clipID in
                await process.execute(clipID: clipID)
            }
        }

        monitor.onNewContent = { [weak self] content, bundleID, appName in
            Task { @MainActor in
                self?.captureClip.execute(content: content, bundleID: bundleID, appName: appName)
            }
        }
        monitor.start()

        hotKeyManager.onHotKey = { [weak self] in
            self?.appRouter.toggleHistory()
        }
        applyHotKey()
        syncLaunchAtLogin()

        enqueueAI.backfill(from: clipboardRepository.clips)
        WidgetSnapshotWriter.write(clips: clipboardRepository.clips, appearance: settings.appearanceMode)
        URLEventHandler.shared.install()
        installWidgetCopyRelay()
        installObservers()
        AppLogger.event("DependencyContainer started")
    }

    // MARK: - System integration

    /// Returns false when the shortcut could not be registered (taken by another app).
    @discardableResult
    func applyHotKey() -> Bool {
        hotKeyManager.register(settings.hotKey)
    }

    private func syncLaunchAtLogin() {
        // The system is the source of truth; keep the toggle honest after reinstalls.
        if settings.launchAtLogin != launchAtLogin.isEnabled {
            settings.launchAtLogin = launchAtLogin.isEnabled
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        lifetimeObservers.append(center.addObserver(forName: .clipboardSnapshotDidWrite, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadWidgets() }
        })
        lifetimeObservers.append(center.addObserver(forName: .clipboardAppearanceChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                WidgetSnapshotWriter.write(clips: self.clipboardRepository.clips, appearance: self.settings.appearanceMode)
            }
        })
        lifetimeObservers.append(center.addObserver(forName: .clipboardHotKeyChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyHotKey() }
        })
        lifetimeObservers.append(center.addObserver(forName: .clipboardLaunchAtLoginChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try self.launchAtLogin.setEnabled(self.settings.launchAtLogin)
                } catch {
                    AppLogger.error("Launch at login change failed: \(error.localizedDescription)")
                }
                if self.settings.launchAtLogin != self.launchAtLogin.isEnabled {
                    self.settings.launchAtLogin = self.launchAtLogin.isEnabled
                }
            }
        })
        lifetimeObservers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushAll()
            }
        })
    }

    func flushAll() {
        clipboardRepository.flush()
        pinboardRepository.flush()
        aiMemoryRepository.flush()
    }

    // MARK: - URL scheme / widget

    func handleOpenURL(_ url: URL) {
        guard url.scheme == WidgetSnapshot.urlScheme else { return }
        let host = (url.host ?? "").lowercased()
        switch host {
        case "paste":
            if let id = pasteClipID(from: url) { copyClipFromWidget(id: id) }
        case "settings", "preferences":
            appRouter.showPreferences()
        default:
            appRouter.showHistory()
        }
    }

    private func pasteClipID(from url: URL) -> UUID? {
        if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "id" })?.value,
           let id = UUID(uuidString: raw) {
            return id
        }
        let pathID = url.path.split(separator: "/").map(String.init).first { !$0.isEmpty }
        return pathID.flatMap(UUID.init(uuidString:))
    }

    private func copyClipFromWidget(id: UUID) {
        guard let clip = clipboardRepository.clip(id: id) else { return }
        clipboardViewModel.copyOnly(clip)
    }

    private func installWidgetCopyRelay() {
        lifetimeObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: WidgetClipAction.copyNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let raw = notification.object as? String
                Task { @MainActor in
                    guard let raw, let id = UUID(uuidString: raw) else { return }
                    self?.copyClipFromWidget(id: id)
                }
            }
        )
        let commandDir = WidgetSnapshot.commandFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: commandDir, withIntermediateDirectories: true)
        let fd = open(commandDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let id = WidgetClipAction.consumeCommandID() else { return }
                self?.copyClipFromWidget(id: id)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        widgetCommandSource = source
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }

    // MARK: - Factories

    private func makeProcessAI() -> ProcessAIMemoryUseCase {
        ProcessAIMemoryUseCase(clipboard: clipboardRepository, aiMemory: aiMemoryRepository, settings: settings, ai: aiService)
    }

    private func makeEnqueueAI() -> EnqueueAIProcessingUseCase {
        EnqueueAIProcessingUseCase(aiMemory: aiMemoryRepository, settings: settings, queue: aiQueue)
    }

    private func makeCaptureClip() -> CaptureClipUseCase {
        CaptureClipUseCase(
            clipboard: clipboardRepository,
            pinboards: pinboardRepository,
            aiMemory: aiMemoryRepository,
            mediaStore: mediaStore,
            settings: settings,
            enqueueAI: enqueueAI
        )
    }

    private func makePasteClip() -> PasteClipUseCase {
        PasteClipUseCase(
            clipboard: clipboardRepository,
            mediaStore: mediaStore,
            pasteService: pasteService,
            settings: settings,
            monitor: monitor
        )
    }

    private func makeDeleteClips() -> DeleteClipsUseCase {
        DeleteClipsUseCase(
            clipboard: clipboardRepository,
            pinboards: pinboardRepository,
            aiMemory: aiMemoryRepository,
            stack: pasteStackStore
        )
    }

    private func makeClipboardViewModel() -> ClipboardViewModel {
        ClipboardViewModel(
            appState: appState,
            appRouter: appRouter,
            clipboard: clipboardRepository,
            pinboards: pinboardRepository,
            aiMemory: aiMemoryRepository,
            stack: pasteStackStore,
            settings: settings,
            pasteClip: pasteClip,
            deleteClips: deleteClips,
            managePinboards: managePinboards,
            updateClip: updateClip,
            updateAIMemory: updateAIMemory,
            confirmation: AlertConfirmationPrompter()
        )
    }

    private func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(
            appState: appState,
            clipboard: clipboardRepository,
            pinboards: pinboardRepository,
            aiMemory: aiMemoryRepository,
            searchMemory: searchMemory
        )
    }

    private func makeAIMemoryViewModel() -> AIMemoryViewModel {
        AIMemoryViewModel(
            appState: appState,
            appRouter: appRouter,
            clipboard: clipboardRepository,
            aiMemory: aiMemoryRepository,
            settings: settings,
            pasteClip: pasteClip,
            searchMemory: searchMemory,
            updateAIMemory: updateAIMemory,
            ai: aiService
        )
    }

    private func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            settings: settings,
            appRouter: appRouter,
            clipboard: clipboardRepository,
            aiMemory: aiMemoryRepository,
            updateAIMemory: updateAIMemory,
            deleteClips: deleteClips,
            pasteService: pasteService,
            launchAtLogin: launchAtLogin,
            ai: aiService,
            aiQueue: aiQueue,
            hotKeyApplier: { [weak self] in self?.applyHotKey() ?? false }
        )
    }
}
