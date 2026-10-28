import Foundation

@MainActor
func registerAITests(_ r: TestRunner) {
    r.test("enqueue policy: shouldProcess rules") {
        var s = StubSettings().snapshot
        try expect(EnqueueAIProcessingUseCase.shouldProcess(text: "hello", settings: s), "normal text")
        try expect(EnqueueAIProcessingUseCase.shouldProcess(text: nil, settings: s), "images without OCR still get heuristics")
        try expect(!EnqueueAIProcessingUseCase.shouldProcess(text: String(repeating: "a", count: 13_000), settings: s), "too long")
        try expect(!EnqueueAIProcessingUseCase.shouldProcess(text: "password=abcdefghijk", settings: s), "sensitive")
        s.processSensitiveContent = true
        try expect(EnqueueAIProcessingUseCase.shouldProcess(text: "password=abcdefghijk", settings: s), "sensitive allowed by setting")
        s.aiFeaturesEnabled = false
        try expect(!EnqueueAIProcessingUseCase.shouldProcess(text: "hello", settings: s), "AI off")
    }

    r.asyncTest("enqueue: seeds heuristics and queues; backfill picks pending/missing only") {
        let world = TestWorld()
        let a = world.clipboard.insert(ClipItem(contentType: .text, text: "SELECT 1 FROM t")).clip
        let b = world.clipboard.insert(ClipItem(contentType: .text, text: "done")).clip
        let c = world.clipboard.insert(ClipItem(contentType: .text, text: "stuck")).clip
        world.enqueueAI.execute(clip: a)
        try expectEqual(world.aiMemory.metadata(for: a.id)?.category, .sql, "seeded")
        try expectEqual(world.aiMemory.metadata(for: a.id)?.status, .pending)
        world.aiMemory.upsert(AIMemoryMetadata(clipID: b.id, status: .completed))
        world.aiMemory.upsert(AIMemoryMetadata(clipID: c.id, status: .processing))
        world.enqueueAI.backfill(from: [a, b, c])
        await world.settle()
        let queued = await world.queue.enqueued
        try expectEqual(Set(queued), Set([a.id, c.id]), "a (pending) and c (interrupted), not b")
    }

    r.asyncTest("processing queue: ids wait for a handler instead of being dropped") {
        let queue = AIProcessingQueue()
        let id = UUID()
        await queue.enqueue(id)
        try? await Task.sleep(nanoseconds: 50_000_000)
        try expectEqual(await queue.pendingCount(), 1, "still pending")
        let processed = Processed()
        await queue.setHandler { clipID in processed.ids.append(clipID) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        try expectEqual(processed.ids, [id])
        try expectEqual(await queue.pendingCount(), 0)
        await queue.enqueueMany([id, id])
        try? await Task.sleep(nanoseconds: 200_000_000)
        try expectEqual(processed.ids.count, 2, "duplicate ids in one batch collapse")
    }

    r.asyncTest("process: completes metadata via injected service and keeps favorites") {
        let world = TestWorld()
        let clip = world.clipboard.insert(ClipItem(contentType: .text, text: String(repeating: "A thoughtful paragraph. ", count: 12))).clip
        world.aiMemory.upsert(AIMemoryMetadata(clipID: clip.id, status: .pending, isFavorite: true))
        world.ai.providerID = "apple.foundationModels"
        world.ai.classification = AIClassificationResult(category: .article, tags: ["Essay"], summary: nil, language: "en", codeLanguage: nil, entities: [], importance: 0.7)
        await world.processAI.execute(clipID: clip.id)
        let meta = world.aiMemory.metadata(for: clip.id)!
        try expectEqual(meta.status, .completed)
        try expectEqual(meta.category, .article)
        try expectEqual(meta.tags, ["Essay"])
        try expectEqual(meta.summary, "summary", "long text → summarize call")
        try expectEqual(meta.modelIdentifier, "apple.foundationModels")
        try expectEqual(meta.promptVersion, AIPromptVersion.current)
        try expect(meta.isFavorite, "favorite preserved across processing")
        try expectEqual(world.ai.summarizeCalls, 1)
    }

    r.asyncTest("process: sensitive content is skipped and deleted clips are ignored") {
        let world = TestWorld()
        let secret = world.clipboard.insert(ClipItem(contentType: .text, text: "password=hunter2hunter2")).clip
        await world.processAI.execute(clipID: secret.id)
        try expectEqual(world.aiMemory.metadata(for: secret.id)?.status, .skipped)
        try expectEqual(world.ai.classifyCalls, 0, "model never called")
        await world.processAI.execute(clipID: UUID())
        try expectEqual(world.aiMemory.metadata.count, 1, "unknown id adds nothing")
    }

    r.asyncTest("process: respects AI off and tag/summary toggles") {
        let world = TestWorld()
        let clip = world.clipboard.insert(ClipItem(contentType: .text, text: "hello there")).clip
        world.settings.aiFeaturesEnabled = false
        await world.processAI.execute(clipID: clip.id)
        try expect(world.aiMemory.metadata(for: clip.id) == nil, "nothing when AI off")
        world.settings.aiFeaturesEnabled = true
        world.settings.automaticTags = false
        world.settings.automaticSummaries = false
        world.ai.classification = AIClassificationResult(category: .plainText, tags: ["Ignored"], summary: "s", language: nil, codeLanguage: nil, entities: [], importance: 0.5)
        await world.processAI.execute(clipID: clip.id)
        try expectEqual(world.aiMemory.metadata(for: clip.id)?.tags, [], "tags off")
        try expectEqual(world.aiMemory.metadata(for: clip.id)?.summary, "s", "classification summary kept, no summarize call")
        try expectEqual(world.ai.summarizeCalls, 0)
    }

    r.asyncTest("AIService: heuristics are definitive for structured content") {
        let service = AIService(heuristic: HeuristicLanguageModelProvider(), apple: UnavailableProvider())
        let sql = ClipItem(contentType: .text, text: "SELECT * FROM t")
        try expectEqual(await service.classify(clip: sql, useAI: true).category, .sql)
        try expectEqual(await service.activeProviderID(useAI: true), "heuristic", "falls back when Apple is unavailable")
        let prose = ClipItem(contentType: .text, text: String(repeating: "prose ", count: 60))
        let summary = await service.summarize(clip: prose, useAI: true)
        try expect(summary?.hasSuffix("…") == true, "fallback summary")
        try expectEqual(try await service.rewrite(text: "{\"a\":1}", style: .formatJSON, useAI: false), "{\n  \"a\" : 1\n}")
    }

    r.test("update memory: favorites and tags") {
        let world = TestWorld()
        let update = UpdateAIMemoryUseCase(aiMemory: world.aiMemory)
        let id = UUID()
        update.toggleFavorite(clipID: id)
        try expectEqual(world.aiMemory.favoriteIDs(), [id])
        update.updateTags(clipID: id, tags: ["#a", "a", "b"])
        try expectEqual(world.aiMemory.metadata(for: id)?.tags, ["a", "b"])
        update.clearAll()
        try expect(world.aiMemory.metadata.isEmpty, "cleared")
    }
}

final class Processed: @unchecked Sendable {
    var ids: [UUID] = []
}

struct UnavailableProvider: LanguageModelProvider {
    let id = "unavailable"
    let displayName = "Unavailable"
    var availability: AIProviderAvailability { .unavailable(reason: "test") }
    func classify(text: String, contentType: ClipContentType, sourceApp: String?) async throws -> AIClassificationResult { throw AIProviderError.unavailable("test") }
    func summarize(text: String) async throws -> String { throw AIProviderError.unavailable("test") }
    func generateTags(text: String, contentType: ClipContentType) async throws -> [String] { throw AIProviderError.unavailable("test") }
    func rewrite(text: String, style: SmartRewriteStyle) async throws -> String { throw AIProviderError.unavailable("test") }
    func interpretQuery(_ query: String) async throws -> AIQueryInterpretation { throw AIProviderError.unavailable("test") }
}
