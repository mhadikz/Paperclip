import AppKit
import Foundation
import ApplicationServices

/// Writes clips to the pasteboard and optionally pastes them with a synthetic ⌘V.
@MainActor
final class PasteService: PasteServing {
    private let mediaStore: MediaStoring
    private var warnedAboutAccessibility = false

    init(mediaStore: MediaStoring) {
        self.mediaStore = mediaStore
    }

    func write(_ item: ClipItem, plainText: Bool, richText: Data?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentType {
        case .text:
            let text = item.text ?? ""
            if let richText, !plainText {
                pasteboard.declareTypes([.rtf, .string], owner: nil)
                pasteboard.setData(richText, forType: .rtf)
                pasteboard.setString(text, forType: .string)
            } else {
                pasteboard.setString(text, forType: .string)
            }
        case .link:
            let text = item.text ?? ""
            if plainText {
                pasteboard.setString(text, forType: .string)
            } else {
                pasteboard.declareTypes([.string, .URL], owner: nil)
                pasteboard.setString(text, forType: .string)
                pasteboard.setString(text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .URL)
            }
        case .image:
            if plainText, let text = item.searchableText, !text.isEmpty {
                pasteboard.setString(text, forType: .string)
            } else if let fileName = item.mediaFileName, let data = mediaStore.loadData(fileName: fileName) {
                pasteboard.declareTypes([.png, .tiff], owner: nil)
                pasteboard.setData(data, forType: .png)
                if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }
        case .file:
            if plainText {
                pasteboard.setString(item.filePaths.joined(separator: "\n"), forType: .string)
            } else {
                let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
                pasteboard.writeObjects(urls)
            }
        }
    }

    func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    var canSendKeystrokes: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func sendPasteKeystroke(after delay: TimeInterval) {
        guard canSendKeystrokes else {
            if !warnedAboutAccessibility {
                warnedAboutAccessibility = true
                AppLogger.event("Paste keystroke skipped: Accessibility not granted", logger: AppLogger.clipboard)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalKeyboardEvents], state: .eventSuppressionStateSuppressionInterval)
        let keyV: CGKeyCode = 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
