# Discovering an undocumented protocol

Most non-VIA keyboards and almost all gaming mice configure themselves over a vendor HID channel (`FFxx` usage page) with a protocol nobody published. Here is how to approach one, in order of safety.

## 1. Look for prior work (free, safe)

- OpenRGB's supported-devices list and source (`Controllers/*`): many RGB protocols are already decoded.
- Linux kernel drivers and `libratbag` / Piper for mice.
- GitHub search for the VID:PID in hex (`"320f" "5055"`).
- The vendor's web configurator, if it uses WebHID: its JavaScript contains the protocol, usually minified. Searching a multi-megabyte bundle is slow and often inconclusive; prefer step 2.

## 2. Watch the vendor's own software (safe, most reliable)

- **WebHID configurators:** open `chrome://device-log` while changing one setting at a time; every report sent is logged.
- **Windows driver software:** Wireshark + USBPcap on a Windows PC or VM with USB passthrough. Change one setting, capture, diff.
- **macOS vendor apps:** run the app and a USB capture (`tcpdump -i XHC20` on older macOS, or a hardware USB analyser).

Change exactly one thing per capture. Record each packet with what it did in `device-profile.yaml`.

## 3. Read-only probing (careful)

Only "get"-shaped requests: feature report reads (`IOHIDDeviceGetReport` with `kIOHIDReportTypeFeature`), or commands that prior work shows to be reads. Log every reply. No writes.

## 4. Writes (only with the owner's yes)

Only replay packets captured from the vendor software in step 2, after a backup, one at a time, verifying each.

## When to stop

If an hour of steps 1 and 3 found nothing, stop and write down where you got to. Ask the owner whether they can run the vendor software somewhere you can capture it. E68 Studio stopped here twice:

- **E-68 PRO per-key RGB:** the `FF1C` interface looked like OpenRGB's EVision layout, but neither EVision v1 nor v2 commands got any reply. Needs a capture of FuryCube's Windows driver.
- **MCHOSE G7 on-board DPI:** the 64-byte `FF01` channel matched no protocol family in the vendor's web bundle. Needs a `chrome://device-log` capture while the web driver changes DPI.

Both features were delivered another way (VIA's whole-board lighting; macOS-side DPI), and the open questions were written down so nobody repeats the dead ends.
