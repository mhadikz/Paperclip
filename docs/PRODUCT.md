# Product vision

## Positioning

```
Traditional Clipboard Manager
            +
      AI Memory
```

The clipboard history is the primary product. AI Memory is an optional intelligence layer over the same history.

**Core idea:** “Everything I copy becomes searchable memory — and it never leaves my Mac.”

The app must remain usable forever without enabling AI.

## Inspiration (not clones)

| App | What we took | What we skipped |
| --- | --- | --- |
| CopyClip | Menu bar, history limits, ignored apps, simple prefs | App Store / network |
| Paste | Visual history, pinboards, stack, search, images/files, hotkey, rich text | iCloud, iOS, subscriptions, team sharing, MCP by default |

## Personas

- Developer / power user who copies commands, URLs, snippets, screenshots
- Privacy-conscious user who does not want clipboard cloud sync
- Someone who wants Paste-like memory without SaaS

## UX principles

1. **Instant paste** — default Paste never waits on AI; the previous app keeps focus
2. **One shortcut away** — `⇧⌘V` by default, yours to change
3. **Keyboard first** — everything in History is reachable without the mouse
4. **Memory ≠ chatbot** — search/retrieve first; smart actions are secondary
5. **Local by default** — no account, no backend, honest permission explanations
6. **Native macOS** — menu bar agent, non-activating panel, Liquid Glass with accessible fallbacks

## Primary surfaces

1. **Menu bar** — recent clips, pause, delete all, settings, quit
2. **History panel** — cards; title menu: Clipboard History | AI Memory | Favorites; preview
3. **Settings** — General, AI Memory, Ignored Apps, Clips, About
4. **Widget** — Desktop and Notification Center; Copy button or open History

## Success criteria

- Copy → appear in history within the 0.35 s poll interval
- Re-paste without leaving keyboard flow (`⌘0`–`⌘9`, or History + `↩`)
- Natural-language find works usefully even when Foundation Models are unavailable (heuristics)
- Disabling AI leaves a complete clipboard manager
- A new user can understand every permission request from the Settings copy alone
