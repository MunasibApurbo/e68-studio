# Phase 1: Discover the hardware (read-only)

Goal: know every interface each device exposes and which one carries configuration. Nothing in this phase writes to a device.

## Steps

1. Ask the owner to connect each device **by USB** (then repeat with the dongle and Bluetooth; interfaces differ per link).
2. Run:

   ```bash
   swift Framework/tools/hid-probe.swift            # everything
   swift Framework/tools/hid-probe.swift <name>     # one device
   ```

   Read the output for each interface:
   - `0001:06` keyboard, `0001:02` mouse, `000C:01` media keys: the normal input interfaces.
   - `FF60:61` with 32-byte reports: **QMK/VIA raw HID**. Configuration is well understood.
   - Any other `FFxx` page: a vendor channel. Configuration is probably there, protocol unknown.
3. If there is a VIA interface:

   ```bash
   swift Framework/tools/via-probe.swift <VID> <PID>
   ```

   Record the protocol version, layer count, macro slots and buffer size.
4. For Bluetooth devices, note what `system_profiler SPBluetoothDataType` shows, and whether the Battery Service (`180F`) is present. Bluetooth links usually expose only the input interfaces, not configuration.
5. Look up the matrix size (rows × columns) from the VIA JSON if one exists. Without one, the matrix comes from reading the keymap in phase 3.

## Record in `device-profile.yaml`

For each device and each link: VID, PID, product string, firmware version, every usage page/usage with report sizes, which one is the config channel, and how sure you are (`measured`, `documented`, `guess`).

## Done when

- Every device and link has an entry.
- Each device's config channel is identified, or marked `unknown`, with the evidence.
- `PROGRESS.md` phase 1 is ticked with the probe output pasted or summarised.

## Reference

What this looked like for E68 Studio: the E-68 PRO showed `FF60:61` (VIA), plus `FF1C:92` and `FFEF` vendor pages. The vendor pages were later probed and never answered (`playbooks/protocol-discovery.md`). The G7 mouse showed a 64-byte vendor page `FF01:10` whose protocol was never found.
