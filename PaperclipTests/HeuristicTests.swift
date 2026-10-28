import Foundation

@MainActor
func registerHeuristicTests(_ r: TestRunner) {
    func classify(_ text: String) -> AIClassificationResult {
        HeuristicClassifier.classify(clip: ClipItem(contentType: ClipItem.inferType(from: text), text: text))
    }

    r.test("heuristic: SQL") {
        let result = classify("SELECT * FROM users WHERE id = 1;")
        try expectEqual(result.category, .sql)
        try expect(result.tags.contains("SQL"), "SQL tag")
        try expectEqual(result.codeLanguage, "sql")
    }

    r.test("heuristic: shell with tool tags") {
        let result = classify("docker system prune -af")
        try expectEqual(result.category, .shell)
        try expect(result.tags.contains("Docker"), "Docker tag")
        try expectEqual(classify("brew install jq && brew upgrade").category, .shell)
    }

    r.test("heuristic: JSON, XML, markdown, code") {
        try expectEqual(classify("{\"a\": 1, \"b\": [1,2]}").category, .json)
        try expectEqual(classify("<?xml version=\"1.0\"?><root><a/></root>").category, .xml)
        try expectEqual(classify("# Title\n\n## Section\n- [ ] todo").category, .markdown)
        let swift = classify("import Foundation\n\nfunc greet() {\n    print(\"hi\")\n}")
        try expectEqual(swift.category, .code)
        try expectEqual(swift.codeLanguage, "swift")
    }

    r.test("heuristic: links, email, phone, plain text") {
        let url = classify("https://github.com/org/repo/pull/12")
        try expectEqual(url.category, .url)
        try expect(url.tags.contains("GitHub"), "GitHub tag")
        try expectEqual(url.entities, ["github.com"])
        try expectEqual(classify("someone@example.com").category, .email)
        try expect(classify("git@github.com:org/repo.git").category != .email, "ssh remote is not an email")
        try expectEqual(classify("+1 (415) 555-0132").category, .phoneNumber)
        try expect(classify("2026-10-26 14:30:00").category != .phoneNumber, "timestamps are not phone numbers")
        try expectEqual(classify("Just a quick note about the meeting").category, .plainText)
        try expectEqual(classify(String(repeating: "word ", count: 120)).category, .article)
    }

    r.test("heuristic: sensitive text classified as credentials") {
        let result = classify("password=supersecretvalue")
        try expectEqual(result.category, .credentials)
        try expect(result.summary?.contains("secret") == false, "summary never echoes the secret")
    }

    r.test("heuristic: images and files") {
        let image = HeuristicClassifier.classify(clip: ClipItem(contentType: .image, searchableText: "Invoice total 42"))
        try expectEqual(image.category, .image)
        try expectEqual(image.summary, "Invoice total 42")
        let files = HeuristicClassifier.classify(clip: ClipItem(contentType: .file, filePaths: ["/a/report.PDF", "/a/b.txt"]))
        try expectEqual(files.category, .file)
        try expect(files.tags.contains("PDF"), "extension tag")
        try expectEqual(files.summary, "2 files")
    }

    r.test("smart actions: contextual catalog") {
        let jsonClip = ClipItem(contentType: .text, text: "{\"a\":1}")
        let json = SmartActionCatalog.actions(for: jsonClip, metadata: AIMemoryMetadata(clipID: jsonClip.id, category: .json))
        try expect(json.contains(.formatJSON), "json → format")
        try expect(!json.contains(.unitTests), "json ≠ unit tests")
        let image = ClipItem(contentType: .image)
        try expect(SmartActionCatalog.actions(for: image, metadata: nil).isEmpty, "image without OCR has no text actions")
        let secret = ClipItem(contentType: .text, text: "x")
        try expect(SmartActionCatalog.actions(for: secret, metadata: AIMemoryMetadata(clipID: secret.id, category: .credentials)).isEmpty, "credentials get no actions")
    }

    r.asyncTest("heuristic provider: format JSON works offline, others refuse politely") {
        let provider = HeuristicLanguageModelProvider()
        try expect(provider.availability.isAvailable, "always available")
        let pretty = try await provider.rewrite(text: "{\"b\":1,\"a\":[1,2]}", style: .formatJSON)
        try expect(pretty.contains("\n"), "pretty printed")
        try await expectThrows("non-JSON should throw") { _ = try await provider.rewrite(text: "not json", style: .formatJSON) }
        try await expectThrows("model-only styles throw unsupported") { _ = try await provider.rewrite(text: "hi", style: .explainCode) }
        let result = try await provider.classify(text: "hello world", contentType: .text, sourceApp: nil)
        try expect([.plainText, .other, .article].contains(result.category), "plain-ish")
    }

    r.test("foundation models provider: parses JSON embedded in prose") {
        let fallback = HeuristicClassifier.classify(clip: ClipItem(contentType: .text, text: "hello"))
        let raw = "Sure! Here is the JSON:\n{\"category\":\"meetingNotes\",\"tags\":[\"Standup\"],\"summary\":\"Daily standup notes\",\"importance\":1.7,\"entities\":[\"Team\"]}\nThanks."
        let parsed = AppleFoundationModelsProvider.parseClassification(raw, fallback: fallback)
        try expectEqual(parsed.category, .meetingNotes)
        try expectEqual(parsed.tags, ["Standup"])
        try expectEqual(parsed.importance, 1.0, "clamped")
        let garbage = AppleFoundationModelsProvider.parseClassification("no json here", fallback: fallback)
        try expectEqual(garbage, fallback)
        let query = AppleFoundationModelsProvider.parseQuery("{\"keywords\":[\"docker\"],\"relativeTime\":\"lastWeek\",\"sourceAppHint\":\"Terminal\"}", fallback: QueryInterpreter.heuristic("x"))
        try expectEqual(query.relativeTime, .lastWeek)
        try expectEqual(query.sourceAppHint, "Terminal")
    }
}
