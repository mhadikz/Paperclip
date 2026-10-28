# Security Policy

Paperclip handles some of the most sensitive data on a Mac. Please report vulnerabilities
privately before disclosing them.

## Reporting

Open a private security advisory on the repository, or email the maintainers (address in the
repository profile). Include steps to reproduce and the macOS version. You will get an
acknowledgement within a few days.

## What counts

- Clipboard content leaving the Mac through any path
- Secrets written to logs, crash reports, or the widget snapshot
- Bypasses of the sensitive-content filter that cause secrets to be stored when the policy says not to
- Privilege or permission misuse (Accessibility, login items, URL scheme)

## Design notes

- All data lives in `~/Library/Application Support/Paperclip/` and the app group container.
- The `paperclip://` URL scheme only opens History or re-copies a clip by UUID; it cannot read or exfiltrate data.
- Pasteboard types `org.nspasteboard.ConcealedType` / `TransientType` are always honoured.
- Logging uses `OSLog` with public, content-free messages only.

See [docs/PRIVACY_SECURITY.md](docs/PRIVACY_SECURITY.md) for the full model.
