# Phase 7 (optional): Your desk in 3D

Only do this if the owner asked for it in phase 0. It is the largest phase by far; E68 Studio's scene is about half its code.

## Approach that worked

1. **Reference photos first.** 10–30 photos of the real desk from the front, top, sides and close up. Keep them in `Docs/Reference/` (git-ignored; phone photos carry location data). Every visual change is compared against them.
2. **Procedural geometry in code**, not downloaded models: SceneKit nodes built from extruded shapes and custom meshes for the keyboard case, keycaps (from the VIA layout), mouse, monitor, lamp and props. It keeps the repo small, licence-clean, and editable by an agent.
3. **Live state in the scene.** Keycaps press when keys are pressed, the backlight matches the real lighting, the lamp is a real light.
4. **Rendering.** Start with SceneKit's renderer. A Metal hardware ray tracer (E68 Studio's `Scene/RayTracer/`) gives far better light but is a large project: stored light points, one ray per pixel, MetalFX temporal upscaling for anti-aliasing.
5. **Photographed backgrounds** from CC0 HDR panoramas (Poly Haven). Ask before downloading; state file names and sizes.

## Verification without interrupting the owner

Add CLI modes that render offscreen to PNG: `--render-closeups <dir>` with fixed camera poses (home, keyboard top, mouse, lamp…). After every visual change, render and **look at the images yourself**, comparing against the reference photos. Never open the app window on the owner's screen to check something.

## Things owners reject (from E68 Studio, likely to recur)

Visible noise or "rendering in progress" speckle, cheap blur effects, fake fill light at night, pure black shadows, sandpaper-like normal maps, and generic stock plants instead of the owner's own. Record yours in `AGENTS.md` → Rejected.

Reference: `Sources/E68Studio/Scene/`, `Sources/E68Studio/App/SceneRender.swift`, `Docs/Archive/ANTIGRAVITY_HANDOFF.md` (a real handoff for this phase).
