import Foundation

// MARK: - Enqueue

/// Seeds heuristic metadata immediately and schedules background enrichment.
@MainActor
struct EnqueueAIProcessingUseCase {
    let aiMemory: AIMemoryRepositoryProtocol
    let settings: SettingsProviding
    let queue: AIProcessingQueuing

    /// Text above this size is skipped for model processing (heuristics still run).
    static let maxTextCharacters = 12_000

    static func shouldProcess(text: String?, settings: AppSettingsSnapshot) -> Bool {
        guard settings.aiFeaturesEnabled, settings.automaticAIProcessing else { return false }
        guard let text, !text.isEmpty else { return true }
        if text.count > maxTextCharacters { return false }
        if !settings.processSensitiveContent, SensitiveContentFilter.looksSensitive(text) {
            return false
        }
        return true
    }

    func execute(clip: ClipItem) {
        guard settings.aiFeaturesEnabled else { return }

        // Heuristic seed is cheap and makes the clip searchable right away.
        if aiMemory.metadata(for: clip.id) == nil {
            let result = HeuristicClassifier.classify(clip: clip)
            var meta = AIMemoryMetadata(clipID: clip.id, status: .pending)
            meta.category = result.category
            meta.replaceTags(result.tags)
            meta.summary = result.summary
            meta.codeLanguage = result.codeLanguage
            meta.importance = result.importance
            meta.searchableRepresentation = [result.category.title, result.tags.joined(separator: " "), result.summary]
                .compactMap { $0 }.joined(separator: " ")
            aiMemory.upsert(meta)
        }

        guard Self.shouldProcess(text: clip.text ?? clip.searchableText, settings: settings.snapshot) else { return }
        let queue = self.queue
        let id = clip.id
        Task { await queue.enqueue(id) }
    }

    /// On launch: pick up clips that never got metadata or were interrupted mid-processing.
    func backfill(from clips: [ClipItem], limit: Int = 100) {
        guard settings.aiFeaturesEnabled, settings.automaticAIProcessing else { return }
        let snapshot = settings.snapshot
        let ids = clips.filter { clip in
            let status = aiMemory.metadata(for: clip.id)?.status
            let needsWork = status == nil || status == .pending || status == .processing
            return needsWork && Self.shouldProcess(text: clip.text ?? clip.searchableText, settings: snapshot)
        }
        .prefix(limit)
        .map(\.id)
        guard !ids.isEmpty else { return }
        let queue = self.queue
        Task { await queue.enqueueMany(Array(ids)) }
    }
}

// MARK: - Process

/// Runs on the queue's callback: classify + summarize, then store the sidecar metadata.
@MainActor
struct ProcessAIMemoryUseCase {
    let clipboard: ClipboardRepositoryProtocol
    let aiMemory: AIMemoryRepositoryProtocol
    let settings: SettingsProviding
    let ai: AIMemoryServicing

    func execute(clipID: UUID) async {
        guard let clip = clipboard.clip(id: clipID) else { return }
        guard settings.aiFeaturesEnabled else { return }

        let text = clip.text ?? clip.searchableText
        if let text, SensitiveContentFilter.looksSensitive(text), !settings.processSensitiveContent {
            var skipped = aiMemory.metadata(for: clipID) ?? AIMemoryMetadata(clipID: clipID)
            skipped.status = .skipped
            skipped.category = .credentials
            skipped.tags = ["Sensitive"]
            skipped.summary = "Sensitive content excluded from AI processing"
            aiMemory.upsert(skipped)
            return
        }

        var meta = aiMemory.metadata(for: clipID) ?? AIMemoryMetadata(clipID: clipID)
        let favorite = meta.isFavorite
        meta.status = .processing
        aiMemory.upsert(meta)

        let useAI = settings.useFoundationModels && settings.automaticAIProcessing
        let classification = await ai.classify(clip: clip, useAI: useAI)

        // The clip may have been deleted while the model was busy.
        guard clipboard.clip(id: clipID) != nil else { return }

        meta.category = classification.category
        if settings.automaticTags {
            meta.replaceTags(classification.tags)
        }
        meta.language = classification.language
        meta.codeLanguage = classification.codeLanguage
        meta.entities = classification.entities
        meta.importance = classification.importance
        meta.isFavorite = favorite || (aiMemory.metadata(for: clipID)?.isFavorite ?? false)

        if settings.automaticSummaries {
            if let summary = classification.summary, (clip.text?.count ?? 0) < 160 {
                meta.summary = summary
            } else {
                meta.summary = await ai.summarize(clip: clip, useAI: useAI) ?? classification.summary
            }
        } else {
            meta.summary = classification.summary
        }

        meta.searchableRepresentation = [
            meta.category?.title,
            meta.tags.joined(separator: " "),
            meta.summary,
            meta.entities.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        meta.status = .completed
        meta.processedAt = Date()
        meta.promptVersion = AIPromptVersion.current
        meta.modelIdentifier = await ai.activeProviderID(useAI: useAI)
        meta.lastError = nil
        aiMemory.upsert(meta)
    }
}

/// Version stamp recorded on metadata so prompts can evolve and stale entries be found.
enum AIPromptVersion {
    static let current = "1.1.0"
}

// MARK: - Update

@MainActor
struct UpdateAIMemoryUseCase {
    let aiMemory: AIMemoryRepositoryProtocol

    func toggleFavorite(clipID: UUID) {
        var meta = aiMemory.metadata(for: clipID) ?? AIMemoryMetadata(clipID: clipID, status: .skipped)
        meta.isFavorite.toggle()
        aiMemory.upsert(meta)
    }

    func updateTags(clipID: UUID, tags: [String]) {
        var meta = aiMemory.metadata(for: clipID) ?? AIMemoryMetadata(clipID: clipID, status: .completed)
        meta.replaceTags(tags)
        aiMemory.upsert(meta)
    }

    func clearAll() {
        aiMemory.clearAll()
    }
}
