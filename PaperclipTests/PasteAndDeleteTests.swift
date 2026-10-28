import Foundation

@MainActor
func registerPasteAndDeleteTests(_ r: TestRunner) {
    r.test("paste: writes, ignores own change, bumps, and sends ⌘V when allowed") {
        let world = TestWorld()
        world.copyText("first")
        world.copyText("second")
        let first = world.clipboard.clips[1]
        world.pasteClip.execute(first)
        try expectEqual(world.paste.writes.count, 1)
        try expectEqual(world.paste.writes[0].clipID, first.id)
        try expectEqual(world.monitor.ignoreCount, 1, "monitor told to skip our write")
        try expectEqual(world.clipboard.clips[0].id, first.id, "bumped to top")
        try expectEqual(world.paste.keystrokes, [PasteClipUseCase.keystrokeDelay])
    }

    r.test("paste: copy-only and settings suppress the keystroke") {
        let world = TestWorld()
        world.copyText("x")
        let clip = world.clipboard.clips[0]
        world.pasteClip.execute(clip, pasteImmediately: false)
        try expect(world.paste.keystrokes.isEmpty, "copy only")
        world.settings.pasteAndEnter = false
        world.pasteClip.execute(clip)
        try expect(world.paste.keystrokes.isEmpty, "setting off")
        world.paste.canSendKeystrokes = false
        world.settings.pasteAndEnter = true
        world.pasteClip.execute(clip)
        try expect(world.paste.keystrokes.isEmpty, "no accessibility → silently copies")
        try expect(!world.pasteClip.canPasteIntoOtherApps, "reports capability")
        try expectEqual(world.pasteClip.requestAccessibilityIfNeeded(), false)
        try expectEqual(world.paste.accessibilityRequests, 1)
    }

    r.test("paste: rich text travels unless plain text requested") {
        let world = TestWorld()
        world.copyText("styled", rtf: Data("{\\rtf1 styled}".utf8))
        let clip = world.clipboard.clips[0]
        world.pasteClip.execute(clip)
        world.pasteClip.execute(clip, plainText: true)
        try expectEqual(world.paste.writes.map(\.hasRichText), [true, false])
        try expectEqual(world.paste.writes.map(\.plainText), [false, true])
    }

    r.test("paste: transformed text is not stored as history") {
        let world = TestWorld()
        world.pasteClip.executeTransformed(text: "rewritten", pasteImmediately: false)
        try expectEqual(world.paste.writes.first?.text, "rewritten")
        try expect(world.clipboard.clips.isEmpty, "not inserted")
        try expectEqual(world.monitor.ignoreCount, 1)
    }

    r.test("delete: cascades to metadata, pinboards and stack") {
        let world = TestWorld()
        world.copyText("gone"); world.copyText("stays")
        let gone = world.clipboard.clips[1]
        let board = world.pinboards.create(name: "B", colorHex: "#FFC300")
        world.pinboards.pin(clipID: gone.id, to: board.id)
        world.stack.push(gone.id)
        world.deleteClips.execute([gone])
        try expectEqual(world.clipboard.clips.map(\.text), ["stays"])
        try expect(world.aiMemory.metadata(for: gone.id) == nil, "metadata removed")
        try expect(!world.pinboards.isPinned(gone.id), "unpinned")
        try expect(world.stack.stack.isEmpty, "stack cleaned")
    }

    r.test("delete all: keeps pinned clips and their metadata") {
        let world = TestWorld()
        world.copyText("pinned"); world.copyText("loose")
        let pinned = world.clipboard.clips[1]
        let board = world.pinboards.create(name: "B", colorHex: "#FFC300")
        world.pinboards.pin(clipID: pinned.id, to: board.id)
        world.deleteClips.executeDeleteAllHistory()
        try expectEqual(world.clipboard.clips.map(\.id), [pinned.id])
        try expect(world.aiMemory.metadata(for: pinned.id) != nil, "pinned metadata kept")
        try expectEqual(world.aiMemory.metadata.count, 1)
    }

    r.test("update: rename sets and clears titles") {
        let world = TestWorld()
        world.copyText("body")
        let clip = world.clipboard.clips[0]
        let update = UpdateClipUseCase(clipboard: world.clipboard)
        update.rename(clip, title: "  My title ")
        try expectEqual(world.clipboard.clips[0].title, "My title")
        try expectEqual(world.clipboard.clips[0].preview, "My title")
        update.rename(world.clipboard.clips[0], title: "   ")
        try expect(world.clipboard.clips[0].title == nil, "cleared")
    }
}
