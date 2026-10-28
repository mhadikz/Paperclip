import Foundation
import OSLog

/// Privacy-safe logging. Messages are public strings that must never include clipboard
/// bodies, OCR text, file paths copied by the user, or secrets.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mhadikz.Paperclip"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let ui = Logger(subsystem: subsystem, category: "ui")

    static func event(_ message: String, logger: Logger = general) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String, logger: Logger = general) {
        logger.error("\(message, privacy: .public)")
    }
}
