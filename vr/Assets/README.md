# vr/Assets

Source assets for the Ares scene. Licences and credits: `../../CREDITS.md`. Total about 104 MB.

## nasa/ (real imagery, public domain with credit lines)
- `perseverance-sol253-watson-dourbes.jpg` 1280x956, WATSON abrasion close-up (has a 1 cm scale bar baked in).
- `perseverance-sol1436-watson-slants-river.jpg` 1648x1200, fractured abrasion patch.
- `perseverance-sol1526-watson-kenmore.jpg` 1577x1175, radial tool marks; cleanest for the "scientist" moment.
- `jezero-orbital-map-pia23976.jpg` 2048x1315, annotated HiRISE map of Jezero (labels and colour overlays are part of the image).
- `perseverance-sol53-64-mastcamz-van-zyl-overlook-crop.jpg` 4096x1242 far backdrop.

Backdrop notes: the source panorama is 360 degrees over 23265 px (about 64.6 px per degree, 80 degrees tall). The crop is x 31 to 95.5 percent of the width, about 232 degrees horizontally, and y 0 to 88 percent, about 70 degrees vertically. The horizon sits about 13 percent from the top of the crop (about 9.6 degrees of sky above it). The ground is real Jezero crater floor (rock-strewn orange regolith, low ridge on the horizon). Wrap it on a cylinder or half cylinder: the crop is not seamless left to right, and the right edge has a small black patch (rover deck) at the bottom. Sky is butterscotch, close to the ART.md palette but brighter. Real tyre tracks and the Ingenuity airfield are visible. It will not tile with the terrain mesh; fade the ground into it with dust haze. Credit: NASA/JPL-Caltech/ASU/MSSS.

## models/
- `polyhaven/<id>/<id>_1k.gltf` + `.bin` + `textures/` (JPG diffuse, GL normal, ARM). Also `polyhaven/<id>/usd/<id>_1k.usdc` + `textures/` (some normal/roughness maps are EXR). CC0.
- `kenney/space-kit`, `space-station-kit`, `furniture-kit`, `food-kit`: OBJ + MTL (flat-colour materials; the station and food kits use `Textures/colormap.png`). CC0.
- `quaternius/ultimate-modular-scifi-feb2021`: OBJ + MTL. CC0.

Best picks: lander `kenney/space-kit/craft_cargoA.obj` (about 260 faces), rover `rover.obj`, dish `satelliteDish_large.obj`/`satelliteDish_detailed.obj`, barrels `barrel.obj`/`barrels.obj`, rocks `rock*.obj`/`rocks_small*.obj` plus Poly Haven `moon_rock_02` (lightest), crates `plastic_crate_02` or `Props_Crate.obj`, hydroponics `seeding_tray_01` + `potted_plant_04` or Kenney `plantSmall*`, mug `food-kit/mug.obj`, shelves/racks `steel_frame_shelves_01`.

## textures/polyhaven/<id>/
1k JPG: `*_diff_1k`, `*_nor_gl_1k` (OpenGL normal; SceneKit expects this convention), `*_rough_1k`, `*_ao_1k`. Wire them in code (`material.diffuse/normal/roughness/ambientOcclusion`, `lightingModel = .physicallyBased`). Ids: red_sand, dry_ground_rocks, moon_dusted_01, rock_surface, rubber_tiles, blue_metal_plate, metal_plate_02, painted_metal_shutter.

## Formats and conversion (checked on this Mac, 2026-10-24)
- SceneKit loads OBJ, USD/USDC/USDZ and DAE natively. Verified by loading in a script: Kenney `rover.obj`, `mug.obj`, Quaternius `Props_Crate.obj`, and Poly Haven `.usdc` (geometry loads for all 15; diffuse resolved for some, EXR normal/roughness maps will not load in SceneKit, use the JPG maps from the glTF folders' `textures/` or the texture folders).
- glTF/GLB is NOT natively loadable by SceneKit or Model I/O here (`MDLAsset.canImportFileExtension("gltf")` is false). Use the `.usdc` or the Kenney OBJ instead.
- Available: `/usr/bin/usdzip`, `usdcat`, `usdchecker`; Xcode `scntool` and `realitytool`; Reality Composer Pro.app (inside Xcode). To pack a USDZ: `usdzip out.usdz model.usdc` (keep textures beside it, PNG/JPG only).
- Not available: `usdzconvert`, `usdz_converter` (removed from Xcode), Reality Converter.app, Blender.
- Model I/O can export OBJ to `.usd`/`.obj` but not `.usdz` directly.
- Kenney Space Kit also ships DAE/FBX/GLTF/STL in the original zip (only OBJ kept here); the zip is at https://kenney.nl/assets/space-kit if DAE is wanted.
