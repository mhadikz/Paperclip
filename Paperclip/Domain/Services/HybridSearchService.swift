import Foundation

struct MemorySearchResult: Identifiable, Equatable {
    var id: UUID { clip.id }
    let clip: ClipItem
    let metadata: AIMemoryMetadata?
    let score: Double
    let reason: String
}

/// Keyword + metadata + cue scoring over clips. Pure and synchronous; callers decide
/// whether the interpretation came from heuristics or a language model.
enum HybridSearchService {
    static func search(
        query: String,
        clips: [ClipItem],
        metadata: [UUID: AIMemoryMetadata],
        interpretation: AIQueryInterpretation?,
        limit: Int = 60,
        now: Date = Date()
    ) -> [MemorySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return clips.prefix(limit).map {
                MemorySearchResult(clip: $0, metadata: metadata[$0.id], score: 1, reason: "Recent")
            }
        }

        let interp = interpretation ?? QueryInterpreter.heuristic(trimmed)
        let queryLower = trimmed.lowercased()
        let keywords = Set(interp.keywords.map { $0.lowercased() } + tokenized(trimmed))
        let appHint = interp.sourceAppHint?.lowercased()

        var scored: [MemorySearchResult] = []
        scored.reserveCapacity(min(clips.count, 256))

        for clip in clips {
            guard matchesRelativeTime(clip.createdAt, hint: interp.relativeTime, now: now) else { continue }

            let meta = metadata[clip.id]
            let blob = clip.searchBlob + " " + (meta?.memorySearchBlob ?? "")
            var score = 0.0
            var reasons: [String] = []

            // Exact phrase beats scattered keywords.
            if blob.contains(queryLower) {
                score += 4
                reasons.append("Exact match")
            }
            for keyword in keywords where blob.contains(keyword) {
                score += keyword.count > 5 ? 2.5 : 1.5
                reasons.append(keyword)
            }
            if let title = clip.title?.lowercased(), title.contains(queryLower) {
                score += 3
            }
            if let category = interp.category {
                let typeMatches = meta?.category == category
                    || (category == .url && clip.contentType == .link)
                    || (category == .image && clip.contentType == .image)
                    || (category == .file && clip.contentType == .file)
                if typeMatches {
                    score += 3
                    reasons.append(category.title)
                }
            }
            if let appHint, !appHint.isEmpty {
                let app = (clip.sourceAppName ?? "").lowercased()
                let bundle = (clip.sourceBundleID ?? "").lowercased()
                if app.contains(appHint) || bundle.contains(appHint) {
                    score += 2.5
                    reasons.append(clip.sourceAppName ?? "App")
                }
            }
            if let summary = meta?.summary?.lowercased(), keywords.contains(where: { summary.contains($0) }) {
                score += 2
            }
            if meta?.isFavorite == true {
                score += 0.5
            }
            score += (meta?.importance ?? 0.3) * 0.5

            // Recency: up to +2 for today, fading over two weeks.
            let ageDays = now.timeIntervalSince(clip.createdAt) / 86_400
            score += max(0, 2.0 - ageDays / 14.0)

            // Something beyond recency/importance has to match.
            if score > 2.6 && !reasons.isEmpty {
                scored.append(
                    MemorySearchResult(
                        clip: clip,
                        metadata: meta,
                        score: score,
                        reason: reasons.prefix(3).joined(separator: ", ").capitalized
                    )
                )
            }
        }

        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    static func related(
        to clip: ClipItem,
        metadata: AIMemoryMetadata?,
        allClips: [ClipItem],
        allMetadata: [UUID: AIMemoryMetadata],
        limit: Int = 5
    ) -> [ClipItem] {
        let seedTags = Set((metadata?.tags ?? []).map { $0.lowercased() })
        let seedCategory = metadata?.category
        let seedTokens = Set(tokenized(clip.searchBlob + " " + (metadata?.memorySearchBlob ?? "")))

        var scored: [(ClipItem, Double)] = []
        for other in allClips where other.id != clip.id {
            let meta = allMetadata[other.id]
            var score = 0.0
            if let seedCategory, meta?.category == seedCategory { score += 2 }
            let tags = Set((meta?.tags ?? []).map { $0.lowercased() })
            score += Double(seedTags.intersection(tags).count) * 1.5
            let tokens = Set(tokenized(other.searchBlob + " " + (meta?.memorySearchBlob ?? "")))
            score += Double(seedTokens.intersection(tokens).count) * 0.35
            if let app = clip.sourceAppName, app == other.sourceAppName { score += 0.5 }
            if score >= 2.5 {
                scored.append((other, score))
            }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    static func tokenized(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 }
    }

    private static func matchesRelativeTime(
        _ date: Date,
        hint: AIQueryInterpretation.RelativeTimeHint,
        now: Date
    ) -> Bool {
        let cal = Calendar.current
        switch hint {
        case .any:
            return true
        case .today:
            return cal.isDateInToday(date)
        case .yesterday:
            return cal.isDateInYesterday(date)
        case .lastWeek:
            guard let start = cal.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= start
        case .lastMonth:
            guard let start = cal.date(byAdding: .day, value: -31, to: now) else { return true }
            return date >= start
        }
    }
}
