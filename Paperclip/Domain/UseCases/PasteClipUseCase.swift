import Foundation

/// Puts a clip back on the pasteboard and, when allowed, pastes it into the frontmost app.
@MainActor
struct PasteClipUseCase {
    let clipboard: ClipboardRepositoryProtocol
    let mediaStore: MediaStoring
    let pasteService: PasteServing
    let settings: SettingsProviding
    let monitor: ClipboardMonitoring

    /// Delay before ⌘V so the History panel has closed and key focus is back in the target app.
    static let keystrokeDelay: TimeInterval = 0.12

    /// - Parameter pasteImmediately: overrides the "paste into frontmost app" setting (nil = use setting).
    func execute(_ item: ClipItem, plainText: Bool = false, pasteImmediately: Bool? = nil) {
        let richText: Data? = {
            guard !plainText, let name = item.richTextFileName else { return nil }
            return mediaStore.loadData(fileName: name)
        }()
        pasteService.write(item, plainText: plainText, richText: richText)
        monitor.ignoreCurrentChange()
        clipboard.bumpToTop(id: item.id)

        if pasteImmediately ?? settings.pasteAndEnter {
            pasteService.sendPasteKeystroke(after: Self.keystrokeDelay)
        }
    }

    /// Pastes AI-transformed text. It is not inserted into history as a new clip.
    func executeTransformed(text: String, pasteImmediately: Bool? = nil) {
        pasteService.writeText(text)
        monitor.ignoreCurrentChange()
        if pasteImmediately ?? settings.pasteAndEnter {
            pasteService.sendPasteKeystroke(after: Self.keystrokeDelay)
        }
    }

    var canPasteIntoOtherApps: Bool { pasteService.canSendKeystrokes }

    /// Shows the system Accessibility prompt when auto-paste is on but not yet allowed.
    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        guard settings.pasteAndEnter, !pasteService.canSendKeystrokes else { return true }
        return pasteService.requestAccessibility()
    }
}
