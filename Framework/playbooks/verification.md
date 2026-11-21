# Verification: how the agent proves its work

The owner should not have to test every change. Give the app ways to check itself, and use them after every change.

## `--selftest`

One command that prints `PASS`/`FAIL` lines and exits non-zero on failure.

- **Offline checks** (always run): codecs (macros, backups), layout integrity (unique positions, key count), Codable round trips including old saved formats, clamping of out-of-range values, pure engines (music light engine, scroll accumulator, click tracker, debounce).
- **Live checks** (run when hardware is connected): identity, layer count, keymap read, key write/verify/restore, macro write/verify/restore, lighting set/get/restore, matrix state read.
- Print an `INFO` line, not a failure, when hardware is absent, so the test also runs on machines without the device.

Run it after every change that touches `Model/`, `HID/` or `Store/`.

## Headless renders

For anything visual (3D scene, generated textures, icons), add CLI modes that render to PNG offscreen with fixed camera poses. After a change: render, open the image, compare with the reference photos and with the previous render. Do not open the app window on the owner's screen to check visuals; it interrupts them.

## Builds

`swift build` with zero warnings, and `swift build -c release` before shipping. Treat a new warning as a failure.

## What only the owner can check

Some things need eyes and hands: how the physical keyboard's LEDs look, whether a remap feels right, on-screen frame rate at their window size. Collect these in `PROGRESS.md` under "For the owner to check" and ask about them together, once, at the end of a phase.
