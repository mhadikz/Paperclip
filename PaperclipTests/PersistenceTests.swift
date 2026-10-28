import Foundation
import AppKit

@MainActor
func registerPersistenceTests(_ r: TestRunner) {
    r.test("JSONFileStore: coalesces saves and flush writes the latest value") {
        let dir = TestTemp.directory("store")
        let store = JSONFileStore<[String]>(url: dir.appendingPathComponent("v.json"), label: "test", delay: 5)
        store.scheduleSave(["one"])
        store.scheduleSave(["one", "two"])
        try expect(!FileManager.default.fileExists(atPath: store.url.path), "nothing written before the delay")
        store.flush()
        try expectEqual(store.load() ?? [], ["one", "two"])
    }

    r.test("JSONFileStore: corrupt file is quarantined instead of overwritten") {
        let dir = TestTemp.directory("corrupt")
        let url = dir.appendingPathComponent("history.json")
        try Data("{not json".utf8).write(to: url)
        let store = JSONFileStore<[ClipItem]>(url: url, label: "history")
        try expect(store.load() == nil, "load returns nil")
        try expect(!FileManager.default.fileExists(atPath: url.path), "original moved aside")
        let moved = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("corrupt-") }
        try expectEqual(moved.count, 1, "quarantined copy exists")
    }

    r.test("AppDataLocation: legacy Clipboard folder is moved to Paperclip once, never over existing data") {
        let base = TestTemp.directory("migrate")
        let legacy = base.appendingPathComponent("Clipboard", isDirectory: true)
        let current = base.appendingPathComponent("Paperclip", isDirectory: true)

        // No history.json → an unrelated "Clipboard" folder is left alone.
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try expect(!AppDataLocation.migrateLegacyFolderIfNeeded(from: legacy, to: current), "ignores folders without history")
        try expect(FileManager.default.fileExists(atPath: legacy.path), "untouched")

        try Data("[]".utf8).write(to: legacy.appendingPathComponent("history.json"))
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try expect(AppDataLocation.migrateLegacyFolderIfNeeded(from: legacy, to: current), "moves once")
        try expect(!FileManager.default.fileExists(atPath: legacy.path), "old folder gone")
        try expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("history.json").path), "history moved")
        try expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("Media").path), "media moved")

        // A new folder that only holds a widget snapshot is merged into, not treated as live data.
        let base2 = TestTemp.directory("migrate-merge")
        let legacy2 = base2.appendingPathComponent("Clipboard", isDirectory: true)
        let current2 = base2.appendingPathComponent("Paperclip", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current2, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: legacy2.appendingPathComponent("history.json"))
        try Data("{}".utf8).write(to: current2.appendingPathComponent("widget-snapshot.json"))
        try expect(AppDataLocation.migrateLegacyFolderIfNeeded(from: legacy2, to: current2), "merges into existing folder")
        try expect(FileManager.default.fileExists(atPath: current2.appendingPathComponent("history.json").path), "history merged")
        try expect(!FileManager.default.fileExists(atPath: legacy2.path), "old folder removed after merge")

        // A second legacy folder appearing later never replaces the live one.
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("[{}]".utf8).write(to: legacy.appendingPathComponent("history.json"))
        try expect(!AppDataLocation.migrateLegacyFolderIfNeeded(from: legacy, to: current), "existing data wins")
        try expectEqual(String(decoding: try Data(contentsOf: current.appendingPathComponent("history.json")), as: UTF8.self), "[]")
    }

    r.test("ClipPersistence + AIMetadataStore: round trip") {
        let dir = TestTemp.directory("persist")
        let persistence = ClipPersistence(rootURL: dir)
        let clip = ClipItem(contentType: .text, text: "hello", title: "t", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        persistence.saveClips([clip])
        persistence.savePinboards([Pinboard(name: "Work", clipIDs: [clip.id])])
        persistence.flushClips()
        persistence.flushPinboards()
        try expectEqual(ClipPersistence(rootURL: dir).loadClips(), [clip])
        try expectEqual(ClipPersistence(rootURL: dir).loadPinboards().first?.name, "Work")

        let metaStore = AIMetadataStore(url: dir.appendingPathComponent("ai.json"))
        metaStore.save([clip.id: AIMemoryMetadata(clipID: clip.id, status: .completed, tags: ["A"])])
        metaStore.flush()
        try expectEqual(AIMetadataStore(url: dir.appendingPathComponent("ai.json")).load()[clip.id]?.tags, ["A"])
    }

    r.test("MediaStore: save, size, delete") {
        let dir = TestTemp.directory("media")
        let store = MediaStore(rootURL: dir)
        let id = UUID()
        let name = store.saveImageData(TestImages.png(), id: id)
        try expectEqual(name, "\(id.uuidString).png")
        try expect(store.fileSize(fileName: name) > 0, "size reported")
        try expect(store.totalByteCount() > 0, "total reported")
        store.delete(fileName: name)
        try expectEqual(store.fileSize(fileName: name), 0)
        try expect(store.saveData(Data("x".utf8), fileName: "a.rtf"), "generic save")
        try expectEqual(store.loadData(fileName: "a.rtf"), Data("x".utf8))
    }

    r.test("ImageTranscoder: converts TIFF to PNG") {
        let png = TestImages.png()
        let image = NSImage(data: png)!
        let tiff = image.tiffRepresentation!
        let converted = ImageTranscoder.pngData(from: tiff)
        try expect(converted != nil, "converted")
        try expect(converted!.starts(with: [0x89, 0x50, 0x4E, 0x47]), "png magic")
    }
}
