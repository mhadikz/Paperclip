# Architecture

Paperclip uses **SwiftUI + MVVM + feature-based modules + dependency injection + repository/service
layer + Swift concurrency**, organized as Clean Architecture.

For agent rules, see [../AGENTS.md](../AGENTS.md).

---

## Layer diagram

```
┌─────────────────────────────────────────────┐
│ App                                         │
│  PaperclipApp · AppState · AppRouter        │
│  DependencyContainer · Windows · URL events │
└───────────────────┬─────────────────────────┘
                    │ injects
┌───────────────────▼─────────────────────────┐
│ Features (Presentation)                     │
│  Clipboard · Search · AI · Settings         │
│  Views + ViewModels + ThumbnailStore        │
└───────────────────┬─────────────────────────┘
                    │ calls
┌───────────────────▼─────────────────────────┐
│ Domain                                      │
│  Models · Protocols · UseCases · Services   │
└───────────────────▲─────────────────────────┘
                    │ implements
┌───────────────────┴─────────────────────────┐
│ Data                                        │
│  Repositories · Persistence · Services · AI │
└─────────────────────────────────────────────┘
┌─────────────────────────────────────────────┐
│ Core — Design · Logging · Utilities · Compat│
└─────────────────────────────────────────────┘
```

### Dependency rule

- **Features → Domain** (never Data types; AI only through `AIMemoryServicing`)
- **Data → Domain protocols**
- **App** composes Data implementations into Domain and Features
- **Domain** does not import SwiftUI and holds no singletons
- **Core** has no feature knowledge (`ContentHasher`, `AppLogger`, design tokens, `@ViewState`)

---

## Directory map

```
Paperclip/
├── App/
│   ├── PaperclipApp.swift          # @main, MenuBarExtra (label observes AppSettings directly)
│   ├── AppState.swift              # searchText, navigationMode, selection, preview, presentation count
│   ├── AppRouter.swift             # windows, open URL, reveal in Finder, system settings panes
│   ├── DependencyContainer.swift   # composition root; hotkey/login-item sync; flush on quit
│   ├── URLEventHandler.swift       # paperclip://open | paste/<id> | settings
│   └── Windows/
│       ├── HistoryWindowController.swift   # non-activating NSPanel
│       └── PreferencesWindowController.swift
├── Features/
│   ├── Paperclip/                  # MenuBarView, ClipboardView, ClipboardViewModel, ThumbnailStore, Components/
│   ├── Search/                     # SearchViewModel (two-phase)
│   ├── AI/                         # AIMemoryView, AIMemoryViewModel, MemoryDetailView, TimelineGrouping
│   └── Settings/                   # SettingsView + tabs + SettingsViewModel + ShortcutRecorderView
├── Shared/                         # WidgetSnapshot, WidgetActions (compiled into the widget too)
├── Domain/
│   ├── Models/                     # ClipItem, Pinboard, AppSettings, AIMemoryMetadata, HotKeySpec, AIModels, …
│   ├── Protocols/                  # RepositoryProtocols, ServiceProtocols
│   ├── Services/                   # HeuristicClassifier, QueryInterpreter, HybridSearchService,
│   │                               # SensitiveContentFilter, SmartActionCatalog (pure)
│   └── UseCases/                   # CaptureClip, PasteClip, DeleteClips, ManagePinboard, UpdateClip,
│                                   # SearchMemory, AIMemoryUseCases (Enqueue/Process/Update)
├── Data/
│   ├── Repositories/               # Clipboard, Pinboard, AIMemory, PasteStack
│   ├── Persistence/                # JSONFileStore, ClipPersistence, AIMetadataStore, MediaStore, WidgetSnapshotWriter
│   ├── Services/                   # ClipboardMonitor, PasteService, HotKeyManager, LaunchAtLoginService,
│   │                               # ConfirmationPrompter, InstalledAppsService
│   └── Services/AI/                # LanguageModelProvider, Heuristic + Apple FM providers, AIService, queue, prompts
└── Core/
    ├── Design/                     # AppTheme, AppPalette, GlassChrome (+ reduce-transparency fallback)
    ├── Logging/AppLogger.swift
    ├── Utilities/ContentHasher.swift
    └── Compat/ViewState.swift
```

---

## MVVM mapping

| Feature | Views | ViewModel | Owns |
| --- | --- | --- | --- |
| Clipboard | `MenuBarView`, `ClipboardView`, `ClipCardView`, `ClipPreviewView`, `HistoryChrome`, `PinboardManagerView` | `ClipboardViewModel` | `visibleClips` (filtered once per change), selection/navigation, paste/copy/delete/rename, pinboards, favorites |
| Thumbnails | — | `ThumbnailStore` | Off-main decoding + cache of image previews |
| Search | embedded in AI Memory | `SearchViewModel` | Instant heuristic results, delayed model refinement |
| AI | `AIMemoryView`, `MemoryDetailView` | `AIMemoryViewModel` | Detail, smart actions, favorites/tags |
| Settings | `SettingsView` + tabs | `SettingsViewModel` | Hotkey apply, Accessibility/login status, storage stats, AI maintenance |

Shared UI shell state lives in **`AppState`**. Closing History calls `resetHistorySession()` (search,
filter, selection, preview). `historyPresentationCount` increments on every show so views can
re-focus the search field.

`@Published` publishers fire on `willSet`; ViewModels that derive state from `AppState` keep mirrors
of the emitted values instead of reading `AppState` inside the sink.

---

## Domain use cases

| Use case | Responsibility |
| --- | --- |
| `CaptureClipUseCase` | Policies (pause, ignored apps, sensitive, size) → insert or bump → RTF sidecar → trim → enqueue AI; image hash dedupe + async OCR |
| `PasteClipUseCase` | Write pasteboard (+RTF/URL types), tell monitor to ignore, bump, delayed ⌘V when allowed; Accessibility prompt |
| `DeleteClipsUseCase` | Cascade to media, metadata, pinboards, paste stack; delete-all keeps pinned |
| `ManagePinboardUseCase` | Pinboard CRUD / pin / unpin |
| `UpdateClipUseCase` | Rename (title) |
| `SearchMemoryUseCase` | `quickSearch` (sync heuristics), `shouldRefineWithAI`, `refinedSearch`, related |
| `EnqueueAIProcessingUseCase` | Heuristic seed + policy (`shouldProcess`) + queue; launch backfill of missing/interrupted |
| `ProcessAIMemoryUseCase` | Classify/summarize via `AIMemoryServicing` → metadata upsert (keeps favorites) |
| `UpdateAIMemoryUseCase` | Favorite / tags / clear |

Cross-aggregate orchestration stays in use cases.

---

## Data repositories

| Repository | State | Persistence |
| --- | --- | --- |
| `ClipboardRepository` | `[ClipItem]` | `history.json` via `JSONFileStore` + widget snapshot |
| `PinboardRepository` | `[Pinboard]` | `pinboards.json` |
| `AIMemoryRepository` | `[UUID: AIMemoryMetadata]` | `ai-metadata.json` |
| `PasteStackStore` | `[UUID]` | memory only |

`JSONFileStore` coalesces saves (250 ms), encodes on a utility queue, writes atomically, moves
undecodable files aside (`*.corrupt-<timestamp>`), keeps a `.bak` from the first load, and `flush()`
writes synchronously on `applicationWillTerminate`.

---

## DI / composition root

`DependencyContainer.shared`:

1. Constructs persistence, media store, services (`PasteService`, `ClipboardMonitor`, `HotKeyManager`,
   `LaunchAtLoginService`, `AIService`, `AIProcessingQueue`, `ThumbnailStore`), repos, settings
2. Lazily builds use cases and ViewModels
3. `start()` wires:
   - `AIProcessingQueue.setHandler` → `ProcessAIMemoryUseCase`
   - `ClipboardMonitor.onNewContent` → `CaptureClipUseCase`
   - hotkey from `AppSettings.hotKey` (re-registered on change)
   - login item status sync (system is the source of truth)
   - AI backfill, widget snapshot, URL handler, widget copy relay, flush on terminate

SwiftUI receives objects via `.environmentObject(...)`.

---

## Concurrency model

```
Pasteboard poll (Timer, main, 0.35 s)
  → ClipboardMonitor (skips concealed/transient types; TIFF→PNG off main)
  → MainActor CaptureClipUseCase
  → Repository insert (value types) → JSONFileStore.scheduleSave (utility queue)
  → EnqueueAIProcessingUseCase (heuristic seed, sync)
       → actor AIProcessingQueue (serial; waits for a handler)
       → ProcessAIMemoryUseCase (MainActor) → AIService (actor) → providers
OCR: Task.detached (Vision) → clipboard.update on MainActor
Thumbnails: ThumbnailStore → Task.detached (ImageIO) → NSCache
```

- Capture **never** waits on Foundation Models, Vision or disk encoding
- Search: quick pass is synchronous; refinement is a cancellable `Task` with a 450 ms delay
- Pasteboard self-writes are excluded by syncing the monitor's change count immediately

---

## Windowing (macOS agent app)

App is `LSUIElement = true`.

- **History:** `NSPanel` with `.nonactivatingPanel` + `.utilityWindow`, floating, moves to the active
  Space, hides on resign-key, remembers its size, opens on the screen under the mouse. Esc closes
  (or clears search / closes preview first). `NSGlassEffectView` chrome on macOS 26.
- **Settings:** custom `NSWindow` (`PreferencesWindowController`), normal level, autosaved frame;
  closing hides the app so focus returns to the previous app.

Do not use the SwiftUI `Settings` scene — it would open a second, different window.

---

## Extension points

| Goal | How |
| --- | --- |
| New AI provider | Implement `LanguageModelProvider`; inject into `AIService` |
| New smart action | Add `SmartRewriteStyle` + `SmartActionCatalog` mapping |
| New settings | `AppSettings` + `SettingsProviding` + Settings UI |
| New capture policy | `CaptureClipUseCase` + tests in `CaptureTests.swift` |
| App Intents / Spotlight later | Call use cases from the intent handler |

---

## Anti-patterns (rejected)

- God-object store on MainActor holding all concerns
- AI calls from SwiftUI `Button` action bodies (use ViewModel → use case → protocol)
- Duplicating clip `text` into AI metadata JSON
- Blocking capture on model download / failure / image encoding
- Logging pasteboard strings
- Reading `AppState` inside a `$published` sink (fires before the value changes)
