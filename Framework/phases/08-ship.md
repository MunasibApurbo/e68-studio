# Phase 8: Ship

Goal: an app other people can download and open, and a repository other people can build.

## The app

1. `Scripts/build-app.sh` builds release, assembles `dist/<App>.app` (icon, resources, `Info.plist` with every usage description), and signs it.
2. Entitlements for the Hardened Runtime: `com.apple.security.device.audio-input` if you use the audio tap; no sandbox (raw HID needs it off). Reference: `Scripts/E68Studio.entitlements`.
3. **Just for the owner:** sign with a local self-signed identity (create "<App>Local" in Keychain Access → Certificate Assistant) so permissions survive rebuilds.
4. **For others:** needs an Apple Developer ID (paid account). Then `Scripts/notarize-app.sh` signs with the runtime and timestamp, submits to the notary service, staples, verifies with `spctl`, and writes a `.dmg` or `.zip` to `dist/`. The agent cannot do this step without the owner's credentials; prepare the script and give the owner the exact commands.
5. Without a Developer ID, share the zip with instructions: right-click → Open, or `xattr -dr com.apple.quarantine <App>.app`.

## The repository

- `README.md`: what it does, rendered screenshots, supported hardware with IDs, permissions table, build steps, CLI modes, layout, licence.
- `LICENSE` (MIT is common) and `Resources/ASSET_CREDITS.md` listing every bundled third-party file with its licence.
- Trademark note: device brands belong to their owners; not affiliated.
- `.gitignore`: `.build/`, `dist/`, `*.app/`, `.DS_Store`, device backups, raw reference photos.
- Check history before publishing: personal photos (EXIF location), device backups (Bluetooth addresses), names and emails in commits. If history holds anything private, publish from a fresh single-commit branch.
- No secrets anywhere: `git grep -nE "password|token|secret|BEGIN .*KEY"`.

## Done when

`dist/` has a signed app and zip, a fresh clone builds with `swift build` and passes `--selftest` offline, and the README matches what the app does.
