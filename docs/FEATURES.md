# Feature inventory

Complete list of user-facing and engineering features as of v1.3.0.

## Menu bar

| Feature | Status | Notes |
| --- | --- | --- |
| Paperclip status item | Done | Template SF Symbol; badge (`paperclip.badge.ellipsis`) while recording is paused |
| Open Clipboard History | Done | Shows the configured shortcut |
| Recent clips list | Done | Unfiltered by History search; type icon per row |
| Shortcuts `⌘0`–`⌘9` | Done | First ten menu items |
| Paste stack actions | Done | When stack non-empty |
| Pause / Resume recording | Done | Toggles `recordHistory` |
| Delete All History… | Done | Keeps pinned pinboard items; confirms |
| Settings… / Quit | Done | `⌘,` / `⌘Q` |

## History panel

| Feature | Status | Notes |
| --- | --- | --- |
| Non-activating floating panel | Done | Previous app keeps focus; opens on the screen under the mouse; remembers size; hides when it loses key |
| Modes: Clipboard / AI Memory / Favorites | Done | Title menu |
| Search field | Done | `⌘F` focuses; clear button; Esc clears before closing |
| Keyboard navigation | Done | `↑/↓` select, `↩` paste, `⇧↩` paste plain, `⌘C` copy, `⌘⌫` delete, `⌘Y` preview, `⌘1–9` quick paste, `⇧⌘N` new pinboard, `⎋` back/close |
| Cards | Done | Type badge, source app, relative time, favorite star, pinboard badges, bounded excerpt, thumbnail for images |
| Preview | Done | Full text/code, full-size image, file list with Reveal, link with Open; details (size, formatting, pinboards); memory tags |
| Context menu | Done | Paste, Paste as Plain Text, Copy, Preview, Open Link, Reveal in Finder, Favorite, Pin to…, Add to Paste Stack, Rename…, Delete |
| Drag out | Done | Text, URL, file URL, or image to other apps |
| Pinboards | Done | ••• › Pinboard; chips with Rename/Delete; Manage Pinboards sheet |
| Type filter | Done | ••• › Show |
| Paused indicator | Done | Chip in the header |
| Footer hints | Done | Reflects whether ↩ pastes or only copies |
| Hide from screen sharing | Done | `sharingType = .none` |

## Capture

| Feature | Status | Notes |
| --- | --- | --- |
| Text / links / images / files | Done | Links inferred from a single http(s) URL |
| Rich text sidecar | Done | RTF ≤ 512 KB, toggle in Settings |
| OCR on images | Done | Vision, off-main |
| Duplicate bump | Done | Same content keeps id, pins, favorites, metadata; moves to top |
| Image dedupe | Done | SHA-256 of PNG |
| Text vs image priority | Done | Text wins unless the text is just a URL (browser "Copy Image") |
| Concealed / transient types | Done | `org.nspasteboard.*`, 1Password, etc. |
| Sensitive skip / redact / store-without-AI | Done | Policies in Settings; detector covers keys, JWTs, markers, known prefixes, card runs, opaque tokens |
| Ignored apps | Done | Bundle ID set |
| Size limits | Done | 1,000,000 characters of text; larger copies are left on the system clipboard |
| Self-write suppression | Done | Monitor change-count sync |

## Paste

| Feature | Status | Notes |
| --- | --- | --- |
| Copy to pasteboard | Done | Text + RTF, URL type for links, PNG + TIFF for images, file URLs |
| Paste into frontmost app | Done | ⌘V via CGEvent after 120 ms; requires Accessibility; one-time prompt |
| Paste as plain text | Done | |
| Paste transformed AI output | Done | Not stored as history |
| Paste stack FIFO | Done | In-memory |

## Pinboards & favorites

| Feature | Status | Notes |
| --- | --- | --- |
| Create / rename / delete / color | Done | Six legible colors |
| Pin / unpin | Done | UUID refs; cascade on delete |
| Favorites | Done | `AIMemoryMetadata.isFavorite`; survive processing |
| Never trimmed | Done | Pinned + favorites in `keepForever` |

## AI Memory

| Feature | Status | Notes |
| --- | --- | --- |
| Categories, tags, summaries | Done | Heuristics always; Apple FM when available |
| Two-phase search | Done | Instant keyword/cue pass; model refinement for ≥3-word queries |
| Timeline / favorites / related | Done | |
| Detail pane + smart actions | Done | Contextual; Format JSON offline; progress per action; dismissable output |
| Reprocess / clear | Done | Shows queue size |
| Provider abstraction | Done | `LanguageModelProvider`, `AIMemoryServicing` |

## Settings

| Tab | Contents |
| --- | --- |
| General | Shortcut recorder; pasting (toggle, Accessibility status/button, rich text); history limits (stepper), record, confirm; startup (login item status); appearance (theme, glass tint); privacy; storage usage + Show in Finder |
| AI Memory | Feature toggles; Apple Intelligence status; sensitive policy with explanation; maintenance |
| Ignored Apps | Installed app checklist with filter |
| Clips | Filterable list, favorite/app/time columns, delete selected / delete all |
| About | App icon, version/build, principles, links (when configured), data folder |

## Appearance

| Feature | Status | Notes |
| --- | --- | --- |
| Design tokens / palette | Done | `AppTheme`, `AppPalette` (midnight/navy/gold/white) |
| Light / Dark / System | Done | |
| Liquid Glass | Done | macOS 26; material fallback on 14–15; opaque surfaces with Reduce Transparency |
| App icon | Done | Generated by `scripts/make-icon.sh` |
| Widget | Done | Small/medium/large, relative timestamps, Copy button |

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⇧⌘V` (customizable) | Toggle History |
| `↑` / `↓` | Move selection |
| `↩` / `⇧↩` | Paste / paste as plain text |
| `⌘C` | Copy selected clip |
| `⌘Y` | Preview selected clip |
| `⌘⌫` | Delete selected clip |
| `⌘F` | Focus search |
| `⌘1`–`⌘9` | Quick paste from History; `⌘0`–`⌘9` from the menu |
| `⇧⌘N` | New pinboard |
| `⌘[` | Back from preview/detail |
| `⎋` | Close preview → clear search → close panel |
| `⌘,` / `⌘Q` | Settings / Quit (menu) |

## Non-features (explicit)

- iCloud / Universal Clipboard replacement, iOS app, shared pinboards
- Default cloud LLM, subscriptions, telemetry of clipboard bodies
