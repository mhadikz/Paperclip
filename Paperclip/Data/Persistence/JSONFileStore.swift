import Foundation

/// Coalesced, background JSON persistence for one value.
///
/// - Saves are debounced (`delay`) and encoded off the main thread, so a burst of
///   capture → trim → metadata updates costs one write instead of several.
/// - `flush()` writes the latest pending value synchronously (used on quit).
/// - A file that no longer decodes is moved aside (`*.corrupt-<timestamp>`) instead of being
///   silently replaced by an empty value on the next save.
/// - The first successful load of a session leaves a `.bak` copy next to the file.
final class JSONFileStore<Value: Codable>: @unchecked Sendable {
    let url: URL
    private let label: String
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var pending: Value?
    private var scheduled: DispatchWorkItem?
    private let lock = NSLock()

    init(url: URL, label: String, delay: TimeInterval = 0.25) {
        self.url = url
        self.label = label
        self.delay = delay
        self.queue = DispatchQueue(label: "com.mhadikz.Paperclip.store.\(label)", qos: .utility)
    }

    // MARK: - Load

    func load() -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let value = try Self.decoder().decode(Value.self, from: data)
            backupOnce(data)
            return value
        } catch {
            quarantine(error: error)
            return nil
        }
    }

    // MARK: - Save

    func scheduleSave(_ value: Value) {
        lock.lock()
        pending = value
        scheduled?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.writePending() }
        scheduled = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Writes immediately on the calling thread. Safe to call from `applicationWillTerminate`.
    func flush() {
        lock.lock()
        scheduled?.cancel()
        scheduled = nil
        lock.unlock()
        queue.sync { self.writePending() }
    }

    private func writePending() {
        lock.lock()
        guard let value = pending else { lock.unlock(); return }
        pending = nil
        scheduled = nil
        lock.unlock()
        do {
            let data = try Self.encoder().encode(value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            AppLogger.error("Failed to save \(label): \(error.localizedDescription)", logger: AppLogger.persistence)
        }
    }

    // MARK: - Safety

    private func quarantine(error: Error) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = url.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: target)
        AppLogger.error("Could not decode \(label); moved file aside (\(error.localizedDescription))", logger: AppLogger.persistence)
    }

    private var didBackup = false

    private func backupOnce(_ data: Data) {
        guard !didBackup else { return }
        didBackup = true
        let backup = url.appendingPathExtension("bak")
        queue.async {
            try? data.write(to: backup, options: [.atomic])
        }
    }

    // MARK: - Coding

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Where this app keeps user data: `~/Library/Application Support/Paperclip/`.
enum AppDataLocation {
    /// Folder name used by builds that shipped as "Clipboard" (up to 1.3.0 dev builds).
    static let legacyFolderName = "Clipboard"
    static let folderName = "Paperclip"

    static var rootURL: URL { resolvedRoot }

    private static let resolvedRoot: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent(folderName, isDirectory: true)
        migrateLegacyFolderIfNeeded(from: appSupport.appendingPathComponent(legacyFolderName, isDirectory: true), to: dir)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    /// Moves the old data folder to the new name once. Runs only while the new folder has no
    /// `history.json` and the old one does, so live history is never overwritten. If the new folder
    /// already exists (for example a widget snapshot was written first) the files are moved into it.
    @discardableResult
    static func migrateLegacyFolderIfNeeded(from legacy: URL, to current: URL) -> Bool {
        let fm = FileManager.default
        let history = "history.json"
        guard !fm.fileExists(atPath: current.appendingPathComponent(history).path),
              fm.fileExists(atPath: legacy.appendingPathComponent(history).path) else { return false }
        do {
            if fm.fileExists(atPath: current.path) {
                for name in try fm.contentsOfDirectory(atPath: legacy.path) {
                    let source = legacy.appendingPathComponent(name)
                    let destination = current.appendingPathComponent(name)
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                    try fm.moveItem(at: source, to: destination)
                }
                try? fm.removeItem(at: legacy)
            } else {
                try fm.moveItem(at: legacy, to: current)
            }
            AppLogger.event("Moved data folder from \(legacy.lastPathComponent) to \(current.lastPathComponent)")
            return true
        } catch {
            AppLogger.error("Could not move legacy data folder: \(error.localizedDescription)", logger: AppLogger.persistence)
            return false
        }
    }

    static var mediaURL: URL {
        let dir = rootURL.appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var historyURL: URL { rootURL.appendingPathComponent("history.json") }
    static var pinboardsURL: URL { rootURL.appendingPathComponent("pinboards.json") }
    static var aiMetadataURL: URL { rootURL.appendingPathComponent("ai-metadata.json") }

    /// Bytes used by all JSON files and media.
    static func totalByteCount() -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
