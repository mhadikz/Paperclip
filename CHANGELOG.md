# Changelog

All notable changes to Paperclip are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and versions follow SemVer.

## [1.3.0] — 2026-10-26

### Added
- Customizable global shortcut (General → Shortcut) with a built-in recorder; default stays ⇧⌘V.
- Rich-text fidelity: formatted text (bold, links, colors) is kept as an RTF sidecar and restored on paste; "Paste as Plain Text" bypasses it.
- Keyboard-first History: ↑/↓ select, ↩ paste, ⇧↩ plain, ⌘C copy, ⌘⌫ delete, ⌘Y preview, ⌘F search, ⌘1–9 quick paste, ⎋ back/close.
- Full-size clip preview inside History (text, code, images, file lists) with details and memory tags.
- Rename clips, open links in the browser, reveal files in Finder, drag clips out of History into other apps.
- Accessibility status and one-click System Settings link; login-item status; storage usage; "Show in Finder" for the data folder.
- Menu bar icon shows a badge while recording is paused; menu rows show type icons.
- App icon, universal (Apple Silicon + Intel) release builds, zip/DMG packaging, Azure Pipelines and GitHub CI, MIT license.
- 77 fast tests covering capture policies, persistence, search, AI processing, and view-model logic.
- Landing page in `site/` (static, brand palette, light/dark, no third-party requests) published with GitHub Pages, and a tag-triggered Release workflow that attaches the DMG, zip and checksums.

### Changed
- Bundle identifier is now `com.mhadikz.Paperclip` (app group `group.com.mhadikz.Paperclip`). Preferences saved under the old `com.local.Clipboard` identifier are migrated automatically on first launch; history is unaffected.
- History is now a non-activating panel: the app you were working in keeps focus, so "paste into frontmost app" works.
- Copying something already in history bumps the existing clip (keeps its pins, favorites, and tags) instead of creating a duplicate.
- Identical images collapse into one clip (SHA-256). Spreadsheet/table copies are stored as text, not as images.
- Persistence is coalesced and written off the main thread; corrupt files are moved aside instead of being overwritten.
- Memory search runs instantly on heuristics and refines with Apple Intelligence only for natural-language queries.
- Sensitive-content detection has far fewer false positives (file paths, identifiers, UUIDs, hashes, dates) and recognises common API-key formats.
- Pasteboard flags set by password managers (`org.nspasteboard.ConcealedType`, `TransientType`) are honoured.
- Settings layout reorganised; destructive "Clear" removed from the History header (now in the ••• menu).
- Pure logic (classifier, search, sensitive filter, smart actions) moved into Domain; AI reached through protocols.

### Fixed
- Project did not compile with Swift 6.4 Command Line Tools (`@State` macro); `@ViewState` typealias.
- Paste from History sent ⌘V to the app itself instead of the previous app.
- AI backfill could drop queued clips at launch (handler race).
- Preferences opened a second, different window via the SwiftUI Settings scene.
- Pinboards could reference clips that no longer existed after a duplicate copy.
- History cards laid out entire multi-kilobyte clips and decoded full-size images on every scroll.

## [1.2.0] — 2026-09-05
- Desktop / Notification Center widget, Liquid Glass design system, navy/gold palette, Light/Dark/System.

## [1.1.0] — 2026-08
- AI Memory: heuristic + Apple Foundation Models classification, tags, summaries, hybrid search, smart actions.

## [1.0.0] — 2026-08
- Menu-bar clipboard history with pinboards, paste stack, ignored apps, sensitive-content skipping.
