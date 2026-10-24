# Credits

Every third-party asset in `vr/Assets/`. Licences were read from the source pages on 2026-10-24. No real agency logos or insignia are used from any of these; NASA imagery is shown as imagery only, with the credit line on screen.

## NASA imagery (real data, `vr/Assets/nasa/`)

NASA/JPL images are generally not copyrighted (NASA media usage guidelines: use for educational/informational purposes is allowed, and the NASA insignia/logo must not be used or implied as endorsement). Show the credit line next to each image. Not an endorsement by NASA.

| File | What | Instrument | Sol / date | Target | NASA id | Credit | Source page / direct URL |
|---|---|---|---|---|---|---|---|
| perseverance-sol253-watson-dourbes.jpg | Abrasion patch, close-up, 1280x956. Contains a 1 cm scale bar in the image. | SHERLOC WATSON (Perseverance rover), 8 shadowed frames merged | Sol 253, 2021-11-05 | "Dourbes" (outcrop later cored as "Brac"), South Seitah | PIA24940 | NASA/JPL-Caltech/MSSS | https://science.nasa.gov/photojournal/watsons-view-of-dourbes-in-mars-jezero-crater ; https://assets.science.nasa.gov/content/dam/science/psd/photojournal/pia/pia24/pia24940/PIA24940.jpg |
| perseverance-sol1436-watson-slants-river.jpg | Abrasion patch that fractured after abrasion, 1648x1200 (converted from PNG to JPEG, not resized) | SHERLOC WATSON | Sol 1436, 2025-03-05 | "Slants River" | SIF_1436_0794428005_417EBY_N0692124SRLC01037_0000LMJ (raw image id) | NASA/JPL-Caltech | https://science.nasa.gov/blog/navigating-a-slanted-river ; https://assets.science.nasa.gov/content/dam/science/missions/mars2020/2025/perseverance-rover-updates/Mars_Perseverance_SIF_1436_0794428005_417EBY_N0692124SRLC01037_0000LMJ.png ; raw: https://mars.nasa.gov/mars2020-raw-images/pub/ods/surface/sol/01436/ids/edr/browse/shrlc/SIF_1436_0794428005_417EBY_N0692124SRLC01037_0000LMJ01.png |
| perseverance-sol1526-watson-kenmore.jpg | Abrasion patch with tool marks, taken from about 7 cm, 1577x1175 | SHERLOC WATSON | Sol 1526, 2025-06-05 | "Kenmore" | PIA26576 | NASA/JPL-Caltech/MSSS | https://science.nasa.gov/photojournal/zooming-in-on-perseverance-rovers-kenmore-abrasion-patch ; https://assets.science.nasa.gov/content/dam/science/psd/photojournal/pia/pia26/pia26576/PIA26576.jpg |
| jezero-orbital-map-pia23976.jpg | Annotated HiRISE-based map of regions around Jezero crater (delta, crater floor, rim, marginal deposits), with the landing ellipse. It carries colour overlays, labels and a scale bar. 3108x1996 as published; stored resized to 2048x1315. | MRO HiRISE (base mosaic) | Released 2020-07-15 | Jezero crater | PIA23976 | NASA/JPL-Caltech/USGS/University of Arizona | https://science.nasa.gov/photojournal/map-of-regions-around-mars-jezero-crater ; https://assets.science.nasa.gov/content/dam/science/psd/photojournal/pia/pia23/pia23976/PIA23976.jpg |
| perseverance-sol53-64-mastcamz-van-zyl-overlook-crop.jpg | Crop of the 360-degree Van Zyl Overlook panorama, resized to 4096x1242 (see README for how it was cropped) | Mastcam-Z (right eye), 992 frames stitched | Sols 53-64, 2021-04-15 to 04-26 | "Van Zyl Overlook" | PIA24663 | NASA/JPL-Caltech/ASU/MSSS | https://science.nasa.gov/photojournal/mastcam-zs-360-degree-view-of-van-zyl-overlook/ ; https://assets.science.nasa.gov/content/dam/science/psd/photojournal/pia/pia24/pia24663/PIA24663.jpg (23265x5165, 15 MB) |

Notes
- The Perseverance raw-image feed (https://mars.nasa.gov/rss/api/?feed=raw_images&category=mars2020&feedtype=json) is the source for the Slants River image metadata. Raw images are unprocessed and carry the credit NASA/JPL-Caltech.
- The Dourbes and Kenmore sol numbers come from the NASA captions as found via search results; the Slants River sol and time come from the NASA blog caption.
- The Jezero map is annotated; it is not a clean orbital photo. UNVERIFIED as a wall-screen look; a clean HiRISE or CTX mosaic of the delta was not downloaded (PIA19303 and PIA20549 are HiRISE close-ups of dunes and bedrock, not crater overviews; PIA23511 credits ESA data, whose reuse terms were not verified, so it was not downloaded).
- The Van Zyl panorama has the rover deck masked black in the lower left and right; the crop avoids most of it.

## Poly Haven (CC0 1.0), `vr/Assets/models/polyhaven/` and `vr/Assets/textures/polyhaven/`

Licence for all Poly Haven assets: CC0 1.0 Universal, https://polyhaven.com/license . No attribution required; given here anyway. Pages: https://polyhaven.com/a/<id>.

Models (1k textures; glTF and USD versions included):

| Id | Name | Author(s) | Approx. triangles | Used for |
|---|---|---|---|---|
| moon_rock_01 | Moon Rock 01 | Greg Zaal, Rico Cilliers, Jenelle van Heerden, Dario Barresi | 18,668 | Exterior regolith rocks (heavy; use sparingly or decimate) |
| moon_rock_02 | Moon Rock 02 | Rico Cilliers, Greg Zaal, Jenelle van Heerden | 6,194 | Exterior rocks |
| moon_rock_03 | Moon Rock 03 | Greg Zaal, Rico Cilliers, Jenelle van Heerden | 10,492 | Exterior rocks |
| moon_rock_04 | Moon Rock 04 | Greg Zaal, Rico Cilliers, Jenelle van Heerden | 14,316 | Exterior rocks |
| moon_rock_05 | Moon Rock 05 | Greg Zaal, Rico Cilliers, Jenelle van Heerden | 18,466 | Exterior rocks |
| plastic_crate_02 | Plastic Crate 02 | Fabi_G | 5,840 | Storage crates |
| Barrel_01 | Barrel_01 | Jorge Camacho | 2,682 | Barrels (exterior, storage) |
| steel_frame_shelves_01 | Steel Frame Shelves 01 | James Ray Cock | 4,348 | Storage racks |
| worn_metal_rack | Worn Metal Rack | Luca B | 6,372 | Storage racks |
| seeding_tray_01 | Seedling Tray 01 | Satyaki Mandal | 8,334 | Hydroponics tray |
| potted_plant_04 | Potted Plant 04 | James Ray Cock | 6,097 | Hydroponics greens (succulent) |
| medical_box | Medical Box | Ulan Cabanilla | 3,718 | Wall-mounted prop |
| metal_toolbox | Metal Toolbox | Mateusz Sadek | 14,228 | Workshop prop |
| propane_tank | Propane Tank | Slinc | 5,238 | Gas cylinder prop (relabel; not for the real-world meaning) |
| clipboard | Clipboard | ProgrammerOnCoffee | 6,176 | Desk prop |

Textures (1k: diffuse, GL normal, roughness, AO; JPEG):

| Id | Author(s) | Used for |
|---|---|---|
| red_sand | Rohit Seervi | Exterior regolith base |
| dry_ground_rocks | Rob Tuytel | Exterior regolith with rocks, near the feet |
| moon_dusted_01 | Greg Zaal, Rico Cilliers, Jenelle van Heerden, Dario Barresi | Dusty regolith detail |
| rock_surface | Amal Kumar | Rock material |
| rubber_tiles | Amal Kumar | Interior rubber floor |
| blue_metal_plate | Rob Tuytel | Scuffed painted metal panels (recolour in the shader) |
| metal_plate_02 | Rob Tuytel | Worn metal panels |
| painted_metal_shutter | Dario Barresi, Rico Cilliers, Charlotte Baglioni | Painted panel with wear |

**Used in the scene (interior polish round 1, `vr/Shared/Room.swift`, `Tex.swift`, `Dressing.swift`; files copied flat into `vr/AresVR/Resources/interior/`):**
- Models (.usdc, re-textured in code with the 1k diffuse JPG): `steel_frame_shelves_01` (storage rack), `plastic_crate_02` (crates on the rack), `Barrel_01` (two barrels), `medical_box` (on the rack), `metal_toolbox` (side table), `seeding_tray_01` and `potted_plant_04` (hydroponics corner under the magenta grow lights).
- Textures (1k diffuse JPG, composited in code with painted colour, seams, rivets and scuffs): `painted_metal_shutter` (wall panel relief), `metal_plate_02` (grime and scuffs on walls, ceiling and floor), `rubber_tiles` (floor). The `*_nor_gl_1k.jpg` maps are bundled but not wired yet.
- NASA/JPL-Caltech/USGS/University of Arizona, PIA23976 (`jezero-orbital-map-pia23976.jpg`, resized copy `jezero_orbital_map_pia23976_1k.jpg`): the desaturated, darkened background of the LOCATION wall screen (interior polish round 3, `vr/Shared/Screens.swift`), with the credit line "NASA/JPL-Caltech/USGS/University of Arizona, PIA23976" printed on the screen. Imagery only; no NASA logo.
- Kenney Food Kit `mug.obj` + `colormap.png` (coffee mug on the side table).
- Original, drawn in code (no third-party art): the two mission patches (invented ARES / JEZERO BASE and SOL ONE-HUNDRED CREW), the crew locker name tapes (invented names T. VASQUEZ and M. LINDQVIST, not real people), the whiteboard sol plan and sticky notes (fictional), console key panels, equipment faces (O2 SCRUBBER B, WATER RECYCLER), the pressure-door warning stripes, vent grilles and stencilled signs.

## Kenney (CC0 1.0), `vr/Assets/models/kenney/`

Author: Kenney, https://www.kenney.nl . Licence: Creative Commons Zero, CC0 1.0, http://creativecommons.org/publicdomain/zero/1.0/ (text kept as `LICENSE-*.txt` in each folder). Credit is not required.

| Kit | Source | Used for |
|---|---|---|
| Space Kit 2.0 | https://kenney.nl/assets/space-kit | Cargo lander (craft_cargoA/B), rover, satellite dishes, barrels, generators, rocks, craters, rocket parts, pipes, platforms, hangars, corridors, terrain |
| Space Station Kit | https://kenney.nl/assets/space-station-kit | Interior modules: containers, floor panels, doors, display walls, pipes, barriers |
| Furniture Kit (subset) | https://kenney.nl/assets/furniture-kit | Potted plants, bookcases, boxes, screens, lamps, desks, trash can, coffee machine |
| Food Kit (mug, cup-coffee) | https://kenney.nl/assets/food-kit | Coffee mug |

## Quaternius (CC0 1.0), `vr/Assets/models/quaternius/ultimate-modular-scifi-feb2021/`

"Ultimate Modular Sci-Fi - Feb 2021" by Quaternius (https://quaternius.com), downloaded from https://opengameart.org/content/lowpoly-modular-sci-fi-environments . Licence: CC0 1.0 Universal, per the included `LICENSE-quaternius.txt` and the OpenGameArt page. OBJ files only. Used for: interior modules, crates, shelves, vents, pipes, wall and floor tiles, doors, computers.

## Not found / not downloaded
- Solar panels, lockers, whiteboard, cable tray, warning-stripe texture (lockers, whiteboard, cable trays and stripes are now built from primitives and code-drawn textures, see "Used in the scene" above): no verified CC0 model located in the time available (Poly Haven has none; the Kenney and Quaternius kits above contain no solar panel or locker). UNVERIFIED sources were not downloaded. Build these from primitives with the metal textures above.
- Poly Haven `modular_electric_cables` (42k triangles) was found and removed as too heavy.
- Ultimate Space Kit by Quaternius: the Sketchfab page says CC-BY while the description says CC0 (conflict), and the contents were not confirmed. UNVERIFIED, not downloaded.

**Used in the scene (outdoor part 1, `vr/Shared/OutdoorSet.swift`, `Scientist.swift`, `CloseUp.swift`; files copied flat into `vr/AresVR/Resources/outdoor/`):**
- Kenney Space Kit (CC0): `craft_cargoA` (the cargo lander on the landing pad), `barrels` (beside the cargo pallets), `machine_generator` (pad generator); plus the props already placed in the window view (`rover`, `satelliteDish_large`, `hangar_round*`, rocks).
- Poly Haven (CC0): `moon_rock_02` and `moon_rock_04` (.usdc, diffuse JPG; the science outcrop).
- Outdoor round 2, Poly Haven (CC0) 1k diffuse maps copied into `vr/AresVR/Resources/outdoor/`: `red_sand` and `dry_ground_rocks` (layered into the tiled regolith detail texture on the near terrain, `Rocks.swift` `DetailTexture`), `moon_dusted_01` (the batched pebbles), `rock_surface` (copied, not yet used). The cargo lander is now built from primitives with a code-drawn hull texture (panel seams, rivets, edge wear, dust) over the interior's `metal_plate_02` grain; the Kenney `craft_cargoA` model is no longer used.
- NASA/JPL-Caltech/MSSS, PIA26576, `perseverance-sol1526-watson-kenmore.jpg`: the scientist's close-up panel (abrasion patch "Kenmore", SHERLOC WATSON, sol 1526), shown with its caption and credit line. Imagery only; no NASA logo.
- Original, drawn in code: pad markings and scorch decal, habitat shell panels and the AIRLOCK 1 door, crate stencils (invented "ARES CARGO SIM-n" labels), footprints and tyre tracks, solar-cell texture, the scientist figure (primitives). Terrain is the real USGS HiRISE/CTX mesh already credited above.
- Outdoor round 3: the batched pebbles now use the Poly Haven (CC0) `moon_rock_02` 1k diffuse already bundled for the outcrop boulders (one rock family); `moon_dusted_01` is no longer used. Scorch, dust ring, storm band, path lights and the hull wear are code-drawn.
