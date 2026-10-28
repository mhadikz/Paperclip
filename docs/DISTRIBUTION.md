# Distribution

How to turn the repository into something people can download and trust.

## 1. Identity (done)

| Item | Value |
| --- | --- |
| Bundle ID | `com.mhadikz.Paperclip` (widget `com.mhadikz.Paperclip.Widget`) |
| App group | `group.com.mhadikz.Paperclip` (both entitlements + `WidgetSnapshot.appGroupID`) |
| Copyright | `© 2026 mhadikz` (`NSHumanReadableCopyright`, `LICENSE`, About tab) |
| Links | `ProjectLinks` in `Paperclip/Features/Settings/AboutPreferencesView.swift` → `github.com/mhadikz/Paperclip` (set to `nil` to hide a button) |

The app shipped as "Clipboard" during development. On first launch of a Paperclip build:

- Preferences stored under the earlier identifier `com.local.Clipboard` are copied once
  (`AppSettings.migrateLegacyDefaultsIfNeeded`).
- `~/Library/Application Support/Clipboard/` is renamed to `…/Paperclip/` when it holds a
  `history.json` and the new folder does not exist yet (`AppDataLocation.migrateLegacyFolderIfNeeded`).
  Nothing is copied or deleted, so history, pinboards, media and AI metadata survive unchanged.
- Accessibility and the login item are tied to the bundle identifier, so they have to be granted
  again once. The desktop widget must be re-added.

## 2. Build the release

```bash
./scripts/check.sh
./scripts/test.sh
./scripts/build.sh --release --no-install     # universal arm64 + x86_64, optimized, hardened runtime
./scripts/package.sh                          # build/dist/Paperclip-<v>.zip, .dmg, SHA256SUMS.txt
```

Without a signing identity the bundle is **ad-hoc signed**. That is a valid signature (the app runs,
the widget registers) but Gatekeeper cannot verify the developer, so downloaded copies show
*"cannot be opened because the developer cannot be verified"* once. Users fix it with
**right-click → Open → Open**, or:

```bash
xattr -d com.apple.quarantine /Applications/Paperclip.app
```

Put that sentence in the release notes and the README (already there).

## 3. Publish on Azure

- **Azure Repos / DevOps:** push `main`. `azure-pipelines.yml` type-checks, tests, builds the
  universal bundle and publishes `build/dist` as a pipeline artifact on every run.
- **Releases:** create a tag `v1.3.0`, attach `Paperclip-1.3.0.dmg`, `Paperclip-1.3.0.zip` and
  `SHA256SUMS.txt` (download them from the pipeline artifact or build locally). Copy the version
  section of `CHANGELOG.md` as the release notes.
- Then set `ProjectLinks.repository` / `.issues` to the real URLs and rebuild.

### GitHub: landing page and Releases

- **Landing page:** `site/` is a static page (no build step) published by
  `.github/workflows/pages.yml`. Enable it once under *Settings → Pages → Source: GitHub Actions*.
  Set `REPO` in `site/site.js` to the repository slug; the download button then resolves the latest
  DMG through the Releases API and every other link derives from the same value.
- **Releases:** push a tag to publish.

  ```bash
  git tag v1.3.0 && git push origin v1.3.0
  ```

  `.github/workflows/release.yml` type-checks, tests, builds the universal bundle, packages it and
  creates the GitHub Release with `Paperclip-<v>.dmg`, `Paperclip-<v>.zip`, `SHA256SUMS.txt` and
  release notes that include the right-click → Open instruction.

## 4. Optional: a stable identity for your own Mac (no Apple account needed)

macOS ties the Accessibility grant to the app's code signature. Ad-hoc signatures change on every
build, so Paperclip asks for Accessibility again after each `scripts/build.sh`. A self-signed
code-signing certificate keeps the identity stable:

1. Keychain Access → menu **Keychain Access › Certificate Assistant › Create a Certificate…**
2. Name: `Paperclip Dev`, Identity Type: *Self Signed Root*, Certificate Type: **Code Signing**, create.
3. Build with it:

   ```bash
   SIGN_IDENTITY="Paperclip Dev" ./scripts/build.sh
   ```

   (`security find-identity -v -p codesigning` lists what the name must match.)

This does **not** help downloaded copies on other Macs; Gatekeeper still requires notarization for that.

## 5. Future: Developer ID + notarization

When there is an Apple Developer Program membership ($99/year, developer.apple.com/programs):

1. In Xcode (or developer.apple.com → Certificates) create a **Developer ID Application** certificate
   and install it in the login keychain.
2. Change the app group to the Team-ID form Apple requires for signed apps,
   `<TEAMID>.group.com.mhadikz.Paperclip`, in both `.entitlements` files and
   `WidgetSnapshot.appGroupID`.
3. Store notarization credentials once:
   `xcrun notarytool store-credentials AC_PASSWORD --apple-id <email> --team-id <TEAMID> --password <app-specific-password>`
4. Build, notarize, staple, package:

   ```bash
   SIGN_IDENTITY="Developer ID Application: <Name> (TEAMID)" ./scripts/build.sh --release --no-install
   ./scripts/package.sh
   xcrun notarytool submit build/dist/Paperclip-<v>.zip --keychain-profile AC_PASSWORD --wait
   xcrun stapler staple build/Paperclip.app
   ./scripts/package.sh      # re-package the stapled app
   ```

After that, downloads open without any warning.

## 6. Release checklist

- [ ] `CHANGELOG.md` has the version; `Info.plist` versions bumped (app + widget)
- [ ] `./scripts/test.sh` green; `./scripts/build.sh --release --no-install` green
- [ ] `./scripts/package.sh` produced zip + dmg + checksums
- [ ] Smoke test from `docs/STATUS.md` on a clean user account (right-click → Open once)
- [ ] Tag `v<version>`, publish artifacts + checksums + release notes
- [ ] `ProjectLinks` point at the published repository
