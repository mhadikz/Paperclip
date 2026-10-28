# AGENTS.md — Continuity for AI agents and new sessions

This file is the **primary handoff** for anyone (human or agent) continuing work on this repo.
Treat the docs as source of truth; the chat that produced a change is gone.

## Mission

Evolve and maintain a **native macOS clipboard manager + optional AI Memory** that stays:

- Fast and reliable as a clipboard utility first
- Private (local-only by default)
- Cleanly architected (SwiftUI + MVVM + feature modules + DI + use cases)
- Trustworthy enough to publish as open source

## Before coding

1. Read [README.md](README.md)
2. Read [docs/STATUS.md](docs/STATUS.md) (current state + known issues)
3. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) if changing structure
4. Read [docs/AI_MEMORY.md](docs/AI_MEMORY.md) if touching AI/search/privacy
5. Build with `./scripts/check.sh` / `./scripts/build.sh`; do not assume Xcode is installed

## Architecture rules

```
Features → Domain ← Data
              ↑
         App (DependencyContainer)
```

- **Do not** recreate a god-object like the old `ClipboardStore`.
- **Do not** call persistence, pasteboard, `NSWorkspace` or `NSAlert` from SwiftUI views. Views call
  ViewModels; ViewModels call use cases; use cases use Domain protocols.
- Business logic goes in **Domain/UseCases** (one use case per file); pure logic in **Domain/Services**;
  data access in **Data/Repositories**; system integration in **Data/Services**; UI state in
  **Feature ViewModels**.
- Register new dependencies in `Paperclip/App/DependencyContainer.swift`. No new singletons.
- Domain must not import SwiftUI. Features must not touch JSON files or `AIService` directly.
- Write `@ViewState` instead of `@State` (see `Core/Compat/ViewState.swift`).

## Critical product invariants

| Rule | Why |
| --- | --- |
| Capture path never awaits AI, image decoding or disk encoding | Copying must feel instant |
| Menu bar ignores History `searchText` | Searching AI Memory must not empty the menu |
| History is a non-activating `NSPanel` | The previous app keeps focus so ⌘V lands there |
| Settings via `PreferencesWindowController` | LSUIElement apps break the SwiftUI Settings scene |
| AI optional | App works with heuristics only / without Apple Intelligence |
| No clipboard content in logs | Privacy |
| AI metadata is a sidecar | Clearing AI keeps history |
| Duplicate copies bump, never duplicate | Pins, favorites and tags must survive re-copies |
| `org.nspasteboard.ConcealedType` / `TransientType` always skipped | Password managers rely on it |

## Where things live

| Concern | Location |
| --- | --- |
| Composition root / DI | `Paperclip/App/DependencyContainer.swift` |
| UI shell state (search, mode, selection, preview) | `Paperclip/App/AppState.swift` |
| Windows / URL scheme / system navigation | `Paperclip/App/AppRouter.swift`, `App/Windows/`, `App/URLEventHandler.swift` |
| Menu + History UI, view model, thumbnails | `Paperclip/Features/Clipboard/` |
| AI Memory UI | `Paperclip/Features/AI/` |
| Search VM (two-phase) | `Paperclip/Features/Search/` |
| Settings UI, shortcut recorder | `Paperclip/Features/Settings/` |
| Widget | `PaperclipWidget/`, `Paperclip/Shared/` |
| Use cases (capture, paste, delete, pinboards, search, AI, edit) | `Paperclip/Domain/UseCases/` |
| Pure logic (classifier, query interpreter, hybrid search, sensitive filter, smart actions) | `Paperclip/Domain/Services/` |
| Protocols (repositories, services, AI, confirmation) | `Paperclip/Domain/Protocols/` |
| Repos + coalesced JSON persistence | `Paperclip/Data/Repositories/`, `Paperclip/Data/Persistence/` |
| Pasteboard monitor / paste / hotkey / login item / alerts | `Paperclip/Data/Services/` |
| Foundation Models provider, AI service, queue, prompts | `Paperclip/Data/Services/AI/` |
| Settings model | `Paperclip/Domain/Models/AppSettings.swift` |
| Design system | `Paperclip/Core/Design/` |
| Tests | `PaperclipTests/` (runner in `TestHarness.swift`, fakes in `Fakes.swift`) |
| Landing page | `site/` (static; repository slug in `site/site.js`; deployed by `.github/workflows/pages.yml`) |

## Build & verify

```bash
./scripts/check.sh      # fast type-check
./scripts/test.sh       # run tests (optionally: ./scripts/test.sh "capture")
./scripts/build.sh      # build + install to ~/Applications
./scripts/render-previews.sh   # offscreen PNGs of the main screens (build/previews/)
open ~/Applications/Paperclip.app
```

Manual smoke checklist is in `docs/STATUS.md`.

## Privacy when changing AI

- Prefer on-device Apple Foundation Models behind availability checks
- Do not add cloud providers as default
- Never log prompts that include clipboard content
- Keep `SensitiveContentFilter` on the capture and AI paths; add tests for new patterns (both
  positives and false positives)

## Docs to update when you change behavior

| Change | Update |
| --- | --- |
| New user-facing feature | `docs/FEATURES.md`, `docs/STATUS.md`, `CHANGELOG.md`, README feature list |
| Architecture / DI | `docs/ARCHITECTURE.md`, AGENTS.md if rules change |
| AI / search / providers | `docs/AI_MEMORY.md` |
| Build / run / persistence | `docs/DEVELOPMENT.md` |
| Privacy | `docs/PRIVACY_SECURITY.md`, `SECURITY.md` |
| Release process | `docs/DISTRIBUTION.md` |

## Out of scope unless explicitly requested

- iCloud sync, iOS app, team pinboard sharing
- Backend / auth / analytics of clipboard content
- Replacing local JSON with a remote DB
- Rewriting the app from scratch

## Session end checklist (for agents)

- [ ] `./scripts/check.sh` and `./scripts/test.sh` pass
- [ ] `./scripts/build.sh` succeeds and the app launches
- [ ] Tests added for changed behavior
- [ ] STATUS.md / CHANGELOG.md updated if capabilities or known issues changed
- [ ] Xcode project regenerated if files were added/moved (`python3 scripts/generate-xcodeproj.py`)
- [ ] No secrets or clipboard samples committed
- [ ] Did not revive singleton god-store patterns or raw `@State`
