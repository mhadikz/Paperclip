import Foundation

@MainActor
func registerModelTests(_ r: TestRunner) {
    r.test("ClipItem: infers links only for real http(s) URLs") {
        try expectEqual(ClipItem.inferType(from: "https://example.com/path"), .link)
        try expectEqual(ClipItem.inferType(from: "  http://x.y  "), .link)
        try expectEqual(ClipItem.inferType(from: "https://"), .text)
        try expectEqual(ClipItem.inferType(from: "see https://example.com now"), .text)
        try expectEqual(ClipItem.inferType(from: "ftp://host/file"), .text)
    }

    r.test("ClipItem: decodes v1 history and v1.2 history") {
        let decoder = JSONFileStore<[ClipItem]>.decoder()
        let v1 = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"https://a.b","createdAt":"2026-01-01T00:00:00Z"}]"#
        let legacy = try decoder.decode([ClipItem].self, from: Data(v1.utf8))
        try expectEqual(legacy[0].contentType, .link, "legacy text infers link")
        try expectEqual(legacy[0].filePaths, [])

        let v12 = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","contentType":"image","createdAt":"2026-01-01T00:00:00Z","mediaFileName":"x.png","filePaths":[]}]"#
        let image = try decoder.decode([ClipItem].self, from: Data(v12.utf8))
        try expectEqual(image[0].contentType, .image)
        try expect(image[0].contentHash == nil && image[0].richTextFileName == nil, "new fields default to nil")
        try expectEqual(image[0].duplicateKey, "image:x.png", "falls back to file name without a hash")
    }

    r.test("ClipItem: round-trips through the encoder") {
        let clip = ClipItem(contentType: .text, text: "hello", title: "t", createdAt: Date(timeIntervalSince1970: 1_800_000_000), sourceBundleID: "b", sourceAppName: "a", richTextFileName: "r.rtf", contentHash: "abc", mediaByteCount: 12)
        let data = try JSONFileStore<[ClipItem]>.encoder().encode([clip])
        let back = try JSONFileStore<[ClipItem]>.decoder().decode([ClipItem].self, from: data)
        try expectEqual(back[0], clip)
    }

    r.test("ClipItem: preview collapses whitespace and truncates") {
        let clip = ClipItem(contentType: .text, text: "  line one\n\n\tline   two  " + String(repeating: "x", count: 200))
        try expect(clip.preview.hasPrefix("line one line two"), "collapsed: \(clip.preview)")
        try expect(clip.preview.count <= 80, "bounded")
        try expect(clip.preview.hasSuffix("…"), "ellipsis")
        try expectEqual(ClipItem(contentType: .file, filePaths: ["/a/b.txt", "/a/c.txt"]).preview, "2 files")
        try expectEqual(ClipItem(contentType: .file, filePaths: ["/a/b.txt"]).preview, "b.txt")
    }

    r.test("ClipItem: card excerpt is bounded by lines and characters") {
        let many = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let excerpt = ClipItem(contentType: .text, text: many).cardExcerpt
        try expectEqual(excerpt.split(separator: "\n").count, 8)
        try expect(excerpt.hasSuffix("…"), "truncated marker")
        let long = ClipItem(contentType: .text, text: String(repeating: "a", count: 5000)).cardExcerpt
        try expect(long.count <= 481, "character bound")
        try expectEqual(ClipItem(contentType: .text, text: "short").cardExcerpt, "short")
    }

    r.test("ClipItem: counts and url") {
        let clip = ClipItem(contentType: .text, text: "a\nb\nc")
        try expectEqual(clip.lineCount, 3)
        try expectEqual(clip.characterCount, 5)
        try expect(ClipItem(contentType: .link, text: " https://example.com ").url?.host == "example.com", "url parsed")
        try expect(ClipItem(contentType: .text, text: "https://example.com").url == nil, "only links expose url")
    }

    r.test("HotKeySpec: defaults, validation, display, codable") {
        try expectEqual(HotKeySpec.default.displayString, "⇧⌘V")
        try expect(HotKeySpec.default.isValid, "default valid")
        try expect(!HotKeySpec(keyCode: 9, modifiers: [.shift], keyLabel: "v").isValid, "shift alone is typing")
        try expect(HotKeySpec(keyCode: 122, modifiers: [], keyLabel: nil).isValid, "F1 alone is fine")
        try expectEqual(HotKeySpec(keyCode: 49, modifiers: [.control, .option], keyLabel: " ").displayString, "⌃⌥Space")
        try expectEqual(HotKeySpec(keyCode: 126, modifiers: [.command], keyLabel: nil).displayString, "⌘↑")
        let data = try JSONEncoder().encode(HotKeySpec.default)
        try expectEqual(try JSONDecoder().decode(HotKeySpec.self, from: data), HotKeySpec.default)
    }

    r.test("AIMemoryMetadata: tags normalize and metadata never stores content") {
        let tags = AIMemoryMetadata.normalizeTags(["SQL", "sql", "#Docker", "", "A", "B", "C", "D", "E", "F", "G", "H", "I"])
        try expect(tags.count <= 8, "max 8 tags")
        try expectEqual(Set(tags.map { $0.lowercased() }).count, tags.count, "deduped")
        try expectEqual(tags[1], "Docker", "hash stripped")

        let clip = ClipItem(contentType: .text, text: "super secret body that must not be duplicated")
        let meta = AIMemoryMetadata(clipID: clip.id, status: .completed, tags: ["Test"], summary: "Short summary")
        let encoded = String(data: try JSONEncoder().encode(meta), encoding: .utf8) ?? ""
        try expect(!encoded.contains("super secret body"), "metadata must not contain raw clipboard content")
    }

    r.test("Pinboard: palette and defaults") {
        try expectEqual(Pinboard(name: "x").colorHex, Pinboard.defaultColorHex)
        try expect(Pinboard.colorPalette.count >= 6, "enough distinct colors")
        try expect(!Pinboard.colorPalette.contains("#FFFFFF"), "white chips would vanish in Light")
    }

    r.test("TimelineGrouping: buckets by day") {
        let now = Date()
        let today = ClipItem(contentType: .text, text: "a", createdAt: now)
        let yesterday = ClipItem(contentType: .text, text: "b", createdAt: Calendar.current.date(byAdding: .day, value: -1, to: now)!)
        let old = ClipItem(contentType: .text, text: "c", createdAt: now.addingTimeInterval(-40 * 86_400))
        let groups = TimelineGrouping.group([today, yesterday, old])
        try expectEqual(groups.map(\.title), ["Today", "Yesterday", "Earlier"])
    }
}
