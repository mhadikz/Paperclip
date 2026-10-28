import Foundation

@MainActor
func registerRepositoryTests(_ r: TestRunner) {
    r.test("repository: duplicate insert bumps the existing clip and keeps its identity") {
        let world = TestWorld()
        let first = world.clipboard.insert(ClipItem(contentType: .text, text: "same"))
        world.clipboard.insert(ClipItem(contentType: .text, text: "other"))
        let second = world.clipboard.insert(ClipItem(contentType: .text, text: "same"))
        guard case .bumped(let bumped) = second else { throw TestFailure(message: "expected bump", file: #fileID, line: #line) }
        try expectEqual(bumped.id, first.clip.id)
        try expectEqual(world.clipboard.clips.map(\.text), ["same", "other"])
        try expectEqual(world.clipboard.clips.count, 2)
    }

    r.test("repository: trim keeps protected clips and returns removed ones") {
        let world = TestWorld()
        var ids: [UUID] = []
        for i in 0..<5 {
            ids.append(world.clipboard.insert(ClipItem(contentType: .text, text: "clip \(i)")).clip.id)
        }
        let removed = world.clipboard.trim(limit: 2, keepForever: [ids[0]])
        try expectEqual(Set(removed.map(\.id)), Set([ids[1], ids[2]]))
        try expectEqual(world.clipboard.clips.map(\.id), [ids[4], ids[3], ids[0]])
    }

    r.test("repository: delete removes media sidecars") {
        let world = TestWorld()
        let id = UUID()
        let png = world.media.saveImageData(TestImages.png(), id: id)!
        _ = world.media.saveData(Data("rtf".utf8), fileName: "\(id).rtf")
        world.clipboard.insert(ClipItem(id: id, contentType: .image, mediaFileName: png, richTextFileName: "\(id).rtf"))
        world.clipboard.delete(ids: [id])
        try expect(!world.media.exists(png), "png removed")
        try expect(!world.media.exists("\(id).rtf"), "rtf removed")
        try expect(world.clipboard.clips.isEmpty, "clip gone")
    }

    r.test("repository: deleteAll keeps pinned, bumpToTop reorders") {
        let world = TestWorld()
        let a = world.clipboard.insert(ClipItem(contentType: .text, text: "a")).clip
        let b = world.clipboard.insert(ClipItem(contentType: .text, text: "b")).clip
        world.clipboard.bumpToTop(id: a.id)
        try expectEqual(world.clipboard.clips.map(\.id), [a.id, b.id])
        world.clipboard.deleteAll(keeping: [b.id])
        try expectEqual(world.clipboard.clips.map(\.id), [b.id])
    }

    r.test("repository: changes survive flush and reload") {
        let world = TestWorld()
        let clip = world.clipboard.insert(ClipItem(contentType: .link, text: "https://example.com")).clip
        let board = world.pinboards.create(name: "Links", colorHex: "#FFC300")
        world.pinboards.pin(clipID: clip.id, to: board.id)
        world.aiMemory.upsert(AIMemoryMetadata(clipID: clip.id, status: .completed, isFavorite: true))
        world.clipboard.flush(); world.pinboards.flush(); world.aiMemory.flush()

        let reloadedClips = ClipboardRepository(persistence: ClipPersistence(rootURL: world.root), mediaStore: world.media, publishSnapshot: { _, _ in })
        let reloadedBoards = PinboardRepository(persistence: ClipPersistence(rootURL: world.root))
        let reloadedMeta = AIMemoryRepository(store: AIMetadataStore(url: world.root.appendingPathComponent("ai-metadata.json")))
        try expectEqual(reloadedClips.clips.map(\.id), [clip.id])
        try expectEqual(reloadedClips.clips.first?.text, clip.text)
        try expectEqual(reloadedClips.clips.first?.contentType, .link)
        try expectEqual(reloadedBoards.pinboards.first?.clipIDs, [clip.id])
        try expectEqual(reloadedMeta.favoriteIDs(), [clip.id])
    }

    r.test("pinboards: unpinEverywhere and prune") {
        let world = TestWorld()
        let id = UUID()
        let b1 = world.pinboards.create(name: "A", colorHex: "#FFC300")
        let b2 = world.pinboards.create(name: "B", colorHex: "#FFC300")
        world.pinboards.pin(clipID: id, to: b1.id)
        world.pinboards.pin(clipID: id, to: b2.id)
        try expect(world.pinboards.isPinned(id), "pinned")
        world.pinboards.unpinEverywhere(clipIDs: [id])
        try expect(!world.pinboards.isPinned(id), "unpinned everywhere")
        world.aiMemory.upsert(AIMemoryMetadata(clipID: id))
        world.aiMemory.prune(keeping: [])
        try expect(world.aiMemory.metadata.isEmpty, "pruned")
    }

    r.test("paste stack: FIFO without duplicates") {
        let stack = PasteStackStore()
        let a = UUID(), b = UUID()
        stack.push(a); stack.push(b); stack.push(a)
        try expectEqual(stack.stack, [a, b])
        try expectEqual(stack.popNext(), a)
        stack.remove(b)
        try expect(stack.stack.isEmpty, "empty")
    }
}
