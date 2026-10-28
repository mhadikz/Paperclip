import AppKit

@MainActor
struct AlertConfirmationPrompter: ConfirmationPrompting {
    func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        let wasActive = NSApp.isActive
        let result = alert.runModal() == .alertFirstButtonReturn
        if !wasActive {
            // The History panel is non-activating; a modal alert activated us. Step back out.
            NSApp.hide(nil)
            HistoryWindowController.shared.show()
        }
        return result
    }
}
