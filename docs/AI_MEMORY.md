# AI Memory

Traditional clipboard remains primary. AI Memory is an optional layer over the same `ClipItem` history.

See also: [PRIVACY_SECURITY.md](PRIVACY_SECURITY.md), [FEATURES.md](FEATURES.md), [STATUS.md](STATUS.md).

---

## Concept

```
ClipItem (source of truth)
    +
AIMemoryMetadata (sidecar by clip UUID)
    =
Memory (searchable, tagged, summarized)
```

Do **not** duplicate clipboard bodies into AI storage.

---

## Data flow

```
NSPasteboard
  → ClipboardMonitor
  → CaptureClipUseCase
  → ClipboardRepository → history.json
       └─ EnqueueAIProcessingUseCase
            ├─ immediate HeuristicClassifier seed (status: pending)
            └─ AIProcessingQueue (actor, serial, waits for its handler)
                 → ProcessAIMemoryUseCase
                 → AIMemoryServicing (AIService → heuristic or Apple FM provider)
                 → AIMemoryRepository → ai-metadata.json
```

At launch `backfill` re-queues clips with missing metadata or whose status is `pending`/`processing`
(interrupted by a quit), limited to 100.

---

## Protocols (Domain)

| Protocol | Implemented by | Purpose |
| --- | --- | --- |
| `AIMemoryServicing` | `AIService` (actor) | classify, summarize, rewrite, interpretQuery, availability, active provider id |
| `AIProcessingQueuing` | `AIProcessingQueue` (actor) | enqueue / enqueueMany / pendingCount |
| `LanguageModelProvider` (Data) | `HeuristicLanguageModelProvider`, `AppleFoundationModelsProvider` | low-level model operations |

Tests use `FakeAI` / `FakeQueue` (see `PaperclipTests/Fakes.swift`).

---

## Classification

1. **Heuristics first** (`Domain/Services/HeuristicClassifier`): URL, email, SQL, JSON, XML, shell,
   code (+language), markdown, config, phone, article/plain. Structured categories are final.
2. **Model classify** only for prose-like text when enabled and available; its tags fall back to the
   heuristic ones when empty.
3. Sensitive content → `credentials` / skipped unless `processSensitiveContent` is on.

Prompts live in `Data/Services/AI/AIPrompts.swift`; `AIPromptVersion.current` (Domain) is stamped
on metadata so stale entries can be found later.

---

## Search (two-phase)

`SearchViewModel` → `SearchMemoryUseCase`:

1. **Quick pass** (synchronous, every keystroke after 120 ms debounce): `QueryInterpreter.heuristic`
   + `HybridSearchService.search` (exact phrase, keywords, category/app/time cues, summary match,
   favorites, importance, recency). Results need at least one real match.
2. **Refinement** (450 ms later, cancellable) only when semantic search is on, Foundation Models are
   enabled, and the query has ≥ 3 words: `AIService.interpretQuery` then the same scorer. The list is
   replaced only if the query is unchanged. Footer shows "Refining with Apple Intelligence…".

**Important:** the menu bar never uses this search state.

---

## Smart actions

`SmartActionCatalog` (Domain) picks `SmartRewriteStyle` values per clip type/category. Format JSON is
deterministic and works without a model. Images need OCR text; credentials get no actions.
Default **Paste** never runs AI.

---

## Foundation Models notes

- Soft-linked / availability-gated (`#if canImport(FoundationModels)`, `#available(macOS 26.0, *)`)
- Deployment target remains **14.0**
- `@Generable` not used (CLI builds); JSON is extracted from text responses
- Guardrail violations / refusals surface as `AIProviderError.refused`
- Availability copy surfaced in Settings › AI Memory

---

## Settings (AI)

| Setting | Default |
| --- | --- |
| Enable AI Memory | On |
| Classify/tag automatically | On |
| Summaries / tags | On |
| Natural-language search | On |
| Use Apple Foundation Models | On (falls back if unavailable) |
| Allow model on sensitive content | Off |
| Sensitive storage policy | Never store |

---

## Testing AI without models

`./scripts/test.sh ai` — `AITests.swift` covers the queue handler race, enqueue policy, backfill,
processing (favorites preserved, toggles respected, sensitive skip), `AIService` fallbacks and the
JSON-in-text parser.

---

## Performance guidelines

- Debounce search (120 ms); refine after 450 ms, only for natural-language queries
- Skip texts over 12,000 characters for model processing (heuristics still run)
- Serial queue with a short pause between items; capture never waits
- Prefer heuristic short-circuit for structured content
