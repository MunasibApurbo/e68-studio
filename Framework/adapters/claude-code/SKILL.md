---
name: device-studio
description: Build a native macOS companion app for the user's own keyboard and mouse (key remapping, macros, lighting, music-reactive RGB, mouse buttons/DPI, battery, optional 3D desk) by following the Device Studio Framework. Use when the user asks to build software for their keyboard or mouse, to configure a VIA/QMK keyboard from their own app, or to continue a project that has Framework/START.md or PROGRESS.md.
---

# Device Studio

1. Read `Framework/START.md` and follow it. If the repo already has `PROGRESS.md`, read it, `AGENTS.md` and `device-profile.yaml` first and continue from the first unticked item.
2. Before any write to a device, read `Framework/playbooks/hardware-safety.md`.
3. Use the read-only tools for discovery:
   - `swift Framework/tools/hid-probe.swift [name]`
   - `swift Framework/tools/via-probe.swift [VID PID]`
4. Prove each phase with `--selftest` and headless renders (`Framework/playbooks/verification.md`); keep `PROGRESS.md` current.
5. For phases that can run in parallel (3, 4, 5 after phase 2), offer to start them as separate sessions, each owning one folder.
6. Save hard-won hardware facts (dead ends, firmware quirks) to memory as well as to `device-profile.yaml`.
