# Hardware safety

A keyboard or mouse is cheap to replace but painful to lose. An agent cannot see the device's lights or feel its keys, so it must be careful on the owner's behalf.

## The rules

1. **Back up before the first write.** Implement `--backup <file>` (keymap, macros, lighting, encoder) as soon as reads work, run it, and keep the file in `Backups/` (git-ignored).
2. **Read, write, read back.** Every write is followed by a read of the same value. A write that cannot be verified is not done.
3. **Tests restore what they touch.** Use positions and slots that are unused, and put the original value back even when the test fails (`defer`).
4. **Never send these:** EEPROM reset, keymap reset, bootloader jump (VIA `0x0A`, `0x06`, `0x0B`), firmware update commands, or anything on a vendor channel whose meaning you have not established.
5. **No blind writes to unknown channels.** "Try values and see what happens" can wipe settings or brick a device. See `protocol-discovery.md` for safe ways to learn a protocol.
6. **Rate-limit.** Lighting at frame rate is fine for volatile state; saving to EEPROM is not. Save once, at the end.
7. **Ask before risk.** If a step could change device state in a way you cannot read back, describe it to the owner and get a yes first. Record the answer in `PROGRESS.md`.
8. **One process talks to the device.** Quit the vendor app and the main app before CLI tests, or they will steal each other's replies.

## If something goes wrong

- Restore from the backup with the app's own restore path.
- For QMK/VIA boards, the owner can usually reflash stock firmware (vendor site) by holding Esc while plugging in. Never do this for them.
- Write down what happened in `device-profile.yaml` under `quirks:` so it never happens again.
