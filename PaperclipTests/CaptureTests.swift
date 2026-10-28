import Foundation

@MainActor
func registerCaptureTests(_ r: TestRunner) {
    r.test("capture: stores text with source app and infers links") {
        let world = TestWorld()
        world.copyText("https://example.com/docs", app: "com.apple.Safari")
        world.copyText("plain words")
        try expectEqual(world.clipboard.clips.map(\.contentType), [.text, .link])
        try expectEqual(world.clipboard.clips.last?.sourceBundleID, "com.apple.Safari")
        try expect(world.aiMemory.metadata(for: world.clipboard.clips[0].id) != nil, "heuristic metadata seeded immediately")
    }

    r.test("capture: respects pause and ignored apps") {
        let world = TestWorld()
        world.settings.recordHistory = false
        world.copyText("while paused")
        world.settings.recordHistory = true
        world.settings.ignored = ["com.1password.app"]
        world.copyText("from password manager", app: "com.1password.app")
        try expect(world.clipboard.clips.isEmpty, "nothing stored")
        world.copyText("allowed")
        try expectEqual(world.clipboard.clips.count, 1)
    }

    r.test("capture: sensitive policies") {
        let world = TestWorld()
        let secret = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        world.copyText(secret)
        try expect(world.clipboard.clips.isEmpty, "neverStore skips")

        world.settings.sensitiveStoragePolicy = .storeEncryptedPlaceholder
        world.copyText(secret)
        try expectEqual(world.clipboard.clips.first?.text, "[redacted secret]")
        try expect(world.clipboard.clips.first?.title == "Redacted secret", "titled")

        world.settings.sensitiveStoragePolicy = .storeWithoutAI
        world.copyText("AKIAIOSFODNN7EXAMPLE")
        let stored = world.clipboard.clips.first!
        try expectEqual(stored.text, "AKIAIOSFODNN7EXAMPLE")
        try expectEqual(world.aiMemory.metadata(for: stored.id)?.category, .credentials, "heuristics mark it, model never sees it")
    }

    r.asyncTest("capture: sensitive clips are never queued for the model") {
        let world = TestWorld()
        world.settings.sensitiveStoragePolicy = .storeWithoutAI
        world.copyText("password=hunter2hunter2")
        world.copyText("ordinary text")
        await world.settle()
        let queued = await world.queue.enqueued
        try expectEqual(queued, [world.clipboard.clips[0].id], "only the ordinary clip is queued")
    }

    r.test("capture: repeated copy bumps and keeps pins, favorites, metadata") {
        let world = TestWorld()
        world.copyText("keep me")
        let original = world.clipboard.clips[0]
        let board = world.pinboards.create(name: "Pins", colorHex: "#FFC300")
        world.pinboards.pin(clipID: original.id, to: board.id)
        world.aiMemory.upsert(AIMemoryMetadata(clipID: original.id, status: .completed, tags: ["Custom"], isFavorite: true))
        world.copyText("something else")
        world.copyText("keep me", app: "com.other.app")
        try expectEqual(world.clipboard.clips.count, 2)
        let bumped = world.clipboard.clips[0]
        try expectEqual(bumped.id, original.id, "identity kept")
        try expectEqual(bumped.sourceBundleID, "com.other.app", "source updated")
        try expect(world.pinboards.isPinned(original.id), "still pinned")
        try expectEqual(world.aiMemory.metadata(for: original.id)?.tags, ["Custom"], "metadata kept")
    }

    r.test("capture: rich text sidecar is stored and bounded") {
        let world = TestWorld()
        world.copyText("bold text", rtf: Data("{\\rtf1 bold}".utf8))
        let clip = world.clipboard.clips[0]
        try expect(clip.richTextFileName != nil, "sidecar recorded")
        try expect(world.media.exists(clip.richTextFileName), "sidecar file exists")

        world.settings.captureRichText = false
        world.copyText("no sidecar", rtf: Data("{\\rtf1}".utf8))
        try expect(world.clipboard.clips[0].richTextFileName == nil, "setting off → no sidecar")

        world.settings.captureRichText = true
        let huge = Data(repeating: 0x41, count: CaptureClipUseCase.maxRichTextBytes + 1)
        world.copyText("too big", rtf: huge)
        try expect(world.clipboard.clips[0].richTextFileName == nil, "oversized RTF is dropped, text kept")
    }

    r.test("capture: oversized text and whitespace-only are skipped") {
        let world = TestWorld()
        world.copyText("   \n\t ")
        world.copyText(String(repeating: "x", count: CaptureClipUseCase.maxTextCharacters + 1))
        try expect(world.clipboard.clips.isEmpty, "nothing stored")
    }

    r.asyncTest("capture: images dedupe by content hash and get OCR text") {
        let world = TestWorld(ocr: "Receipt total 42")
        let png = TestImages.png(red: 10)
        world.capture.execute(content: .image(png), bundleID: "com.apple.screencapture", appName: "Screenshot")
        await world.settle()
        let clip = world.clipboard.clips[0]
        try expectEqual(clip.contentType, .image)
        try expectEqual(clip.contentHash, ContentHasher.sha256(png))
        try expectEqual(clip.mediaByteCount, png.count)
        try expectEqual(clip.searchableText, "Receipt total 42", "OCR applied")
        try expect(world.media.exists(clip.mediaFileName), "png stored")

        world.capture.execute(content: .text("between", richText: nil), bundleID: nil, appName: nil)
        world.capture.execute(content: .image(png), bundleID: nil, appName: nil)
        try expectEqual(world.clipboard.clips.count, 2, "same image collapses")
        try expectEqual(world.clipboard.clips[0].id, clip.id, "bumped to top")

        world.capture.execute(content: .image(TestImages.png(red: 250)), bundleID: nil, appName: nil)
        try expectEqual(world.clipboard.clips.count, 3, "different image is new")
    }

    r.test("capture: files") {
        let world = TestWorld()
        world.capture.execute(content: .files([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]), bundleID: "com.apple.finder", appName: "Finder")
        let clip = world.clipboard.clips[0]
        try expectEqual(clip.contentType, .file)
        try expectEqual(clip.filePaths, ["/tmp/a.txt", "/tmp/b.txt"])
        try expectEqual(clip.preview, "2 files")
    }

    r.test("capture: trims beyond the remember limit and drops their metadata") {
        let world = TestWorld()
        world.settings.rememberCount = 2
        world.copyText("one"); world.copyText("two"); world.copyText("three")
        try expectEqual(world.clipboard.clips.map(\.text), ["three", "two"])
        try expectEqual(world.aiMemory.metadata.count, 2, "metadata for trimmed clip removed")

        let keep = world.clipboard.clips[1]
        world.aiMemory.upsert(AIMemoryMetadata(clipID: keep.id, isFavorite: true))
        world.copyText("four"); world.copyText("five")
        try expect(world.clipboard.clips.contains { $0.id == keep.id }, "favorites survive trimming")
    }

    r.test("monitor: prefers text over image unless the text is just a URL") {
        try expect(ClipboardMonitor.prefersImage(over: nil), "no text → image")
        try expect(ClipboardMonitor.prefersImage(over: "   "), "blank → image")
        try expect(ClipboardMonitor.prefersImage(over: "https://example.com/pic.png"), "url + image → image")
        try expect(!ClipboardMonitor.prefersImage(over: "Q1\t100\nQ2\t200"), "spreadsheet cells → text")
    }
}
