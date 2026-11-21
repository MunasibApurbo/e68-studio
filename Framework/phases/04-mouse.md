# Phase 4: Mouse

Goal: useful mouse features for **any** mouse, done through macOS rather than the mouse's firmware.

Most gaming mice keep DPI and button maps in an undocumented vendor protocol. Rather than wait for that, do everything macOS allows; it works the same for every brand. If the vendor protocol is later found (`playbooks/protocol-discovery.md`), add it as an extra.

## Pointer speed and DPI stages

macOS lets you set per-device properties on HID event services (private but long-stable API in `IOKit`):

- `HIDPointerResolution`: the device's reported DPI as 16.16 fixed point; lowering it makes the pointer faster. This is how "DPI stages" work without firmware access.
- `HIDPointerAcceleration` / `HIDMouseAcceleration`: the acceleration curve. Some devices name the key in `HIDPointerAccelerationType`, so read that first and write the key it names.

Find the service whose `Product`/`VendorID`/`ProductID` match the mouse, then `IOHIDServiceClientSetProperty`. Reference: `Sources/E68Studio/Store/MouseStore+HID.swift`. Settings revert when the mouse reconnects, so reapply on reconnect.

## Buttons, gestures, scroll

A `CGEventTap` at `.cghidEventTap` sees every mouse event before apps do. With it you can:
- remap buttons 3–5+ to keys, shortcuts, text, or app actions;
- implement "hold side button and move" gestures (Mission Control, desktops);
- scale and reverse scrolling per device (keep a fractional accumulator so slow speeds don't drop events);
- debounce chattering switches (ignore a down within N ms of the last up on the same button);
- measure polling rate from event timestamps.

Event taps need **Accessibility** permission, attached to the signed `.app`. Reference: `Sources/E68Studio/HID/Mouse/MouseRemapper.swift`.

Keep the tap callback fast and allocation-free; if it takes too long, macOS disables the tap (`tapDisabledByTimeout`), so handle that event by re-enabling it.

## Self-tests (pure logic, offline)

Scroll accumulator at several multipliers, click-count tracker (single/double/triple, timeout, distance), debounce, DPI ↔ resolution conversion bounds, Codable round trips of the mouse settings. E68 Studio has all of these in `SelfTest.swift`.

## Done when

Pointer speed changes are visible immediately, button remaps and scroll scaling work in any app, and the offline tests pass.
