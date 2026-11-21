# Phase 0: Interview

Goal: learn what the owner has and what they want, in **one round** of questions.

## Ask these together, in one message

1. **Devices.** Exact keyboard and mouse model names (as printed on the box or underside). Any other device to include (headset, macro pad, controller)?
2. **Connections.** Which do they use: USB cable, 2.4 GHz dongle, Bluetooth? Can they plug each device in by USB for setup?
3. **Existing software.** Does the maker ship an app or web driver (VIA, Vial, a vendor "driver", a web configurator)? Is it on Windows only?
4. **Features.** Offer this list and let them tick:
   - key and knob remapping, layers
   - macros (text, key sequences)
   - backlight control
   - music-reactive / screen-colour / wallpaper-colour lighting
   - mouse button remapping, gestures, DPI stages, scroll speed and direction
   - battery levels and low-battery alerts
   - per-app profiles
   - key tester with WPM
   - menu bar companion
   - 3D model of their desk (ask for 10–30 photos from several angles if yes)
5. **Look and feel.** Light, dark, or follow the system? Any app they like the look of?
6. **Sharing.** Just for them, or for others? (Decides signing and notarisation in phase 8.)

## Then, without asking more

- Write `device-profile.yaml` from `templates/device-profile.yaml`, filling in what you know and leaving the rest for phase 1.
- Write the feature list into `PROGRESS.md`, grouped by phase.
- Search the web for each device: "<model> VIA json", "<model> QMK", "<model> protocol", "<model> OpenRGB". Record links and findings under `research:` in the profile. A VIA JSON definition means phase 3 will be straightforward.
- Show the owner the feature list once and ask them to confirm it. That is the only confirmation this phase needs.

## Reference

E68 Studio's equivalent facts are at the top of the repo's `README.md` (Supported hardware) and in `Resources/VIA/*.json`.
