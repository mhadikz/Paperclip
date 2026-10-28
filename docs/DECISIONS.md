# Decision log

Significant choices made while building Paperclip (for future sessions).

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-08 | Menu bar agent app (`LSUIElement`) | Match CopyClip/Paste; stay out of Dock |
| 2026-08 | JSON files under Application Support | Simple, inspectable, no CloudKit requirement |
| 2026-08 | Poll `NSPasteboard.changeCount` | Reliable without Accessibility for capture |
| 2026-08 | Carbon global hotkey | Works without Accessibility |
| 2026-08 | Custom prefs `NSWindow` | SwiftUI Settings scene unreliable for agent apps |
| 2026-08 | Pinboards store UUIDs only | Avoid duplicating clip content |
| 2026-08 | Paste stack in-memory only | Simpler; may persist later |
| 2026-08 | AI metadata sidecar file | Rebuildable; history remains source of truth |
| 2026-08 | Heuristics before Foundation Models | Fast, works offline, reduces model load |
| 2026-08 | Keep deployment target macOS 14 | Broader run support; FM gated at runtime |
| 2026-08 | No `@Generable` in CLI build | Macro plugin unavailable via `swiftc` path |
| 2026-08 | Menu search isolation | AI Memory search must not empty menu bar |
| 2026-08 | Prefer `~/Applications` install | External volume Launch Services failures |
| 2026-08 | Remove `ClipboardStore` god-object | Enforce Clean Architecture / testability |
| 2026-08 | Local-only / no default cloud AI | Privacy-first personal utility |
| 2026-09 | Docs + AGENTS.md harnesses | Session continuity after chat ends |
| 2026-09 | History card UI; Liquid Glass design system; navy/gold palette; Light/Dark/System | Visual identity; material fallback on macOS 14–15 |
| 2026-09 | Desktop widget via WidgetKit + App Intents Copy button | Preview-only snapshot; `paperclip://` scheme |
| 2026-10 | `@ViewState` typealias instead of `@State` | macOS 26/27 SDK makes `@State` a macro; Command Line Tools cannot expand it. Keeps the no-Xcode build path alive with identical semantics. |
| 2026-10 | History is a non-activating `NSPanel` | Activating the app sent ⌘V to the app itself. A `.nonactivatingPanel` takes key focus while the previous app stays frontmost. |
| 2026-10 | Duplicate copies bump the existing clip | Replacing it broke pinboard references and lost favorites/tags; bumping keeps identity. |
| 2026-10 | Image dedupe by SHA-256; text wins over image when both are present | Repeated screenshots piled up; spreadsheet copies were stored as pictures. |
| 2026-10 | RTF sidecar for formatted text (≤ 512 KB) | Pasting lost formatting; RTF is universally readable and small. HTML intentionally not stored. |
| 2026-10 | Coalesced background JSON writes + quarantine + `.bak` | Every copy re-encoded MBs on the main thread; a corrupt file was silently overwritten with an empty history. |
| 2026-10 | Pure logic moved into `Domain/Services`; AI behind `AIMemoryServicing` | Domain depended on Data concretions and singletons, which blocked testing and contradicted the documented rule. |
| 2026-10 | Sensitive detector favors precision | Entropy-only heuristics skipped file paths, identifiers and UUIDs silently. Known key prefixes and contiguous card runs are high precision; hex/UUID/paths exempt. |
| 2026-10 | Two-phase memory search | A model call per keystroke was slow and flickery. Heuristics answer instantly; the model refines only natural-language queries. |
| 2026-10 | Processing queue keeps ids until a handler exists | Backfill at launch raced the handler installation and dropped ids. |
| 2026-10 | Custom shortcut recorder (Carbon re-register) | ⇧⌘V collides with "Paste and Match Style"; users must be able to change it. |
| 2026-10 | Opaque surfaces when Reduce Transparency is on | Accessibility; also makes offscreen previews possible (`glassEffect` cannot be cached). |
| 2026-10 | Destructive "Clear" removed from History header | A red button in primary chrome invited accidents; it lives in the ••• menu with confirmation. |
| 2026-10 | Pinboard palette: gold/coral/teal/sky/violet/lime | White and midnight chips were invisible on one of the two themes. |
| 2026-10 | Custom test runner, no XCTest | Command Line Tools do not ship XCTest; the runner keeps tests runnable anywhere. |
| 2026-10 | Generated `Paperclip.xcodeproj` from a script | Hand-maintained project drifted (referenced deleted files). The script makes `build.sh`'s compile set authoritative. |
| 2026-10 | MIT license; Azure Pipelines + GitHub Actions | Open-source publication; CI uses the same scripts as developers. |
| 2026-10 | Bundle ID `com.mhadikz.Paperclip`; copyright mhadikz | Publisher-owned identifier; `AppSettings` migrates preferences from the old `com.local.Clipboard` domain once. |

## Open decisions

| Topic | Options | Notes |
| --- | --- | --- |
| Persist paste stack | Yes / No | UX nicety vs ephemeral intent |
| Core Spotlight / App Intents | Integrate / skip | System search vs complexity |
| Cloud providers | Opt-in only | Must not be default |
| Notarization | Join the Apple Developer Program / stay ad-hoc | Ad-hoc until there is a membership; users right-click → Open once |
| Localization | String catalogs | When a second language is wanted |
