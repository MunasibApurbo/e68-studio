# Task: extend E68 Studio with the next wave of features

You are working on **E68 Studio**, a native macOS app (SwiftUI + AppKit + SceneKit, Swift Package, macOS 26 / Liquid Glass) that configures an **E68 68% wireless mechanical keyboard with a rotary knob**. The keyboard runs FuryCube firmware and speaks the **VIA raw-HID protocol** over USB. The project lives in `~/Desktop/Keyboard App`.

Read this whole brief before writing code. Ship working features, not stubs. The user wants finished builds, not a stream of clarifying questions: make sensible decisions yourself and note them in the final report.

---

## 0. Ground rules

1. **Start with version control.** The folder is not a git repository yet. Run `git init`, commit the current state as "Baseline before feature wave", and then commit after each feature, one feature per commit. If something breaks you can roll back.
2. **Read before you change.** Read every file in `Sources/E68Studio/` before you edit any of them (about 5,200 lines). Match the existing style: small focused types, `@EnvironmentObject KeyboardStore`, `@ViewState` (defined in `Views/ViewState.swift`), the glass components in `Views/GlassKit.swift`, the adaptive colours in `KeyboardCanvas.swift`, sentence-case UI copy, and doc comments that explain *why*.
3. **Building:**
   - Dev build: `swift build` from the project root.
   - Release `.app`: `./Scripts/build-app.sh`, which writes `E68 Studio.app` to the project root and ad-hoc signs it.
   - The build must finish with **zero warnings and zero errors** before you call a feature done.
   - No Xcode project, no third-party packages, and no SPM dependencies. Only Apple frameworks (SwiftUI, AppKit, SceneKit, IOKit, Combine, ServiceManagement, Charts and so on are fine).
4. **Never brick the keyboard.** Every write to the device goes through existing helpers in `KeyboardStore` and `HID/VIA.swift` (`applyKeymap`, `assign`, `writeMacros`, the lighting pump). Do not send unknown VIA command IDs. Do not touch EEPROM reset (`0x0A`/bootloader) commands. Batch writes and show progress through `store.busy`.
5. **Don't break what works.** Today's features must keep working exactly as before: the Test tab key tester, the 3D scene, remapping on every layer including the knob, Lighting, Macros, the Shortcuts list, Backup/Restore/Factory reset, and Device info.
6. **Privacy.** Anything that watches typing outside the app must be opt-in and off by default. It stores **counts only, never characters or sequences**, keeps everything local, and can be wiped with one button.

---

## 1. How the app works today (verify this yourself)

| Area | File(s) | Notes |
|---|---|---|
| App entry | `App.swift` | SwiftUI `App`, single window |
| Central state | `Model/KeyboardStore.swift` | `ObservableObject`: connection state, `keymap: [[UInt16]]` (layers × 128 cells), `activeLayer`, `selection: Slot?`, `macros`, `macroNames`, `lighting: LightingState`, test state (`pressed`, `tested`, `flashing`), `toast`, `busy`. Key methods: `reload()`, `assign(_:layer:slot:)`, `applyKeymap(_:layers:label:)`, `restoreFactoryKeymap`, `writeMacros`, `notify`. Tabs come from `StudioSection` (`test, light, macros, more`). The `Backup` struct is Codable, format `"e68-studio-backup"`, version 1. |
| VIA protocol | `HID/VIA.swift`, `HID/HIDTransport.swift` | Commands already used: `0x01` protocol version, `0x02` keyboard value (matrix state), `0x05` set keycode, `0x07/0x08/0x09` lighting set/get/save, `0x0C–0x10` macros, `0x11` layer count, `0x12` keymap buffer. The matrix is 8 rows × 16 cols. Lighting values: brightness `0x80`, effect `0x81`, speed `0x82`, colour `0x83` (hue/sat). |
| Layout | `Model/Layout.swift` | `Slot` = physical position. 67 switches plus the **knob as three matrix slots**: `knobCCW` (r7c0), `knobPress` (r1c14), `knobCW` (r7c1). So knob remapping already works through the normal keymap; don't rebuild it. |
| Keycodes | `Model/Keycodes.swift` | `Keycodes.def(for:)` describes any 16-bit code. It already decodes modifier combos `0x0100–0x1FFF`, layer-tap `0x4000–0x4FFF` (`LT`), tap-toggle `0x5800–0x581F` (`TT`), mod-tap `0x6000–0x7FFF` (`MT`), macros at `macroBase`, and FuryCube custom codes at `customBase = 0x5F80` (BT 1–3, 2.4G, Win Lock, scan delay, battery display). |
| Lighting | `Model/Lighting.swift`, `Views/LightingView.swift` | `LightingCatalog.effects` (19 firmware modes), 9 brightness levels, 3 speed levels, hue/sat swatches. Lighting is board-wide; **there is no per-key RGB**. |
| Macros | `Model/Macro.swift`, `Views/MacrosView.swift` | `MacroCodec` encodes into the VIA macro buffer. `MacrosView.swift:386` has a searchable keycode picker you should reuse. |
| Key test | `Views/ToolViews.swift` (`KeyEventTap`, `TestHUD`) | Local and global `NSEvent` monitors map Mac keycodes to HID usages through `MacKeyMap.usage`. Media keys come from `.systemDefined` subtype 8. |
| 3D scene | `Scene/KeyboardScene.swift`, `Scene/SceneView.swift` | SceneKit model with legends, key press animation and knob turning. `SceneView.legends(for:)` feeds legends to it. |
| Diagnostics | `Diagnostics.swift` | Logging and debug helpers. |

---

## 2. Features to build (in this order)

For each feature: implement it, build with zero warnings, test it by hand against the checklist, then commit.

### F1. Profiles and per-app switching (highest priority)
- **Model:** a `Profile` (Codable, `Identifiable`) holding name, SF Symbol, keymap (all layers), lighting, and optionally macros plus macro names. Store profiles as JSON in `~/Library/Application Support/E68 Studio/profiles/`. Reuse the existing `Backup` payload shape so a profile file and a backup file can be converted into each other.
- **UI:** a new **Profiles** tab in `StudioSection` (symbol `person.crop.rectangle.stack`), placed before "More". From the tab you can:
  - create a profile from the current board
  - apply, rename, duplicate, delete, export and import profiles
  - see a diff summary against the board ("12 keys, lighting differs"), reusing the logic in `BackupView.differenceSummary`.
- **Per-app rules:** a list of "when *App* is frontmost → apply *Profile*", plus a default profile. Pick apps with `NSOpenPanel` limited to `.app` bundles, and store bundle IDs.
  - Watch `NSWorkspace.shared.notificationCenter` `didActivateApplicationNotification`.
  - Debounce by 400 ms, and do nothing if the profile is already active.
  - Apply with `applyKeymap(..., label:)` so only the **changed cells** are written. This matters: a full 3-layer rewrite is slow over HID.
- A global on/off toggle for auto-switching, plus a toast when a switch happens ("Switched to Xcode profile").
- **Edge cases:** keyboard disconnected (queue the profile and apply it on reconnect), a write already in progress (cancel and retry the latest one), the user editing keys while a rule fires (don't switch while `inStudio` editing is active and `selection != nil`).

### F2. Advanced key builder (LT / MT / TT / MO / TG / OSL / OSM)
- Check what the current picker can produce. If you can't build layer-tap or mod-tap codes from the UI today, add a **"Hold behaviour"** section to the key picker. The user chooses the tap key, then the hold action (a layer 0–3, or a modifier set with left/right), and you encode it:
  - `LT(layer, kc) = 0x4000 | (layer << 8) | kc`. Basic keycodes only, `kc ≤ 0xFF`.
  - `MT(mods, kc) = 0x6000 | (mods << 8) | kc`, where mods is the 5-bit QMK set (`0x01` Ctrl, `0x02` Shift, `0x04` Alt, `0x08` GUI, `0x10` = right-hand side).
  - `TT(layer) = 0x5800 | layer`.
  - `MO`, `TG`, `TO`, `DF`, `OSL` and `OSM` use the **QMK keycode ranges for the protocol version the board reports** (`store.protocolVersion`). VIA protocol 9+ uses the newer QMK ranges (`QK_MOMENTARY 0x5220`, `QK_TOGGLE_LAYER 0x5260`, `QK_TO 0x5200`, `QK_DEF_LAYER 0x5240`, `QK_ONE_SHOT_LAYER 0x5280`, `QK_ONE_SHOT_MOD 0x52A0`). Older versions use the legacy ranges. Look up the exact values in QMK's `keycodes.h` / `quantum_keycodes_legacy.h` for each version and add a decoder for every new range to `Keycodes.def(for:)`.
- Add presets: "Caps Lock → Esc on tap, Ctrl on hold", "Space → Space on tap, layer 1 on hold", "Right Shift → / on tap, Shift on hold".
- Note in the UI that tap-dance and combos need firmware support and aren't available.

### F3. Menu bar extra
- `MenuBarExtra` (window style) showing connection status, battery shortcut hint, brightness slider, effect picker, colour swatches, a lighting on/off toggle, the active profile picker (from F1), auto-switching on/off, and "Open E68 Studio".
- Add a setting "Keep running in menu bar when window closes" (`NSApp.setActivationPolicy(.accessory)` when the window closes, `.regular` when it reopens).
- Add a "Launch at login" toggle with `SMAppService.mainApp`.

### F4. Undo / redo and change history
- Wire keymap edits, lighting changes and macro edits into an `UndoManager` so ⌘Z / ⇧⌘Z work, and the Edit menu shows "Undo Remap Caps Lock" and so on.
- Add a "Changes this session" popover listing every change with its time, with "Revert to here".
- Group a full profile apply or restore into one undo step.

### F5. Diagnostics: chatter detector, switch health, latency
Build these into the **Test** tab as a segmented sub-mode: Test · Chatter · Report.
- **Chatter:** record press timestamps per slot. If a key has a second down within a threshold (default 30 ms, adjustable from 5 to 80 ms) without a matching sustained release, flag it. Show a count per key on the 2D canvas or 3D scene (red tint), plus a list. Suggest the firmware scan-delay key (`customBase + 5`) as the fix.
- **Matrix source:** where possible, prefer the hardware matrix poll (`VIA.matrixState()`, command `0x02`) over Mac events, because it bypasses macOS key repeat. Measure how fast it polls and fall back to events if polling is too slow over the current link.
- **Report:** per key, show tested / untested / chatter / stuck (held for more than 5 s with no release). Export as PNG (a render of the canvas) and as JSON.
- **Latency:** show the spread of intervals between events and the polling rate seen per connection type (USB, 2.4G, BT). Label it clearly as an estimate.

### F6. Typing stats and heatmap (opt-in)
- Off by default. Turning it on explains that it needs **Input Monitoring**, deep-links to System Settings (`x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`), and checks access with `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`.
- Use a listen-only `CGEventTap` (or a global `NSEvent` monitor for keyDown) that **only increments a per-HID-usage counter** and a per-minute keystroke count. Never store characters, order, or which app was frontmost.
- Persist daily buckets as JSON in Application Support.
- **UI:** a heatmap overlay on the 2D canvas and the 3D scene (use existing legend and colour plumbing, adding a heat colour per key), with ranges for today, 7 days, 30 days and all time. Show a Swift Charts bar chart of keys per day, the top 10 keys, estimated WPM (keystrokes ÷ 5 per active minute), and modifier usage.
- Add a "Delete all typing data" button.
- Bonus: suggest remaps, e.g. "You press Caps Lock 0 times; make it Esc/Ctrl?", linking to the F2 preset.

### F7. Typing test
- A sheet in the Test tab with a 15 / 30 / 60 s test using a bundled list of about 1,000 common English words (put it in `Sources/E68Studio/Resources/words.txt` and add `resources: [.process("Resources")]` to the target in `Package.swift`). Alternatively, keep the list as a Swift array to avoid resource plumbing.
- Show live WPM, accuracy and errors highlighted inline. Keys light up on the 3D scene as you type, using the existing `pressed` set.
- Keep a local history of results.

### F8. Layer HUD
- A borderless, non-activating `NSPanel` that floats over everything and shows a small map of the active layer's legends for about 1.2 s. It appears when the layer changes on the hardware (detect this by polling the matrix for MO/TT/LT key holds, or by watching Fn) and when a profile switches.
- Add an on/off setting.

### F9. Lighting scenes and schedule
- Named lighting presets (effect, brightness, speed, hue, sat) with one-click apply in the Light tab and the menu bar.
- Schedule rules: by time of day ("21:00 → Night"), plus "turn lighting off when the Mac sleeps or the screen locks, restore on wake" (`NSWorkspace` `willSleepNotification` / `didWakeNotification`, `com.apple.screenIsLocked` distributed notifications).
- Remember that writes go through the existing lighting pump. Call `saveLighting` only for presets the user applies by hand, so scheduled changes don't wear out EEPROM.

### F10. Shareable themes
- Export and import a single `.e68theme` file (UTType declared in the `Info.plist` that `build-app.sh` generates). It holds a profile or a lighting preset, includes a preview thumbnail, and can be opened by double-clicking (`onOpenURL` / `NSApplicationDelegate application(_:open:)`).
- Validate on import: product match, layer count, keycodes within known ranges. Show a diff before applying.

### F11. Command palette (⌘K)
- A fuzzy-search palette over every keycode (`Keycodes.known`), macro, profile, lighting effect and preset, and action (Backup, Restore, Switch tab, Toggle lighting).
- Choosing a keycode while a key is selected assigns it.
- Keyboard-only: arrow keys, Return, Esc.

### F12. Remaps that launch apps or URLs (host-side)
- Host-side "app actions": the user binds a spare macro slot or an F13–F24 keycode to "Open app", "Open URL" or "Run Shortcut (Shortcuts.app)".
- The app listens for that keycode through a global monitor (needs Input Monitoring, shared with F6's permission flow) and runs the action. Without the app running, the key just sends F13–F24, so it's harmless.
- Make clear in the UI that this only works while E68 Studio is running (menu bar mode from F3).

---

## 3. Cross-cutting requirements
- **Persistence:** one `SettingsStore` (or `@AppStorage` where trivial) for preferences. Bump `Backup.version` to 2 if you add fields, and keep reading version 1.
- **Backups:** extend Backup/Restore to optionally include profiles, rules, lighting presets and app actions.
- **Accessibility:** every control has a label, full keyboard navigation works, `accessibilityReduceMotion` is respected in the HUD and scene effects, and contrast holds in both light and dark appearance.
- **Performance:** keep HID traffic minimal (diff before writing). Never block the main thread on HID; follow the existing `async` patterns. Keep the app's idle CPU under 1% when the window is hidden.
- **Concurrency:** Swift 6 strict concurrency friendly; `@MainActor` on UI state.
- **No dead code, no TODO stubs, no placeholder screens.** If you can't finish a feature properly, leave it out completely and explain why in the report.

---

## 4. Definition of done
For every feature:
- [ ] `swift build` and `./Scripts/build-app.sh` succeed with zero warnings.
- [ ] Tested by hand with the keyboard over USB: connect, use the feature, unplug mid-operation (no crash, sensible toast), replug (state recovers).
- [ ] Works in light and dark mode, and at the minimum window size.
- [ ] Existing features show no regressions (run through the Test, Light, Macros and More tabs).
- [ ] Committed with a clear message.

Final report, written to `FEATURE_REPORT.md` in the project root:
- what you built, per feature
- files added or changed
- decisions you made and why
- anything skipped and the reason
- known limits (firmware-bound items such as per-key RGB, tap-dance and combos)
- how to test each feature in under a minute.
