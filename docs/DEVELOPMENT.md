# Development guide

## Requirements

- macOS 14+ to run; macOS 26+ with Apple Intelligence for Foundation Models enrichment
- **Command Line Tools** (`xcode-select --install`). Xcode is optional.
- Python 3 (ships with macOS) for `scripts/generate-xcodeproj.py`

Check:

```bash
swift --version
xcrun --show-sdk-path
```

## Scripts

| Script | What it does |
| --- | --- |
| `scripts/check.sh` | Type-checks app + widget sources (fast feedback) |
| `scripts/test.sh [filter]` | Compiles and runs `PaperclipTests/` (custom runner, no XCTest) |
| `scripts/build.sh [--release] [--no-install]` | Builds `build/Paperclip.app` (+ appex), signs inside-out, installs to `~/Applications` (+ `/Applications`) and registers the widget. `--release` = universal + optimized |
| `scripts/package.sh` | zip + DMG + SHA256SUMS in `build/dist/` |
| `scripts/make-icon.sh` | Regenerates `Paperclip/Resources/AppIcon.icns` from `scripts/make-icon.swift` |
| `scripts/generate-xcodeproj.py` | Regenerates `Paperclip.xcodeproj` from the files on disk |
| `scripts/render-previews.sh` | Renders the main screens to `build/previews/*.png` without Screen Recording permission |

`SIGN_IDENTITY="Developer ID Application: …"` switches from ad-hoc to real signing.

### Why `~/Applications`?

Launching an agent `.app` from some external volumes fails with `kLSNoExecutableErr`. The widget
gallery (PluginKit) is also happier with a copy in `/Applications`.

### The `@State` quirk

With the macOS 26/27 SDK, `@State` is a macro whose plugin only ships inside Xcode. Builds through
the Command Line Tools fail with *"plugin for module 'SwiftUIMacros' not found"*. The project uses
`@ViewState` (`Core/Compat/ViewState.swift`), a typealias to `SwiftUI.State` with identical
semantics. `scripts/check.sh` will catch any stray `@State`.

## Test

```bash
./scripts/test.sh            # all
./scripts/test.sh capture    # only tests whose name contains "capture"
```

- Compiles app sources **without** `@main` `PaperclipApp.swift` plus `PaperclipTests/*.swift`
- `Fakes.swift` provides `TestWorld` (real repositories in a temp dir, fake paste/monitor/AI/queue)
- Covers sensitive detection, models, heuristics, search, persistence (coalescing, quarantine),
  repositories, capture policies, paste/delete cascades, AI processing, view-model logic
- Does **not** require Apple Intelligence; runs in under a second

## App identity

| Key | Value |
| --- | --- |
| Product name | Paperclip |
| Bundle ID | `com.mhadikz.Paperclip` (widget: `.Widget`, app group: `group.com.mhadikz.Paperclip`) |
| Version / build | 1.3.0 / 12 (app and widget plists) |
| `LSUIElement` | `true` (no Dock icon) |
| Min OS | 14.0 |
| Icon | `Paperclip/Resources/AppIcon.icns` |

## Persistence paths

```
~/Library/Application Support/Paperclip/
  history.json (+ .bak)          pinboards.json (+ .bak)        ai-metadata.json (+ .bak)
  Media/{uuid}.png               Media/{uuid}.rtf               widget-snapshot.json
  *.corrupt-<timestamp>          (only if a file failed to decode)
~/Library/Group Containers/group.com.mhadikz.Paperclip/
  widget-snapshot.json           widget-command.json (transient)
```

Settings: `UserDefaults` keys listed in `AppSettings.Keys` (`hotKey` is JSON-encoded `HotKeySpec`).

### Reset local data (dev only)

```bash
pkill -x Paperclip || true
rm -rf ~/Library/Application\ Support/Paperclip
# optional: defaults delete com.mhadikz.Paperclip
```

## Architecture entry points

| Task | Start file |
| --- | --- |
| Wire new service | `App/DependencyContainer.swift` |
| New capture rule | `Domain/UseCases/CaptureClipUseCase.swift` (+ `CaptureTests.swift`) |
| New UI on History | `Features/Clipboard/ClipboardView.swift` + ViewModel + `Core/Design/` |
| AI search behavior | `Features/Search/SearchViewModel.swift` + `Domain/Services/HybridSearchService.swift` |
| AI processing | `Domain/UseCases/AIMemoryUseCases.swift` + `Data/Services/AI/` |
| Settings tab | `Features/Settings/` |
| Sensitive patterns | `Domain/Services/SensitiveContentFilter.swift` (+ tests) |

## Concurrency conventions

- UI, repositories, use cases: `@MainActor`
- `AIProcessingQueue`, `AIService`: actors
- Heavy work (PNG transcoding, OCR, thumbnails, JSON encoding): `Task.detached` or utility queues
- Capture must not `await` anything

## Logging

Use `AppLogger` (`Core/Logging/AppLogger.swift`): categories `general`, `clipboard`, `persistence`,
`ai`, `ui`. **Never** log clipboard text, OCR bodies, file paths copied by the user, or secrets.

```bash
log stream --predicate 'subsystem == "com.mhadikz.Paperclip"' --style compact
```

## Common pitfalls

1. **Paste goes nowhere** — Accessibility not granted (Settings › General shows the state), or the
   History window activated the app (it must stay a non-activating panel).
2. **Accessibility keeps resetting** — ad-hoc signatures change on every build. Use a stable signing
   identity for day-to-day use.
3. **Menu empty after search** — menu must use `ClipboardViewModel.displayedClips` (unfiltered).
4. **Echo capture** — after writing the pasteboard call `monitor.ignoreCurrentChange()` (the paste use
   case does).
5. **Duplicate `@main`** — only `PaperclipApp.swift`; tests and the preview renderer exclude it.
6. **FoundationModels** — guard with `#if canImport` + `#available(macOS 26.0, *)`.
7. **Widget missing from gallery** — appex must use `_NSExtensionMain`, sandbox + app group, and be
   signed **without** `--deep`. Search **Paperclip** in Edit Widgets.
8. **Widget shows 0 clips** — sandboxed `containerURL` is often nil without a Team ID; the snapshot is
   also written to the real group container path and Application Support.
9. **Menu bar icon gone** — `MenuBarExtra`'s label has no parent environment during init; it observes
   `AppSettings` through `@ObservedObject`, never `@EnvironmentObject`.
10. **Blank glass in offscreen renders** — `glassEffect` cannot be cached; previews use
    `.environment(\.appGlassDisabled, true)`, the same path as Reduce Transparency.

## Frameworks linked

SwiftUI, AppKit, ServiceManagement, Combine, Carbon, Vision, FoundationModels, OSLog, WidgetKit,
AppIntents, CryptoKit (via Foundation)

## Landing page (`site/`)

Static HTML + CSS + a few lines of JS, no build step and no third-party requests. Brand colors
mirror `AppPalette`; screenshots are copies of `docs/assets/*.png` (re-copy after
`scripts/render-previews.sh` if they change).

- Preview: `open site/index.html` (the release lookup fails silently when opened from disk).
- Configure: `REPO` in `site/site.js` (owner/name on GitHub). All links derive from it, and the
  download button is upgraded to the latest DMG through the GitHub Releases API.
- Deploy: `.github/workflows/pages.yml` publishes `site/` on every push to `main` that touches it.
  One-time repository setting: *Settings → Pages → Source: GitHub Actions*.
- Releases: `.github/workflows/release.yml` runs on tags `v*`, builds the universal app and attaches
  zip, DMG and `SHA256SUMS.txt` to a GitHub Release, which is what the landing page links to.

## Older SDKs

Liquid Glass (`Glass`, `NSGlassEffectView`, `glassEffect`) and `FoundationModels` exist only in the
macOS 26 SDK. The code wraps them in `#if compiler(>=6.2)` / `#if canImport(FoundationModels)` so it
also compiles with Xcode 16, and the scripts link FoundationModels only when the SDK has it. CI runs
on both macOS 15 and macOS 26 runners; releases are built on macOS 26.
