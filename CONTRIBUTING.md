# Contributing

Thanks for helping make Paperclip better. This is a small, opinionated macOS utility: fast
clipboard history first, optional on-device intelligence second, privacy always.

## Ground rules

- **Local only.** No network calls that carry clipboard content. No analytics. No accounts.
- **Capture stays instant.** Nothing on the capture path may wait for a model, the disk, or the network.
- **AI is optional.** Every feature must work with AI off and without Apple Intelligence.
- **No clipboard content in logs**, test fixtures that look like real secrets, or screenshots in issues.

Read [AGENTS.md](AGENTS.md) for the architecture rules and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the layer map before changing structure.

## Setup

```bash
git clone <repo-url>
cd Paperclip
./scripts/check.sh      # type-check (≈1 min)
./scripts/test.sh       # 70+ tests, no XCTest or Xcode required
./scripts/build.sh      # build + install to ~/Applications
```

Only the Command Line Tools are required. If you prefer Xcode, open `Paperclip.xcodeproj`; after
adding or moving files, run `python3 scripts/generate-xcodeproj.py` so the project stays in sync.

One quirk: write `@ViewState` instead of `@State` in SwiftUI views. The macOS 26+ SDK turns
`@State` into a macro whose plugin only ships with Xcode; the typealias keeps the Command Line
Tools build working (see `Paperclip/Core/Compat/ViewState.swift`).

## Making changes

1. Branch from `main`.
2. Keep the dependency direction: Features → Domain ← Data, composed in `App/DependencyContainer.swift`.
3. Add or update tests in `PaperclipTests/` for behavior you change. The suite runs in under a second.
4. Run `./scripts/test.sh` and `./scripts/build.sh`, then do the smoke checklist in [docs/STATUS.md](docs/STATUS.md).
5. Update the docs that describe the behavior you touched (table in AGENTS.md).
6. Open a pull request with a short description of *why*.

## Reporting bugs

Please include macOS version, whether Apple Intelligence is on, and steps to reproduce.
Never paste real clipboard contents, tokens, or screenshots of private data into an issue.

## Security

See [SECURITY.md](SECURITY.md).
