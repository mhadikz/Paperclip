import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {
    static let shared = PreferencesWindowController()

    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .clipboardAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyAppearance() }
        })
    }

    func show() {
        ensureWindow()
        applyAppearance()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() {
        if window != nil { return }

        let container = DependencyContainer.shared
        let content = SettingsView()
            .environmentObject(container)
            .environmentObject(container.settingsViewModel)
            .environmentObject(container.settings)
            .environmentObject(container.clipboardViewModel)
            .environmentObject(container.thumbnails)

        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 600)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Paperclip Settings"
        window.applyAppColorScheme(container.settings.appearanceMode)
        window.setAppGlassContentView(hostingView, tintAmount: container.settings.glassTintAmount)
        window.setContentSize(NSSize(width: 560, height: 600))
        window.minSize = NSSize(width: 520, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setFrameAutosaveName("PaperclipPreferences")

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in
                // Return focus to whatever the user was doing; an agent app has no other window.
                NSApp.hide(nil)
            }
        })

        self.window = window
    }

    private func applyAppearance() {
        let settings = DependencyContainer.shared.settings
        window?.applyAppColorScheme(settings.appearanceMode)
        window?.applyAppGlassTint(amount: settings.glassTintAmount)
    }
}
