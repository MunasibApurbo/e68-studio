# START HERE (instructions for the AI agent)

You are building a native macOS companion app for the owner's own keyboard and mouse. The owner may not be a programmer. Your job is to deliver a working app, not to ask a stream of questions.

## Rules that apply to every phase

1. **Hardware safety first.** Read `playbooks/hardware-safety.md` before you send a single byte to a device. In short: back up before writing, read before you write, read back after you write, restore what you changed in tests, and never send reset, EEPROM-reset or bootloader commands.
2. **Facts live in `device-profile.yaml`.** Every VID/PID, usage page, report size, protocol version and quirk you measure goes there. Code reads its constants from what is recorded there; nothing is guessed.
3. **Every phase ends with proof.** Add checks to `--selftest` and run them, and use headless renders for anything visual. See `playbooks/verification.md`. Do not ask the owner "does it work?" for something you can check yourself.
4. **Keep `PROGRESS.md` current.** Tick items as they pass, with the evidence (command and result). A new session must be able to continue from that file alone.
5. **Ask only for decisions that are the owner's:** which features they want, what something should look like, permission to download something or to try a risky write. Batch your questions; never ask one at a time.
6. **One writer per area.** If several agents or tools work in parallel, give each its own folder (`HID/`, `Scene/`, `Views/`…) and never let two edit the same files.
7. **Record what the owner rejects** in `AGENTS.md` under "Rejected" with their words, and never bring it back.
8. **No network code, no analytics, no telemetry** unless the owner asks.

## Phase order

| Phase | File | Done when |
|---|---|---|
| 0 | `phases/00-interview.md` | `device-profile.yaml` and the feature list are written and the owner has confirmed the feature list |
| 1 | `phases/01-discover.md` | every device and interface is recorded; the configuration channel of each device is identified or marked unknown |
| 2 | `phases/02-skeleton.md` | the app builds, launches, finds the devices, and `--selftest` passes |
| 3 | `phases/03-keyboard.md` | keymap, macros and lighting round-trip on the real keyboard (or are marked unreachable with evidence) |
| 4 | `phases/04-mouse.md` | pointer speed, buttons and scroll work through macOS, with tests for the pure logic |
| 5 | `phases/05-lighting-sync.md` | music, screen and wallpaper modes drive the keyboard without flooding it |
| 6 | `phases/06-interface.md` | every feature has a screen, a menu bar entry where it makes sense, and clear permission prompts |
| 7 | `phases/07-3d-desk.md` | optional; only if the owner asked for it |
| 8 | `phases/08-ship.md` | `dist/` contains a signed app and a zip; README, licence and credits are written |

Work in this order. Phases 3, 4 and 5 can run in parallel in separate sessions once phase 2 is done.

## Setting up the repository (do this first)

```bash
cp Framework/templates/AGENTS.md AGENTS.md
cp Framework/templates/PROGRESS.md PROGRESS.md
cp Framework/templates/device-profile.yaml device-profile.yaml
git init && git add -A && git commit -m "Start from Device Studio Framework"
```

Then open `phases/00-interview.md`.

## The reference implementation

E68 Studio, in the parent folder of this framework (or wherever the owner found it), solved every phase for a Furycube E-68 PRO (VIA) and an MCHOSE G7 mouse. When a phase says "see `HID/Keyboard/VIA.swift`", read that file for a working, commented example. Copy patterns, not constants: your device's IDs, matrix size and quirks will differ.

## When you get stuck

- Protocol unknown: `playbooks/protocol-discovery.md`. Do not blind-write to vendor channels.
- Something visual that you can't judge: render it headlessly and look at the image yourself.
- Ending a session with work in progress: fill in `templates/HANDOFF.md` as `HANDOFF.md` in the repo root.
