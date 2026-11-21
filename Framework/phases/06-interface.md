# Phase 6: Interface

Goal: every feature reachable in a clear native interface, with permissions explained where they are needed.

## Layout that works for device apps

- **Sidebar sections** per device: Keymap, Lighting, Macros, Profiles, Shortcuts/Snippets, Key Test, Backup, Device for the keyboard; Buttons, DPI, Scroll, More for the mouse.
- **A visual of the device** as the main canvas: click a key to remap it. A 2D canvas drawn from the VIA layout is enough; 3D is phase 7.
- **Menu bar extra** (`MenuBarExtra`) with the few things people change daily: backlight on/off, brightness, a lighting mode, DPI stage, profile.
- **Background mode**: closing the window can keep the menu bar, remaps and profiles running (set the activation policy to `.accessory`).
- **Settings**: appearance, launch at login (`SMAppService.mainApp`), menu bar, background behaviour.

## Permissions

Request each permission at the moment its feature is turned on, not at launch. Explain in one sentence what it is for and what still works without it. After granting Screen Recording, macOS needs the app relaunched; say so. Put the usage strings in `Info.plist` (the build script writes them).

## Writing and design

- Plain words: "Brightness", not "LED luminance level".
- Show device state honestly: connected via what, firmware version, battery, last error.
- Debounce sliders: update the device live at a capped rate, save to EEPROM when the drag ends.
- If the owner's harness has design skills (Claude Code users can add design skills or plugins), load them for this phase.

Reference: `Sources/E68Studio/Views/`.

## Done when

Every feature from the confirmed list has a working control, the menu bar works with the window closed, and permission prompts appear only when a feature needs them.
