import Foundation

/// Publishes a small, preview-oriented snapshot for the WidgetKit extension.
enum WidgetSnapshotWriter {
    static let maxItems = 8
    private static let maxCopyTextCharacters = 50_000
    private static let queue = DispatchQueue(label: "com.mhadikz.Paperclip.widget-snapshot", qos: .utility)
    private static let lock = NSLock()
    private static var scheduled: DispatchWorkItem?

    /// Coalesces bursts; encodes and writes on a utility queue.
    static func write(clips: [ClipItem], appearance: AppearanceMode) {
        let items: [WidgetSnapshot.Item] = clips.prefix(maxItems).compactMap { clip in
            if let text = clip.text, SensitiveContentFilter.looksSensitive(text) {
                return nil
            }
            return WidgetSnapshot.Item(
                id: clip.id,
                contentType: clip.contentType.rawValue,
                preview: clip.preview,
                createdAt: clip.createdAt,
                copyText: copyText(for: clip)
            )
        }
        let snapshot = WidgetSnapshot(updatedAt: Date(), items: items, appearance: appearance.rawValue)

        lock.lock()
        scheduled?.cancel()
        let item = DispatchWorkItem { persist(snapshot) }
        scheduled = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private static func persist(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        var seen = Set<String>()
        for url in [WidgetSnapshot.fileURL, WidgetSnapshot.sharedGroupFileURL, WidgetSnapshot.applicationSupportFileURL] {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipboardSnapshotDidWrite, object: nil)
        }
    }

    private static func copyText(for clip: ClipItem) -> String? {
        switch clip.contentType {
        case .text, .link:
            guard let text = clip.text, !text.isEmpty else { return nil }
            return text.count <= maxCopyTextCharacters ? text : String(text.prefix(maxCopyTextCharacters))
        case .image, .file:
            return nil
        }
    }
}
