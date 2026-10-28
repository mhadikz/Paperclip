import Foundation
import AppKit
import Carbon

@MainActor
final class URLEventHandler: NSObject {
    static let shared = URLEventHandler()

    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc
    private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard
            let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: string)
        else { return }
        Task { @MainActor in
            DependencyContainer.shared.handleOpenURL(url)
        }
    }
}
