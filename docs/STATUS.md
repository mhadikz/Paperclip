# Project status (handoff)

**Last updated:** 2026-10-26  
**App version:** 1.3.0 (build 12)  
**Bundle ID:** `com.mhadikz.Paperclip` (settings migrate automatically from the pre-1.3 `com.local.Clipboard` domain)  
**Deployment target:** macOS 14.0 · universal (arm64 + x86_64) in release builds  
**Toolchain:** Command Line Tools only (Swift 6.4 / macOS 27 SDK). Xcode optional.

This document is the **current truth** of the repo for new sessions.

---

## What happened in the 1.3.0 session (2026-10-26)

A full review of implementation, design, testing and tooling, then fixes and improvements aimed at
an open-source, trustworthy release. Highlights:

1. **Build was broken on the current OS** — `@State` became a macro in the macOS 26/27 SDK and the
   Command Line Tools cannot expand it. Fixed with the `@ViewState` typealias (`Core/Compat`). Never
   write `@State` in this repo.
2. **Paste into the frontmost app never worked from History** — the window activated Clipboard, so ⌘V
   went to the app itself. History is now a non-activating `NSPanel`; the previous app keeps focus.
3. **Architecture cleanup** — pure logic (classifier, query interpreter, hybrid search, sensitive
   filter, smart actions) moved into `Domain/Services`; AI and system services are reached through
   Domain protocols (`AIMemoryServicing`, `AIProcessingQueuing`, `PasteServing`, `LaunchAtLoginServicing`,
   `ConfirmationPrompting`). Use cases split into one file each. No singletons used from Domain.
4. **Data safety + performance** — coalesced background JSON writes (`JSONFileStore`), corrupt-file
   quarantine, `.bak` on first load, flush on quit; thumbnails decoded off-main (`ThumbnailStore`);
   cards receive a bounded excerpt; the visible list is computed once per change, not per body.
5. **Capture fidelity** — duplicate copies bump the existing clip (keeps id, pins, favorites, tags);
   images dedupe by SHA-256; RTF sidecar preserves formatting; spreadsheet copies stay text;
   `org.nspasteboard.ConcealedType`/`TransientType` honoured; oversized clips skipped; rewritten
   sensitive-content heuristics (far fewer false positives, known key prefixes, contiguous card runs).
6. **Product polish** — customizable global shortcut with recorder, keyboard-first History
   (↑↓ ↩ ⇧↩ ⌘C ⌘⌫ ⌘Y ⌘F ⌘1–9), in-panel preview, rename, open link, reveal in Finder, drag out,
   paused badge on the menu bar icon, Accessibility/login-item status in Settings, storage usage,
   app icon, About with principles.
7. **AI** — handler race in the processing queue fixed (ids waited for a handler instead of being dropped);
   interrupted `processing` items are resumed at launch; two-phase search (instant heuristics,
   model refinement only for natural-language queries); honest `modelIdentifier`.
8. **Tooling** — `scripts/check.sh` (typecheck), `scripts/build.sh --release --no-install`
   (universal, hardened runtime), `scripts/package.sh` (zip + dmg + checksums), `scripts/make-icon.sh`,
   `scripts/generate-xcodeproj.py` (regenerates the Xcode project), `scripts/render-previews.sh`
   (offscreen UI renders), Azure Pipelines + GitHub Actions, LICENSE (MIT), CONTRIBUTING, SECURITY,
   CHANGELOG.
9. **Tests** — 77 tests in `PaperclipTests/` (custom runner, no XCTest) covering the sensitive filter,
   models, heuristics, search, persistence, repositories, capture policies, paste/delete cascades,
   AI processing, and view-model logic. They run in under a second.

Earlier history (v1.0–1.2) is summarised in [CHANGELOG.md](../CHANGELOG.md).

---

## Current capabilities

### Clipboard history (required path)
- [x] Menu bar history + `⌘0`–`⌘9`, type icons, paused badge
- [x] Text / link / image / file capture; RTF sidecar for formatted text; OCR for images
- [x] Duplicate bump, image hash dedupe, remember limit (pinned/favorites never trimmed), display limit
- [x] Pinboards (UUID refs only), paste stack (in-memory), ignored apps, concealed-type skipping
- [x] Launch at login (`SMAppService`, status surfaced), record pause/resume
- [x] Customizable global hotkey (Carbon, no Accessibility needed)
- [x] History panel (non-activating): keyboard navigation, preview, rename, open link, reveal, drag out
- [x] Paste into frontmost app (Accessibility) with graceful copy-only fallback and one-time prompt
- [x] Settings window (General, AI Memory, Ignored Apps, Clips, About)
- [x] Desktop / Notification Center widget (relative timestamps, Copy button)

### AI Memory (optional path)
- [x] Heuristic classification / tags / summaries (always)
- [x] Apple Foundation Models provider behind availability checks (macOS 26+)
- [x] Serial background queue; backfill of missing/interrupted items at launch
- [x] Two-phase hybrid search; related memories; timeline grouping; favorites
- [x] Smart actions (contextual; Format JSON works offline)
- [x] Sensitive policies: never store / store without AI / redacted placeholder

### Quality / ops
- [x] `scripts/check.sh`, `scripts/test.sh`, `scripts/build.sh`, `scripts/package.sh`
- [x] CI definitions for Azure Pipelines and GitHub Actions
- [x] Docs harness (`docs/`, `AGENTS.md`, Cursor rule)

---

## Known issues / limitations

| Item | Notes |
| --- | --- |
| Ad-hoc signing resets Accessibility | Each rebuild changes the code identity, so macOS forgets the Accessibility grant. Developer ID signing fixes this for releases. |
| Not notarized | No Apple Developer Program membership yet; users must right-click → Open once. See DISTRIBUTION.md for the self-signed-certificate tip (stable Accessibility grant) and the future notarization path. |
| Launch at login outside /Applications | `SMAppService` may report "requires approval" or fail; Settings shows the real status. |
| Paste stack not persisted | Clears on quit (by design). |
| `@Generable` macros | Not used; FM responses are parsed as JSON-in-text so CLI builds work. |
| Widget needs `/Applications` copy | PluginKit sometimes ignores `~/Applications`; `build.sh` installs both when writable. |
| Multimodal FM on images | Vision OCR + text actions only. |
| Core Spotlight / App Intents search | Not integrated. |
| Localization | English only. |
| Screen Recording for screenshots | Use `scripts/render-previews.sh` for design reviews instead of `screencapture`. |

---

## Suggested next work (priority order)

1. **Sign + notarize** with a Developer ID (see DISTRIBUTION.md), then publish v1.3.0 artifacts.
2. **Persist paste stack** (optional) and expose it more visibly.
3. **Core Spotlight** index and an App Intent for “search my clipboard”.
4. **Localization** scaffolding (String catalogs) once there is a second language.
5. **Sparkle or similar** update channel if distributing outside the App Store long-term.
6. **Provider stubs** for future cloud models behind explicit opt-in (never default).

---

## Smoke test before shipping a change

```bash
./scripts/check.sh && ./scripts/test.sh && ./scripts/build.sh
open ~/Applications/Paperclip.app
```

1. Copy text / image / file → appears in the menu and in History.
2. Hotkey (default ⇧⌘V) toggles History; ↑/↓ moves, ↩ pastes into the previous app, ⌘Y previews, ⎋ closes.
3. AI Memory search does **not** empty the menu bar list.
4. Settings… opens; shortcut recorder works; Accessibility row reflects reality.
5. Pause recording → new copies are not stored; menu bar icon shows the badge.
6. Quit / relaunch → history, pinboards and favorites persist.
7. Edit Widgets → search **Paperclip** → widget shows live clips.

---

## Persistence reminder

User data lives under `~/Library/Application Support/Paperclip/` (`history.json`, `pinboards.json`,
`ai-metadata.json`, `Media/`, plus `.bak` copies made on first load). Do not delete user history during
migrations; `ClipItem` decoding stays backward compatible with v1.0 and v1.2 files.
