// Renders the main SwiftUI surfaces offscreen with sample data so the design can be reviewed
// without launching the app or granting Screen Recording. Output: build/previews/*.png
//
//   scripts/render-previews.sh
import AppKit
import SwiftUI

@main
struct RenderPreviewsMain {
    @MainActor
    static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let world = PreviewWorld()
        for scheme in [AppearanceMode.light, .dark] {
            world.settings.appearanceMode = scheme
            let suffix = scheme == .light ? "light" : "dark"

            world.appState.navigationMode = .clipboard
            world.appState.previewClipID = nil
            world.appState.selectedClipID = world.clipboardViewModel.visibleClips.first?.id
            render(world.history(), size: CGSize(width: 460, height: 680), mode: scheme, to: outDir.appendingPathComponent("history-\(suffix).png"))

            world.appState.previewClipID = world.codeClipID
            render(world.history(), size: CGSize(width: 460, height: 680), mode: scheme, to: outDir.appendingPathComponent("history-preview-\(suffix).png"))
            world.appState.previewClipID = nil

            world.appState.navigationMode = .aiMemory
            world.appState.searchText = ""
            world.searchViewModel.refresh()
            render(world.history(), size: CGSize(width: 460, height: 680), mode: scheme, to: outDir.appendingPathComponent("memory-\(suffix).png"))

            world.appState.searchText = "docker command"
            world.searchViewModel.refresh()
            render(world.history(), size: CGSize(width: 460, height: 680), mode: scheme, to: outDir.appendingPathComponent("memory-search-\(suffix).png"))
            world.appState.searchText = ""
            world.appState.navigationMode = .clipboard

            render(world.settings(tab: 0), size: CGSize(width: 560, height: 720), mode: scheme, to: outDir.appendingPathComponent("settings-general-\(suffix).png"))
            render(world.settings(tab: 1), size: CGSize(width: 560, height: 640), mode: scheme, to: outDir.appendingPathComponent("settings-ai-\(suffix).png"))
            render(world.settings(tab: 3), size: CGSize(width: 560, height: 520), mode: scheme, to: outDir.appendingPathComponent("settings-clips-\(suffix).png"))
            render(world.settings(tab: 4), size: CGSize(width: 560, height: 520), mode: scheme, to: outDir.appendingPathComponent("settings-about-\(suffix).png"))
        }
        world.settings.appearanceMode = .light
        let sample = world.clipboard.clips[1]
        render(
            VStack(spacing: 12) {
                HistorySearchField(placeholder: "Search history", text: .constant(""), isFocused: FocusState<Bool>().projectedValue)
                ClipCardView(clip: sample, metadata: world.aiMemory.metadata(for: sample.id), thumbnail: nil, isSelected: true, onSelect: {}, onCopy: {}, onPaste: { _ in })
                ShortcutRecorderView(current: .default, onRecord: { _ in }, onReset: {})
                Button("Glass button") {}.appGlassButton()
                Text("plain text")
            }
            .padding(20)
            .appWindowFill()
            .appBrandChrome()
            .environmentObject(world.settings),
            size: CGSize(width: 460, height: 420), mode: .light, to: outDir.appendingPathComponent("components-light.png")
        )
        print("→ Previews written to \(outDir.path)")
        exit(0)
    }

    @MainActor
    static func render<V: View>(_ view: V, size: CGSize, mode: AppearanceMode, to url: URL) {
        NSApp.appearance = mode.nsAppearance
        // Glass effects cannot be cached offscreen; render the opaque (Reduce Transparency) variant.
        let hosting = NSHostingView(rootView: AnyView(view.environment(\.appGlassDisabled, true)))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = mode.nsAppearance
        // Far off-screen but ordered, so layer-backed effect views (glass) actually composite.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = mode.nsAppearance
        window.backgroundColor = mode == .dark ? NSColor(hex: AppPalette.midnightHex) : NSColor(hex: AppPalette.whiteHex)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle async state (thumbnails, lazy stacks).
        for _ in 0..<8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        // Composite over the window background so transparent glass areas are visible.
        let image = NSImage(size: size)
        image.lockFocus()
        (window.backgroundColor ?? .white).setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}

/// Isolated in-memory object graph with representative clips.
@MainActor
final class PreviewWorld {
    let root: URL
    let settings: AppSettings
    let appState = AppState()
    let router = AppRouter()
    let media: MediaStore
    let clipboard: ClipboardRepository
    let pinboards: PinboardRepository
    let aiMemory: AIMemoryRepository
    let stack = PasteStackStore()
    let monitor = ClipboardMonitor()
    let paste: PasteService
    let ai = AIService()
    let queue = AIProcessingQueue()
    let thumbnails: ThumbnailStore
    let clipboardViewModel: ClipboardViewModel
    let searchViewModel: SearchViewModel
    let aiViewModel: AIMemoryViewModel
    let settingsViewModel: SettingsViewModel
    var codeClipID: UUID!

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperclipPreviews-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("Media"), withIntermediateDirectories: true)
        let previewDefaults = UserDefaults(suiteName: "PaperclipPreviews")!
        previewDefaults.removePersistentDomain(forName: "PaperclipPreviews")
        settings = AppSettings(defaults: previewDefaults)
        media = MediaStore(rootURL: root.appendingPathComponent("Media"))
        clipboard = ClipboardRepository(persistence: ClipPersistence(rootURL: root), mediaStore: media, publishSnapshot: { _, _ in })
        pinboards = PinboardRepository(persistence: ClipPersistence(rootURL: root))
        aiMemory = AIMemoryRepository(store: AIMetadataStore(url: root.appendingPathComponent("ai.json")))
        paste = PasteService(mediaStore: media)
        thumbnails = ThumbnailStore(mediaStore: media)

        let pasteClip = PasteClipUseCase(clipboard: clipboard, mediaStore: media, pasteService: paste, settings: settings, monitor: monitor)
        let deleteClips = DeleteClipsUseCase(clipboard: clipboard, pinboards: pinboards, aiMemory: aiMemory, stack: stack)
        let searchMemory = SearchMemoryUseCase(settings: settings, ai: ai)
        let updateAIMemory = UpdateAIMemoryUseCase(aiMemory: aiMemory)
        clipboardViewModel = ClipboardViewModel(
            appState: appState, appRouter: router, clipboard: clipboard, pinboards: pinboards, aiMemory: aiMemory,
            stack: stack, settings: settings, pasteClip: pasteClip, deleteClips: deleteClips,
            managePinboards: ManagePinboardUseCase(pinboards: pinboards), updateClip: UpdateClipUseCase(clipboard: clipboard),
            updateAIMemory: updateAIMemory, confirmation: AlwaysYes()
        )
        searchViewModel = SearchViewModel(appState: appState, clipboard: clipboard, pinboards: pinboards, aiMemory: aiMemory, searchMemory: searchMemory)
        aiViewModel = AIMemoryViewModel(appState: appState, appRouter: router, clipboard: clipboard, aiMemory: aiMemory, settings: settings, pasteClip: pasteClip, searchMemory: searchMemory, updateAIMemory: updateAIMemory, ai: ai)
        settingsViewModel = SettingsViewModel(settings: settings, appRouter: router, clipboard: clipboard, aiMemory: aiMemory, updateAIMemory: updateAIMemory, deleteClips: deleteClips, pasteService: paste, launchAtLogin: LaunchAtLoginService(), ai: ai, aiQueue: queue, hotKeyApplier: { true })
        seed()
    }

    private func seed() {
        let now = Date()
        func add(_ clip: ClipItem, minutesAgo: Double, app: String) {
            var c = clip
            c.createdAt = now.addingTimeInterval(-minutesAgo * 60)
            c.sourceAppName = app
            clipboard.insert(c)
            let result = HeuristicClassifier.classify(clip: c)
            var meta = AIMemoryMetadata(clipID: c.id, status: .completed)
            meta.category = result.category
            meta.replaceTags(result.tags)
            meta.summary = result.summary
            aiMemory.upsert(meta)
        }
        add(ClipItem(contentType: .text, text: "Ship the 1.3 release notes to the team before Friday, and remember the widget gallery needs a fresh screenshot."), minutesAgo: 2, app: "Notes")
        let code = ClipItem(contentType: .text, text: """
        import Foundation

        func retry<T>(_ attempts: Int, _ body: () async throws -> T) async throws -> T {
            var lastError: Error?
            for _ in 0..<attempts {
                do { return try await body() } catch { lastError = error }
            }
            throw lastError ?? CancellationError()
        }
        """)
        codeClipID = code.id
        add(code, minutesAgo: 14, app: "Xcode")
        add(ClipItem(contentType: .link, text: "https://github.com/apple/swift-foundation/pull/1182"), minutesAgo: 35, app: "Safari")
        add(ClipItem(contentType: .text, text: "docker compose up -d --build && docker compose logs -f api"), minutesAgo: 70, app: "Terminal")
        add(ClipItem(contentType: .file, filePaths: ["/Users/sam/Documents/Reports/quarterly-summary.pdf"]), minutesAgo: 200, app: "Finder")
        if let png = Self.sampleImage(), let name = media.saveImageData(png, id: UUID()) {
            add(ClipItem(contentType: .image, mediaFileName: name, searchableText: "Quarterly revenue chart", contentHash: ContentHasher.sha256(png), mediaByteCount: png.count), minutesAgo: 1500, app: "Preview")
        }
        add(ClipItem(contentType: .text, text: "SELECT customer_id, SUM(total) FROM orders WHERE created_at > now() - interval '30 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 20;"), minutesAgo: 3000, app: "DataGrip")

        let board = pinboards.create(name: "Release", colorHex: Pinboard.colorPalette[2])
        if let first = clipboard.clips.first { pinboards.pin(clipID: first.id, to: board.id) }
        if let link = clipboard.clips.first(where: { $0.contentType == .link }) {
            var meta = aiMemory.metadata(for: link.id) ?? AIMemoryMetadata(clipID: link.id)
            meta.isFavorite = true
            aiMemory.upsert(meta)
        }
    }

    private static func sampleImage() -> Data? {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(hex: "#0A4A86")?.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(hex: "#FFC300")?.setFill()
        for i in 0..<8 {
            let h = CGFloat(60 + (i * 37) % 250)
            NSRect(x: 40 + CGFloat(i) * 72, y: 40, width: 48, height: h).fill()
        }
        image.unlockFocus()
        return image.pngData()
    }

    func history() -> some View {
        ClipboardView()
            .environmentObject(clipboardViewModel)
            .environmentObject(aiViewModel)
            .environmentObject(searchViewModel)
            .environmentObject(settingsViewModel)
            .environmentObject(thumbnails)
            .environmentObject(appState)
            .environmentObject(settings)
    }

    func settings(tab: Int) -> some View {
        Group {
            switch tab {
            case 0: AnyView(GeneralPreferencesView())
            case 1: AnyView(AIPreferencesView())
            case 3: AnyView(ClipsManagementPreferencesView())
            default: AnyView(AboutPreferencesView())
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .appWindowFill()
        .toggleStyle(AppSwitchToggleStyle())
        .appBrandChrome()
        .environmentObject(settingsViewModel)
        .environmentObject(settings)
        .environmentObject(clipboardViewModel)
        .environmentObject(thumbnails)
    }
}

@MainActor
struct AlwaysYes: ConfirmationPrompting {
    func confirm(title: String, message: String, confirmTitle: String) -> Bool { true }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
