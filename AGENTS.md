# AGENTS.md

Rules for AI agents working on E68 Studio. (`Framework/` is a separate playbook for building apps like this one; its own `templates/AGENTS.md` is for those new repos.)

## Build and check

```bash
swift build                                   # zero warnings
.build/debug/E68Studio --selftest             # PASS/INFO only; live VIA checks run when the E-68 PRO is on USB
./Scripts/build-app.sh                        # dist/E68 Studio.app
BIN="dist/E68 Studio.app/Contents/MacOS/E68Studio"
"$BIN" --render-closeups <dir>                # headless renders; see README for options
```

## Rules

- Check visual work with headless renders. Do not open the app window or run on-screen scripts; it interrupts the owner.
- Hardware: back up (`--backup`) before experiments, verify every write by reading back, never send VIA `0x06`/`0x0A`/`0x0B`. Firmware quirks are documented in `HID/Keyboard/VIA.swift`; keep them there.
- Don't blind-write to the E-68 PRO's `FF1C`/`FFEF` or the G7's `FF01` vendor channels. Per-key RGB and on-board mouse DPI need a capture of the vendor software first.
- If what a stored light point means changes, bump the cache constant `0x5EED_0004` in `PathTracerRenderer.renderLiveFrame`.
- MetalFX: motion vectors exclude the frame's jitter; never reset anti-aliasing history because the camera moved.
- Don't hand the scene to `SCNView` or call `SCNRenderer.prepare(scene)` (about 420 MB and seconds).
- Keep `-e68.live NO` (path-traced reference) working.
- Don't download anything without stating the file, source and size and getting approval.
- Commit in small, named commits. Don't push unless asked.
- The owner wants work delivered, not rounds of questions. Ask only when a decision is theirs.

## Rejected by the owner (never bring back)

- Visible noise, speckle or "rendering in progress", moving or still.
- Background blur and lens blur ("cheap").
- Automatic moonlight or fill light at night ("fake"). Night is lit by the lamp, monitor and keyboard only.
- Pure black shadow under the desk on photographed ground ("cartoon").
- Strong normal-map relief under low light (sandpaper grain).
- Generic scanned plants. The plants are the owner's real pothos, lucky bamboo and a cutting in a jar.
- The sunset lamp, the spotlight and the white adapter on the desk.

History and the full renderer handoff: `Docs/Archive/ANTIGRAVITY_HANDOFF.md`.
