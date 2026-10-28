import Darwin
import Foundation

/// Preview-only snapshot for WidgetKit. Never includes full clipboard bodies.
struct WidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var items: [Item]
    /// `system`, `light`, or `dark` — widget follows Preferences when set.
    var appearance: String?

    struct Item: Codable, Equatable, Identifiable {
        var id: UUID
        var contentType: String
        var preview: String
        var createdAt: Date
        /// Full text for text/link clips so the widget can copy without the host app.
        var copyText: String?
    }

    static let empty = WidgetSnapshot(updatedAt: .distantPast, items: [])

    static let sample = WidgetSnapshot(
        updatedAt: Date(),
        items: [
            Item(id: UUID(), contentType: "text", preview: "Recent clip preview", createdAt: Date(), copyText: "Recent clip preview"),
            Item(id: UUID(), contentType: "link", preview: "https://example.com", createdAt: Date().addingTimeInterval(-120), copyText: "https://example.com"),
            Item(id: UUID(), contentType: "image", preview: "Image", createdAt: Date().addingTimeInterval(-3600), copyText: nil)
        ]
    )

    static let widgetKind = "ClipboardHistoryWidget"
    static let urlScheme = "paperclip"
    static let appGroupID = "group.com.mhadikz.Paperclip"

    /// Write target. The host app's app-group container is preferred when containermanagerd grants it.
    static var fileURL: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container.appendingPathComponent("widget-snapshot.json")
        }
        return sharedGroupFileURL
    }

    /// Real `~/Library/Group Containers/...` — sandboxed `containerURL` is often nil without a Team ID.
    static var sharedGroupFileURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupID, isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    static var applicationSupportFileURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/Paperclip/widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var seen = Set<String>()
        for url in loadCandidateURLs {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            guard let data = try? Data(contentsOf: url, options: [.uncached]) else { continue }
            if let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) {
                return snapshot
            }
        }
        return .empty
    }

    private static var loadCandidateURLs: [URL] {
        [
            fileURL,
            sharedGroupFileURL,
            applicationSupportFileURL
        ]
    }

    /// `homeDirectoryForCurrentUser` is the container home inside a sandbox; passwd still has the real home.
    private static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()) {
            let dir = String(cString: pw.pointee.pw_dir)
            if !dir.isEmpty {
                return URL(fileURLWithPath: dir, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func openHistoryURL() -> URL {
        URL(string: "\(urlScheme)://open")!
    }

    static func pasteURL(id: UUID) -> URL {
        URL(string: "\(urlScheme)://paste/\(id.uuidString)")!
    }

    static var commandFileURL: URL {
        sharedGroupFileURL.deletingLastPathComponent().appendingPathComponent("widget-command.json")
    }
}

extension Notification.Name {
    static let clipboardSnapshotDidWrite = Notification.Name("clipboardSnapshotDidWrite")
}
