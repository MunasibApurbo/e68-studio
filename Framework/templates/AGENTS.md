# AGENTS.md

Rules for any AI agent working in this repository. Keep this file short and current.

## Project

A native macOS companion app for the owner's keyboard and mouse, built with the Device Studio Framework (`Framework/START.md`). Hardware facts: `device-profile.yaml`. Progress: `PROGRESS.md`.

## Build and check

```bash
swift build                         # must have zero warnings
.build/debug/<App> --selftest       # must print only PASS/INFO lines
./Scripts/build-app.sh              # dist/<App>.app
```

## Rules

- Read `Framework/playbooks/hardware-safety.md` before sending anything to a device. Back up first, verify every write by reading it back, restore what tests change, never send reset/EEPROM-reset/bootloader commands.
- Constants come from `device-profile.yaml`, measured on the real device. Document firmware quirks next to the code with `///`.
- Verify your own work with `--selftest` and headless renders. Don't open the app window on the owner's screen to check something.
- One agent edits a folder at a time.
- Commit at the end of each phase. Don't push unless the owner asks.
- Don't download anything without saying what, from where, and how big, and getting a yes.
- No network code or analytics unless the owner asks.
- Ask only for decisions that are the owner's, batched in one message.

## Rejected (the owner said no; never bring back)

- (none yet)
