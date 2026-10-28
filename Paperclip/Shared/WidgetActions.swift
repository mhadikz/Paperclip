import AppIntents
import AppKit
import Foundation

enum WidgetClipAction {
    static let copyNotification = Notification.Name("com.mhadikz.Paperclip.widgetCopyClip")

    static func notifyCopy(clipID: String) {
        writeCommand(clipID: clipID)
        DistributedNotificationCenter.default().postNotificationName(
            copyNotification,
            object: clipID,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func consumeCommandID() -> UUID? {
        let url = WidgetSnapshot.commandFileURL
        guard let data = try? Data(contentsOf: url, options: [.uncached]),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = payload["id"] as? String,
              let id = UUID(uuidString: raw)
        else { return nil }
        try? FileManager.default.removeItem(at: url)
        return id
    }

    private static func writeCommand(clipID: String) {
        let url = WidgetSnapshot.commandFileURL
        let payload: [String: Any] = [
            "id": clipID,
            "at": Date().timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
}

/// Same action as History’s Copy button (`copyOnly` / write pasteboard, no ⌘V).
struct CopyClipIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy"
    static var description: IntentDescription = IntentDescription("Copy to clipboard")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Clip ID")
    var clipID: String

    @Parameter(title: "Copy Text")
    var copyText: String

    init() {
        clipID = ""
        copyText = ""
    }

    init(clipID: UUID, copyText: String?) {
        self.clipID = clipID.uuidString
        self.copyText = copyText ?? ""
    }

    func perform() async throws -> some IntentResult {
        if !copyText.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(copyText, forType: .string)
        }
        WidgetClipAction.notifyCopy(clipID: clipID)
        return .result()
    }
}
