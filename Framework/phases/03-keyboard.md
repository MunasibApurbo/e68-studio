# Phase 3: Keyboard (keymap, macros, lighting)

Goal: read and write the keyboard's configuration safely, with every write verified by reading it back.

Before starting: `playbooks/hardware-safety.md`, and run a full backup (`--backup`) as soon as reading works.

## VIA/QMK keyboards (raw HID `FF60:61`)

Every request is a 32-byte output report; the reply is a 32-byte input report whose first byte echoes the command. Commands you will need:

| ID | Name | Use |
|---|---|---|
| `0x01` | get protocol version | identity; reply bytes 1–2 |
| `0x02` / `0x03` | get / set keyboard value | uptime, layout options, **switch matrix state** (Key Test) |
| `0x05` | set keycode | `layer, row, col, hi, lo` |
| `0x07` / `0x08` / `0x09` | lighting set / get / save | lighting value IDs (see below) |
| `0x0C` / `0x0D` | macro count / buffer size | |
| `0x0E` / `0x0F` | macro buffer get / set | `offset hi, offset lo, length, data…` (max 28 bytes per packet) |
| `0x11` | layer count | |
| `0x12` | keymap buffer get | `offset hi, offset lo, length` → bulk read of all layers |
| `0x14` / `0x15` | encoder get / set | knob actions per layer (if supported) |
| **never** `0x06`, `0x0A`, `0x0B` | keymap reset, EEPROM reset, bootloader jump | not needed; risk losing everything or bricking |

Keymap layout in memory: `layers × rows × cols × 2` bytes, big-endian keycodes. Map matrix positions to physical keys with the VIA JSON's `layouts.keymap` (KLE format).

### Expect the firmware to deviate from QMK

Treat stock QMK behaviour as a hypothesis and **measure each command on the real board**. On the E-68 PRO (firmware 1.02), measured:
- single-key read `0x04` returns junk; bulk write `0x13` is ignored → write with `0x05`, verify with `0x12`;
- macro chunks declared 14–27 bytes long lose their last 14 bytes → always send 28 bytes, zero-padded;
- the published VIA JSON's lighting channel 3 is acknowledged but does nothing; the old `0x80`-series IDs actually drive the LEDs;
- the speed value is stored but ignored by the animation.

Each one cost real debugging time. Write the quirk next to the code (as a `///` comment) and into `device-profile.yaml`. Reference: `Sources/E68Studio/HID/Keyboard/VIA.swift`.

### Keycodes

Build a keycode table (basic HID usages, modifiers, media/consumer, layer functions `MO/TG/TT/LT/MT/OSL/OSM`, macros `0x7700+`). Reference: `Sources/E68Studio/Model/Keyboard/Keycodes.swift`. Vendor boards often have custom codes above `0x7E00` (for example battery display); find them in the VIA JSON's `customKeycodes`.

### Self-tests to add

- keymap read returns `layers × rows × cols` values
- write a key in an unused position, read back, restore the original
- write a macro, read back, restore the original buffer
- lighting set, get, restore
- encode/decode round trips for macros and backups (offline)

## Non-VIA keyboards

1. Check for Vial (`FF60:61` too, plus Vial commands `0xFE`), OpenRGB support, or a community protocol write-up.
2. If none exists, follow `playbooks/protocol-discovery.md`. Do not write to an unknown channel to "see what happens".
3. Ship what you can do through macOS alone (key remapping with an event tap, the key tester, macros typed by the app) and mark the rest as unreachable in `PROGRESS.md`, with the evidence.

## Bluetooth

Bluetooth links rarely carry the config channel. Detect the device (`IOHIDManager` on its Bluetooth PID), read battery through CoreBluetooth (`180F`/`2A19`), and offer the OS-level features. Reference: `HID/Keyboard/BluetoothMonitor.swift`, `HID/Shared/BLEBatteryReader.swift`.

## Done when

All self-tests pass on the real board and the original configuration is intact (compare with the backup).
