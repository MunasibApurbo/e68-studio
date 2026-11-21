# Asset Credits & Provenance

This document records the source and licensing of every bundled asset in `E68 Studio.app/Contents/Resources`.

## Third-Party Assets (Poly Haven — CC0 Public Domain)

All of the following are from Poly Haven (https://polyhaven.com) and are released under CC0 (public domain). No attribution is required; this list records where each file came from.

### Environments (`Resources/Environments`, 2K HDR panoramas)

| File | Used for |
|---|---|
| `alps_field_2k.hdr` | Swiss Alps, day |
| `moonlit_golf_2k.hdr` | Swiss Alps, night |
| `snowy_park_01_2k.hdr` | Winter Park, day |
| `winter_evening_2k.hdr` | Winter Park, night |
| `meadow_2_2k.hdr` | Meadow, day |
| `dikhololo_night_2k.hdr` | Meadow, night |
| `symmetrical_garden_02_2k.hdr` | Garden, day |
| `moonless_golf_2k.hdr` | Garden, night |
| `spiaggia_di_mondello_2k.hdr` | Ocean Cove, day |
| `umhlanga_sunrise_2k.hdr` | Ocean Cove, night |
| `goegap_2k.hdr` | Red Desert, day |
| `rogland_clear_night_2k.hdr` | Red Desert, night |
| `the_sky_is_on_fire_2k.hdr` | City Lights, day |
| `shanghai_bund_2k.hdr` | City Lights, night |

### Materials (`Resources/Materials`)

| Files | Used for |
|---|---|
| `dark_wood_diff_2k.jpg`, `dark_wood_nor_gl_2k.jpg`, `dark_wood_rough_2k.jpg` | Desk top (Poly Haven `dark_wood`, stained darker in code) |

## Project & Hardware Assets

| File(s) | Origin / Purpose |
|---|---|
| `ukiru-mat.jpg` | Desk mat surface derived via `Scripts/make-ukiru-mat.swift` from project reference desk photography (`Docs/Reference/desk.jpg`) |
| `Plants/bamboo_cane_{diff.jpg,norm.png,rough.png}` | Lucky bamboo stalk diffuse, normal, and roughness maps (procedural leaf foliage generated in `DeskTextures+Plants.swift` / `PlantProps.swift`) |
| `Plants/dieff_cane_{diff.jpg,norm.png,rough.png}` | Dieffenbachia cane diffuse, normal, and roughness maps (procedural leaf foliage generated in `DeskTextures+Plants.swift` / `PlantProps.swift`) |
| `Plants/pothos_stem.jpg`, `Plants/root_diff.jpg` | Golden pothos trailing vine stem and submerged root textures |
| `VIA/Furycube_E68_PRO_Wired.json`, `VIA/Furycube_E68_PRO_2.4G.json` | Furycube E68 Pro QMK/VIA keymap definitions |
| `AppIcon.icns` | Generated at build time from `Scripts/make-icon.swift` |

Note: Monitor, iPad, and phone screen displays are generated procedurally in `DeskTextures+TechScreens.swift`.
