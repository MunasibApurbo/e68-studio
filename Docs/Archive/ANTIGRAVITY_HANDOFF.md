# Handoff: E68 Studio 3D desk

You are continuing work on E68 Studio, a macOS keyboard and mouse utility with a 3D desk drawn by a Metal
hardware ray tracer. Read sections 1 to 5 before changing anything. Section 6 is history, for reference.

Last updated 2026-11-15.

## 1. Where things stand

- The desk is drawn by the **live renderer** (default). Soft light is stored at about 1.89 million points
  on the surfaces (76 MB), built over 112 passes and saved to disk per world, time of day and lighting.
  The frame itself has no randomness: one camera ray per pixel, stored light, a per-pixel sun shadow
  ray, one reflection ray, then `MTLFXTemporalScaler` at 1:1 for edges.
- The **path tracer** is kept as a reference only (`-e68.live NO`).
- Eight worlds, each with a day and a night photograph (Poly Haven, CC0): Swiss Alps, Winter Park,
  Meadow, Garden, Ocean Cove, Red Desert, City Lights, plus Studio Room (no photograph).
- The desk lamp is stored separately as unit white, so on/off, brightness and colour change instantly.
- Lens blur exists but is off (`-e68.lensBlur YES`). The background blur control was removed.
- Headless numbers on an M4 at 1280x800: about 8 ms per settled frame, about 30 ms per bake pass,
  about 1 s to first frame, 1.3 GB resident memory.
- **Nothing is committed.** About 106 files are changed or deleted on `main`.
- `E68 Studio.app` is built from the current tree (118 MB, 91 MB of it panoramas), signed with the
  local identity `E68StudioLocal` only.

## 2. Rules

- Commit the current tree before you start (see B1).
- Only one tool edits `Sources/E68Studio/Scene/` at a time.
- Check with headless renders. Do not open the app window or run on-screen perf scripts; the user was
  interrupted by one before.
- Do not download anything without the user's approval. State the file, the source and the size first.
- If what a stored light point means changes, bump the cache constant `0x5EED_0004` in
  `PathTracerRenderer.renderLiveFrame`, or old files on disk will be loaded.
- MetalFX: motion vectors must not include the frame's jitter; `jitterOffsetX/Y = -jitter`.
- Never reset anti-aliasing history because the camera moved.
- Do not hand the scene to `SCNView` or call `SCNRenderer.prepare(scene)` (about 420 MB and seconds).
- Per-ray cost on this GPU is roughly fixed. Speed comes from fewer rays or fewer points.
- Keep `-e68.live NO` working. HID, audio and store code are unrelated to this work.
- The user wants the work delivered, not rounds of questions. Ask only when a decision is theirs.

## 3. What the user has already rejected (do not bring back)

- Any visible noise, speckle or "rendering in progress", moving or still.
- Background blur and lens blur ("cheap").
- Automatic moonlight or fill that lights the desk at night ("fake"). Night is lit by the lamp, the
  monitor and the keyboard only, and the monitor spill is deliberately low.
- Pure black shadow under the desk on the photographed ground ("cartoon").
- Strong normal-map relief under low light (sandpaper grain on the mat and mouse).
- Generic scanned plants. The plants are the user's real ones: pothos, lucky bamboo, a cutting in a jar.
- The sunset lamp, the spotlight and the white adapter on the desk (all removed on request).

## 4. How to build and check

```bash
swift build -c release --disable-sandbox
./Scripts/build-app.sh                       # rebuilds "E68 Studio.app"
BIN="E68 Studio.app/Contents/MacOS/E68Studio"
"$BIN" --render-closeups <dir>               # views: home, angle, keyboard, keyboard-top, mat-and-mouse,
                                             #        wood-and-cables, lamp-and-plant, glass-and-phone
"$BIN" --render-switch <dir>                 # Alps -> Room switch, saves frames across the transition
"$BIN" --render-motion <dir>                 # orbit and drag, saves frames
```

Options: `-e68.closeupScenario <swissAlps|winter|nature|blossom|ocean|canyon|cyberpunk|room>`,
`-e68.closeupMood <daylight|midnight>`, `-e68.closeupOnly <view>`, `-e68.closeupLampColor`,
`-e68.closeupLampBrightness`, `-e68.perf YES` (timings), `-e68.noLightCache YES` (ignore saved light),
`-e68.live NO` (path-traced reference).

Reference photos of the real desk are in `desk model reference/` (25 HEIC files). Earlier renders to
compare against are in `Docs/Renders/live-renderer-comparison/`.

## 5. Everything still to do

Order: B1 first, then A1 to A3, then C, then D. E is for the user.

### A. Renderer rough edges

### A1. No shimmer when wallpaper or a keycap colour changes
Where: `PathTracerRenderer.renderLiveFrame`, the `if discreteChange || continuousDrift` block.
Problem: every branch sets `bakePassesSinceChange = 0`, and pass 0 uses `maxCount = 1`, which throws the
stored light away. Geometry has not changed in these cases, so the old light is a good starting point.
Do:
1. Keep the wipe only for `topologyReset` and for a scenario or mood change (those use the dissolve).
2. For every other change (material hash, monitor colour, other light drift): set
   `gradualBakeRefresh = true`, `fastBakeRefresh = true`, `warmPasses = 0`, keep the existing samples.
3. Change the gradual window so old light really leaves: `maxCount = 24` for the first 96 passes, then
   grow by one per pass up to 192. (The current `max(36, passes + 1)` leaves about 12% old light.)
   Let a gradual refresh run 200 passes before it counts as converged and is saved to disk.
4. Check whether a keycap colour change bumps `extractor.lightCacheGeneration`. If the layout hash is
   unchanged, `buildLightCacheTables()` must not bump it, or step 2 never runs.
Done when: a headless run that changes the monitor colour mid-run shows no speckle in any frame, and
after 200 passes the image matches a from-scratch bake of the new state.

### A2. First visit to a world in about 1.5 s instead of 3 s
Where: `RTSceneExtractor.buildLightCacheTables()`.
Problem: 1.89M points at ~30 ms per pass, ~80 passes to look clean. Spacing is
`0.2 * max(1, dist / 40)^1.5`, so the room shell (walls 240x120, floor 240x200) and the ground disc get
far more points than their smooth lighting needs.
Do:
1. Log points per node with `-e68.perf YES` to see where they go.
2. Give the room shell, floor and ground disc a coarser base spacing (start at 0.5), but keep 0.2 within
   about 30 units of the desk centre so the lamp pool and contact shadows on the wall stay sharp.
3. Target 900k points or fewer. Bump the cache constant.
Done when: `--render-switch <dir> -e68.noLightCache YES -e68.perf YES` reaches pass 80 in about 1.5 s,
and `--render-closeups` views `home` and `angle` for room daylight and room midnight show no blotches
or blurred lamp edge compared with `Docs/Renders/live-renderer-comparison/`.
This also shortens the window in which dragging the camera can show speckle. Do not change the
dissolve's motion escape (12 moving frames); a longer hold feels like a freeze.

### A3. Memory (1.3 GB resident in headless runs)
Measure before changing anything: `logGPUMemory()` plus resident size after launch and after visiting
three worlds. Then, in order of likely gain:
1. Free the panorama (float pixels and Metal texture) of a world as soon as another one is active.
2. Check that SceneKit materials are not keeping CGImage copies of textures already uploaded to Metal
   (129 textures); release the CGImages after upload where SceneKit never draws them.
3. Stored light: `samples` is float4 (16 bytes per point). Half-float rgb plus a separate 16-bit count
   halves it; Task 2 halves it again.
Done when: resident size is reported before and after, per step.

### A4. Speckle when the camera is dragged during a world-switch dissolve
No separate change: A2 shortens the window. Do not lengthen the hold; it feels like a freeze.

### B. Housekeeping

- **B1. Commit.** Everything since `1b591b4` is uncommitted. Commit it as it is before editing, in a few
  logical commits if practical (renderer, worlds and assets, desk props, UI chrome). Do not push
  unless the user asks.
- **B2. Stale code.** With the live renderer the default, remove what the path tracer no longer needs at
  run time, and any dead code left from the removed blur control, sunset lamp and deleted scenarios.

### C. Realism the user asked for and has not got yet

Compare every change with `desk model reference/`. The user's words for the current state were
"cheap" and "cartoon"; the bar is a photograph of their desk.

- **C1. Plants.** Leaf shapes and sizes do not match the photos; only colour was corrected. Pothos leaves
  should be heart-shaped with a centre crease and slight curl; bamboo leaves long and narrow from the
  stalk nodes. Keep them hand-built. Leaves need light passing through them at grazing sun.
- **C2. IEMs.** The model and materials look cheap: shells need a clear resin body with a faceplate,
  metal nozzles, and a braided cable with real thickness. The 3.5 mm plug stays seated in
  `TechProps.MacMini.jack`.
- **C3. Monitor.** Bezel and stand materials are flat. Matte black plastic with fine grain for the
  bezel, satin metal for the stand, and a blurred reflection on both (see C7). The ASUS chin logo was
  redrawn at 4096x256; check it reads cleanly in the `home` view.
- **C4. Plastic grain.** Keycaps and the mouse shell have no fine texture. Add a very fine normal map,
  and keep the relief clamp in `liveKernel` (0.82...1.18) so it never turns to sandpaper under the lamp.
- **C5. Keyboard knob.** Set to silver (0.83, 0.84, 0.86, metal 1.0, rough 0.30) as a guess. Confirm
  against the photos.
- **C6. Ground and background sharpness.** The panoramas are 2K, so the ground near the camera is soft.
  4K or 8K files fix it but need a download the user must approve, and add roughly 4x or 16x to the
  91 MB of panoramas. Ask first, and propose which worlds are worth it.
- **C7. Satin reflections.** Mac mini and monitor stand get no blurred reflection; one ray can only be
  mirror sharp, so they fall back to stored light. A prefiltered or multi-tap reflection would help.
- **C8. Look at every world.** Only Swiss Alps, Meadow and Studio Room were examined closely after the
  exposure tuning. Render `home` and `angle` for all eight worlds, day and night, and fix exposure,
  sun direction (`turn` in `DeskPhotoSky`) and ground tint where the desk does not sit in the photo.
- **C9. Older notes, not re-checked.** Water in the vases paler than the reference; wooden bowl paler;
  mouse contact shadow weak (per-vertex stored light on the shell). Check whether each is still true.

### D. Publish readiness

- **D1. Size.** 118 MB. Options: fewer or re-encoded panoramas, night files at lower resolution.
- **D2. Memory.** See A3.
- **D3. Bundle.** Check `Info.plist` version and identifier (`local.e68studio`), the icon, and that
  `Resources/ASSET_CREDITS.md` lists every Poly Haven file that ships.
- **D4. Signing and notarisation.** Needs the user's Apple Developer ID; you cannot do it for them.
  Prepare the script and tell them the commands.
- **D5. First-run experience.** A first launch fades in from black while the light is built. Confirm it
  is acceptable or ship a pre-built light file for the default world.

### E. Only the user can check (on screen)

- The world-switch dissolve and the lamp-dot fix from 2026-11-15.
- The compact control bar, the lamp popover and the merged device capsule (`DeskChrome.swift`).
- On-screen frame rate at their window size.
- Keyboard Studio and Mouse Studio views.

## 6. History (what was done and why, oldest first)

## Photographed skies (added 15 Nov)

`Scene/Environment/DeskPhotoSky.swift` lets a scenario be lit and backed by a real 360-degree HDR
photograph from `Resources/Environments/` (CC0, polyhaven.com). The photo is the background, the
reflections and the daylight; a sun bright enough to cast shadows is lifted out of the image and turned
into the key light. A photographed scenario builds only its terrace, no generated landscape.

- Done: Swiss Alps, day (`snowy_park_01_2k.hdr`, overcast, no sun) and night (`moonless_golf_2k.hdr`).
- To add a scenario: add a case to `DeskPhotoSky.asset(scenario:mood:)`, return early from its
  `build...` function after the terrace, and tune `whiteLevel` against `--render-closeups`.
- Do not assign the generated cubemap to `scene.background.contents` and then replace it with a colour:
  SceneKit keeps the cubemap. `KeyboardScene.setAmbience` skips the cubemap when a photo exists.
- The 2K photo is soft as a background (it reads as lens blur). A 4K or 8K backplate would be sharper
  but costs memory; not done.
- Night with the photo sky is untuned: the lamps barely show. Check whether the light-cache disk key
  covers the environment image, since stale stored light would look like this.
- `Resources/Materials/dark_wood_*_2k.jpg` (scanned wood: colour, normal, roughness) is downloaded but
  not applied to the desk yet.

### Night with the photo sky (fixed 15 Nov)

- The stored-light disk cache key now includes a fingerprint of the sky image
  (`RTSceneExtractor.environmentHash`). Before, changing the sky or its brightness loaded stale light.
- At night the scenario's moonlight stays as the key light; the night panorama alone left the desk black.
- Still open: the snow-coloured terrace does not suit the grassy night panorama. Either use a snowy
  night photo or make the terrace colour follow the mood.

### Grain while dragging, wood, lens blur (15 Nov, later)

- Grain while the camera was dragged came from stored light being restarted from nothing. The material
  hash in `RTSceneExtractor.computeMaterialCacheHash` included glow and opacity, which change every
  frame (backlit legends, hover overlays, key highlights). It now covers only colour, metalness and
  clear coat. A lamp, mood or material change no longer zeroes stored light either: it is blended in
  (`fastBakeRefresh` in `renderLiveFrame`). Only a rebuilt scene starts from empty.
- Live frames set render flag bit 3: textures are read at pixel size, highlight maps slightly coarser,
  and the per-point random roughness is skipped. This removes crawling detail in moving frames.
- The desk uses the scanned `dark_wood` set, stained to the dark espresso colour
  (`DeskTextures.loadScannedWood`).
- `lensBlurKernel` adds depth of field after anti-aliasing (`-e68.lensBlur NO` turns it off).
- `--render-motion` now includes a night drag with animated backlight, selection and key presses.
- Night does reach the idle state (28 frames after the change in the benchmark). An earlier run that
  never settled was the benchmark's own fault: the animated backlight was still switched on.

## Photographed worlds everywhere (15 Nov, latest)

- Scenarios are now: Swiss Alps, Winter Park, Meadow, Garden, Ocean Cove, Red Desert, City Lights (each a
  day and a night panorama, table in `DeskPhotoSky.asset`), plus the built Studio Room. Aurora, Heaven,
  Hell, Deep Space and Coral Reef were removed: no real footage exists for them. All generated landscape
  code is gone (`DeskScenarios+Natural`, `+FantasyAndUrban`, `DeskSky`).
- The ground is the photograph's own ground: `DeskScenarios.photoGround` is a ringed disc at floor level,
  flagged `RTMatFlags.isGroundProjection`. `liveKernel` paints it with the panorama as seen from
  `photoCaptureOrigin` and multiplies in stored light / `whiteLevel`, which lays the desk's shadows on it.
  New uniforms: `groundProjection`, `backdrop` (background blur in mip levels).
- `Asset.turn` rotates a panorama so its best view is behind the monitor.
- Background blur: `AmbienceKeys.backgroundBlur`, slider in the desk bar and in Settings.
- Desk: iPad placed (model already existed), sunset projector lamp and white adapter removed, loose cable
  remodelled as USB-C, IEM plug seated in the Mac mini's jack (`TechProps.MacMini.jack`).
- Desk bar and status pills rewritten to be smaller (`DeskChrome.swift`, `StatusPill.swift`). These were
  compiled but not looked at on screen.
- Asset sources: `Resources/ASSET_CREDITS.md`.
- Not done: sharper (4K+) backplates, a photographed interior for the Studio Room, Developer ID signing
  and notarisation.

## Crisp sun, lamp, sharpness (15 Nov, last)

- The directional sun or moon is no longer stored. Render flag bit 4 makes the bake skip it;
  `evalKeyAndLampSpecular` returns its matte light (`sunWhite`) from the same shadow ray as its highlight,
  and `sunWhiteAt` adds it at bounce and reflection hits. Stored light now holds only sky, lamps and
  bounce, which is why cast shadows are sharp. The disk cache key carries a format constant; bump it
  whenever what is stored changes meaning.
- Desk lamp: the cone term had its sign inverted (it lit only what was level with or above the bulb).
  Fixed in the bake weights, the bake sample and the live highlight. The lamp's shadow ray stops 4.2
  units short of the bulb so the lamp head cannot block its own light. Brightness and colour are user
  settings (`AmbienceKeys.deskLampBrightness`, `deskLampColor`, `KeyboardScene.setDeskLampLight`).
- Night uses no automatic moonlight: only the photo, the lamp, the monitor and the keyboard light the desk.
- Background blur control removed; lens blur is off unless `-e68.lensBlur YES`.
- Live texture sampling is sharper again (`lodBias` -0.5); the earlier softening was not what fixed the
  grain (that was the stored-light restarts).
- Satin metal gets broad sky and sun light (`metalness > 0.5` branch in `liveKernel`).
- Leaves: sun passes through from behind, duller highlight, less saturated green.
- Knob is silver aluminium; ASUS chin texture is 4096x256.
- Not done: scanned plant models, surface smudges and plastic grain, cloth weave on the mat, IEM rework.

## Matched to the reference photos (15 Nov, after `desk model reference/`)

- The real desk photos are in `desk model reference/` (HEIC). They are the target for materials: warm dark
  brown wood, golden pothos in a glass fishbowl, lucky bamboo in a bottle, a cutting in a ribbed jar,
  glossy black architect lamp, silver Mac mini.
- Desk wood retoned from near-black to that brown (`DeskTextures.loadScannedWood`).
- Plants stay hand-built (a generic scanned plant would be less like the real ones); leaf colour is a
  fresh yellow-green again.
- Monitor spill cut to about a third (`monGain`): at night the mat was as bright as the screen.
- Ground shadows never reach black (`shade = 0.20 + 0.80 * open`) and the projected ground gets fixed
  fine-grained variation near the camera, because the 2K panorama is enlarged many times there.
- `applySurfaceWear`: slow roughness variation on glossy surfaces (smudges), fixed to the surface.
- Still open: plant geometry (leaf size and shape versus the photos), plastic grain on keycaps and mouse,
  IEM model, monitor bezel material, sharper ground (needs 4K+ panoramas).

### Grainy mat and mouse under the lamp (15 Nov)

- Cause: the normal-map relief term divided by the cosine of the stored light's direction with a floor of
  0.25. With the lamp skimming low across the mat that doubled and halved the light per texel, so a 0.11
  cloth normal map looked like sandpaper. The floor is now 0.55, the effect is scaled by 0.45 and clamped
  to 0.82...1.18; highlight maps are read 0.7 mip coarser in live frames.
- `--render-closeups` has a `keyboard-top` view for checking this.

## Bright dots by lamp light (fixed 2026-11-15)

- Symptom: isolated pale dots on the wall and mat whenever the desk lamp was on, clearest at night.
- Cause: in `lightCacheBakeKernel` the desk-lamp bounce (`valueDesk`) gathered from the lamp's own head,
  which sits next to the bulb and is ~10x brighter than the desk. One bounce ray per pass rarely finds it,
  so a few stored points ended up far brighter than their neighbours.
- Fix (`RTLiveShaders.swift`): bounce hits within 6 units of the bulb are skipped for `valueDesk`, and any
  single desk-lamp bounce is capped at 0.05. Disk cache format bumped to `0x5EED_0004` so old caches with
  the dots are discarded.
- Checked headless: `--render-closeups -e68.closeupScenario room -e68.closeupMood midnight`, views `home`
  and `mat-and-mouse`. Renders: `Docs/Renders/live-renderer-comparison/final-room-night-*no-dots.png`.

## Speckled walls right after switching world (fixed 2026-11-15)

- Symptom: wall and floor looked like coarse stucco for a few seconds after picking a world or day/night.
- Cause: the stored light is rebuilt from empty on a switch (~30 ms per pass, ~80 passes to look clean,
  so about 3 s on an M4) and the frame showed it while it filled in.
- Fix (`PathTracerRenderer.renderLiveFrame`): on a scenario or mood change the last presented frame is
  copied to `liveHeldTex` and the composite blends from it to the new frame (`blendTex` + `progressBlend`),
  keyed to bake passes 40...80; baking runs at 2 passes per frame meanwhile. A launch dissolves from black.
  A world already in the disk cache fades in ~14 frames. A moving camera ends the hold within 12 frames.
- Not dissolved on purpose: material or wallpaper changes (would freeze the view while picking colours).
- Check: `--render-switch <dir> -e68.noLightCache YES` saves frames across an Alps -> Room switch.
  `--render-closeups` also has an `angle` view now (the 3/4 preset).
