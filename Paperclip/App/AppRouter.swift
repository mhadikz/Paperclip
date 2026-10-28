import Foundation
import AppKit

/// Window and system navigation. Views never touch `NSWorkspace`/`NSWindow` directly.
@MainActor
final class AppRouter {
    func showHistory() {
        HistoryWindowController.shared.show()
    }

    func hideHistory() {
        HistoryWindowController.shared.hide()
    }

    func toggleHistory() {
        HistoryWindowController.shared.toggle()
    }

    func showPreferences() {
        PreferencesWindowController.shared.show()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppDataLocation.rootURL])
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
