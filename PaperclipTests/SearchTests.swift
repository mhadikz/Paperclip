import Foundation

@MainActor
func registerSearchTests(_ r: TestRunner) {
    r.test("query interpreter: category, time, app, keywords") {
        let q = QueryInterpreter.heuristic("Find the SQL query I copied yesterday from DataGrip")
        try expectEqual(q.category, .sql)
        try expectEqual(q.relativeTime, .yesterday)
        try expectEqual(q.sourceAppHint, "DataGrip")
        try expect(!q.keywords.contains("find") && !q.keywords.contains("copied"), "stop words removed")
        try expectEqual(QueryInterpreter.heuristic("screenshot from safari this week").category, .image)
        try expectEqual(QueryInterpreter.heuristic("screenshot from safari this week").relativeTime, .lastWeek)
    }

    r.test("hybrid search: cues rank the right clip first") {
        let sql = ClipItem(contentType: .text, text: "SELECT * FROM payments;", createdAt: Date())
        let url = ClipItem(contentType: .link, text: "https://github.com/org/auth-service", createdAt: Date())
        var meta: [UUID: AIMemoryMetadata] = [:]
        meta[sql.id] = AIMemoryMetadata(clipID: sql.id, status: .completed, category: .sql, tags: ["SQL", "Payments"], summary: "Payments SQL query")
        meta[url.id] = AIMemoryMetadata(clipID: url.id, status: .completed, category: .url, tags: ["GitHub", "Authentication"], summary: "Auth service repo")

        let results = HybridSearchService.search(
            query: "GitHub authentication link",
            clips: [sql, url],
            metadata: meta,
            interpretation: QueryInterpreter.heuristic("GitHub authentication link")
        )
        try expectEqual(results.first?.clip.id, url.id, "github link first")
        try expect(!results.contains { $0.clip.id == sql.id }, "unrelated clip excluded")
    }

    r.test("hybrid search: exact phrase beats scattered keywords; empty query lists recent") {
        let exact = ClipItem(contentType: .text, text: "deploy to staging now", createdAt: Date().addingTimeInterval(-3600))
        let scattered = ClipItem(contentType: .text, text: "staging is where we deploy, now and then", createdAt: Date())
        let results = HybridSearchService.search(query: "deploy to staging", clips: [scattered, exact], metadata: [:], interpretation: nil)
        try expectEqual(results.first?.clip.id, exact.id)
        let recent = HybridSearchService.search(query: "  ", clips: [scattered, exact], metadata: [:], interpretation: nil)
        try expectEqual(recent.map(\.clip.id), [scattered.id, exact.id])
    }

    r.test("hybrid search: relative time filters") {
        let old = ClipItem(contentType: .text, text: "docker compose up", createdAt: Date().addingTimeInterval(-10 * 86_400))
        let fresh = ClipItem(contentType: .text, text: "docker compose down", createdAt: Date())
        let results = HybridSearchService.search(query: "docker command from today", clips: [old, fresh], metadata: [:], interpretation: nil)
        try expectEqual(results.map(\.clip.id), [fresh.id])
    }

    r.test("hybrid search: related memories share tags/category") {
        let a = ClipItem(contentType: .text, text: "kubectl get pods")
        let b = ClipItem(contentType: .text, text: "kubectl describe pod web")
        let c = ClipItem(contentType: .text, text: "Lunch at noon")
        var meta: [UUID: AIMemoryMetadata] = [:]
        meta[a.id] = AIMemoryMetadata(clipID: a.id, category: .shell, tags: ["Kubernetes", "Shell"])
        meta[b.id] = AIMemoryMetadata(clipID: b.id, category: .shell, tags: ["Kubernetes", "Shell"])
        meta[c.id] = AIMemoryMetadata(clipID: c.id, category: .plainText, tags: ["Text"])
        let related = HybridSearchService.related(to: a, metadata: meta[a.id], allClips: [a, b, c], allMetadata: meta)
        try expectEqual(related.map(\.id), [b.id])
    }

    r.asyncTest("search use case: favorites mode and AI refinement gating") {
        let world = TestWorld()
        let fav = ClipItem(contentType: .text, text: "favorite note about docker")
        let plain = ClipItem(contentType: .text, text: "plain note about docker")
        world.aiMemory.upsert(AIMemoryMetadata(clipID: fav.id, isFavorite: true))
        let input = SearchMemoryUseCase.Input(query: "docker", mode: .favorites, clips: [fav, plain], metadata: world.aiMemory.metadata, pinnedIDs: [])
        let quick = world.searchMemory.quickSearch(input)
        try expectEqual(quick.map(\.clip.id), [fav.id])

        var clipboardMode = input
        clipboardMode.mode = .clipboard
        try expect(world.searchMemory.quickSearch(clipboardMode).isEmpty, "clipboard mode never uses memory search")

        try expect(!world.searchMemory.shouldRefineWithAI(query: "docker"), "single keyword: no model call")
        try expect(world.searchMemory.shouldRefineWithAI(query: "docker command from last week"), "natural language: refine")
        world.settings.semanticSearch = false
        try expect(!world.searchMemory.shouldRefineWithAI(query: "docker command from last week"), "respects setting")

        let refined = await world.searchMemory.refinedSearch(input)
        try expectEqual(refined.map(\.clip.id), [fav.id])
    }
}
