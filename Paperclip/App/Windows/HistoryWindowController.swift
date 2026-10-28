import AppKit
import SwiftUI

/// The History panel is a non-activating floating `NSPanel`: it takes keyboard focus without
/// activating this app, so the app the user was working in stays frontmost and receives the
/// ⌘V we send after a selection. That is what makes "paste into frontmost app" work.
@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()

    private var panel: NSPanel?
    private let windowDelegate = HistoryWindowDelegate()
    private var observers: [NSObjectProtocol] = []
    private var savedFrame: NSRect?

    private static let defaultSize = NSSize(width: 460, height: 680)
    private static let minSize = NSSize(width: 400, height: 480)
    private static let maxSize = NSSize(width: 760, height: 1400)

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .clipboardPrivacyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPrivacy() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .clipboardAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyAppearance() }
        })
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        ensurePanel()
        guard let panel else { return }
        applyPrivacy()
        applyAppearance()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        let appState = DependencyContainer.shared.appState
        appState.isHistoryPresented = true
        appState.historyPresentationCount += 1
    }

    func hide() {
        guard let panel else { return }
        savedFrame = panel.frame
        panel.orderOut(nil)
        let appState = DependencyContainer.shared.appState
        appState.isHistoryPresented = false
        appState.resetHistorySession()
    }

    private func ensurePanel() {
        if panel != nil { return }

        let container = DependencyContainer.shared
        let content = ClipboardView()
            .environmentObject(container)
            .environmentObject(container.clipboardViewModel)
            .environmentObject(container.aiMemoryViewModel)
            .environmentObject(container.searchViewModel)
            .environmentObject(container.settingsViewModel)
            .environmentObject(container.thumbnails)
            .environmentObject(container.appState)
            .environmentObject(container.settings)

        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = NSRect(origin: .zero, size: Self.defaultSize)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard History"
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.applyAppColorScheme(container.settings.appearanceMode)
        panel.setAppGlassContentView(hostingView, tintAmount: container.settings.glassTintAmount)
        panel.minSize = Self.minSize
        panel.maxSize = Self.maxSize
        panel.animationBehavior = .utilityWindow
        panel.delegate = windowDelegate

        self.panel = panel
    }

    /// Centered on the screen that currently holds the mouse; remembers the last size.
    private func positionPanel() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = savedFrame?.size ?? Self.defaultSize
        let width = min(max(size.width, Self.minSize.width), min(Self.maxSize.width, visible.width - 32))
        let height = min(max(size.height, Self.minSize.height), visible.height * 0.9)
        let x = visible.midX - width / 2
        let y = visible.midY - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func applyAppearance() {
        let settings = DependencyContainer.shared.settings
        panel?.applyAppColorScheme(settings.appearanceMode)
        panel?.applyAppGlassTint(amount: settings.glassTintAmount)
    }

    private func applyPrivacy() {
        guard let panel else { return }
        panel.sharingType = DependencyContainer.shared.settings.hideFromScreenSharing ? .none : .readWrite
    }
}

private final class HistoryWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        HistoryWindowController.shared.hide()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        // A transient panel should get out of the way when the user clicks elsewhere,
        // unless one of our own windows (Preferences, an alert) took focus.
        guard let window = notification.object as? NSWindow, window.isVisible else { return }
        if NSApp.keyWindow == nil || NSApp.keyWindow === window {
            HistoryWindowController.shared.hide()
        }
    }
}
