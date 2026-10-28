import Foundation

/// Two-phase retrieval: an instant heuristic pass, then an optional AI-refined pass for
/// natural-language queries when Foundation Models are enabled and available.
@MainActor
struct SearchMemoryUseCase {
    let settings: SettingsProviding
    let ai: AIMemoryServicing

    struct Input {
        var query: String
        var mode: HistoryNavigationMode
        var clips: [ClipItem]
        var metadata: [UUID: AIMemoryMetadata]
        var pinnedIDs: Set<UUID>
    }

    /// Synchronous keyword/cue search — safe to call on every keystroke.
    func quickSearch(_ input: Input) -> [MemorySearchResult] {
        guard input.mode != .clipboard else { return [] }
        let trimmed = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let interpretation = trimmed.isEmpty ? nil : QueryInterpreter.heuristic(trimmed)
        return HybridSearchService.search(
            query: input.query,
            clips: source(for: input),
            metadata: input.metadata,
            interpretation: interpretation
        )
    }

    /// Whether a model-refined pass is worth running for this query.
    func shouldRefineWithAI(query: String) -> Bool {
        guard settings.semanticSearch, settings.aiFeaturesEnabled, settings.useFoundationModels else { return false }
        let words = query.split(whereSeparator: \.isWhitespace)
        return words.count >= 3
    }

    /// Model-assisted pass. Falls back to heuristics on any failure.
    func refinedSearch(_ input: Input) async -> [MemorySearchResult] {
        guard input.mode != .clipboard else { return [] }
        let interpretation = await ai.interpretQuery(input.query, useAI: true)
        return HybridSearchService.search(
            query: input.query,
            clips: source(for: input),
            metadata: input.metadata,
            interpretation: interpretation
        )
    }

    func related(to clip: ClipItem, metadata: [UUID: AIMemoryMetadata], clips: [ClipItem]) -> [ClipItem] {
        HybridSearchService.related(
            to: clip,
            metadata: metadata[clip.id],
            allClips: clips,
            allMetadata: metadata
        )
    }

    private func source(for input: Input) -> [ClipItem] {
        switch input.mode {
        case .clipboard, .aiMemory:
            return input.clips
        case .favorites:
            return input.clips.filter { input.metadata[$0.id]?.isFavorite == true || input.pinnedIDs.contains($0.id) }
        }
    }
}
