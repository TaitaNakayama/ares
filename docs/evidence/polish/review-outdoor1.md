# Outdoor review 1 (fresh eyes)

## Scores

**(a) Looks effortful: 6/10**
- The pad has real density: barcoded ARES CARGO crates, striped drums, pallets, yellow pad markings, flag poles, lamp posts. The airlock door (hazard stripes, rivets, glow, "AIRLOCK 1" decal) is the best-finished object.
- The terrain is a flat brown plane with a few faceted low-poly rocks. The boulders in outdoor-science and the headset foreground rocks are plain faceted brown with no grit or dust. They look like placeholders next to the textured grey boulders.

**(b) Consistent with the interior: 5/10**
- Interior (inside-after-enter) has panelled walls, light strips and a rubber floor. The door and habitat shell outside share that rivet and panel language.
- The lander, the pad building and the astronaut are flat-shaded primitives (a grey wedge with black slab windows, a cylinder rocket). They look a generation cruder than the interior.
- The lander (outdoor-pad) and the rocket (outdoor-science) read as different vehicles. Two incompatible landers also erodes the "just landed" story.

**(c) Text readable at ~1200 px per eye: 7/10**
- Captions and the REAL MARS card are large and high contrast. Credit text in the card ("NASA/JPL-Caltech/MSSS, PIA26576") is big enough to read.
- In outdoor-solar the engineer speech bubble ("Requesting 40 battery modules...") and the nametags are tiny, about a quarter of the caption size. They will be mush in Cardboard.
- In headset-pad the "Cargo Keeper - Receiver" tag is about 12 px tall. Captions are not visible in the headset frames at all, so their size in the headset is unchecked.

**(d) Believable Mars: 6/10**
- The butterscotch sky, hazy horizon ridge and rust palette match ART.md. The dust-streak storm frame (outdoor-solar) is the most convincing image of the set.
- The ground is untextured and flat, with no detail texture, scorch marks, tracks or footprints. Shadows are absent or very weak, so objects float. There is no long low-sun shadow, which was the main lighting idea.
- Scale is unclear. The pad building could be a shed or a hangar. The solar arrays are tiny in the distance and the horizon is the same blur in every direction.

**(e) Story clarity: 5/10**
- The door prompt "ENTER THE BASE - Look at the door and press the button" is clear. The storm dialogue ("Dust storm rising... get inside") works, and the streaks help it.
- "A cargo lander just landed" is not shown. The pad frame shows a building with crates and no lander or engine scorch. The rocket stands far off, upright, with no relation to the crates.
- The scientist is only visible in outdoor-science, and the Kenmore card hides the scientist in the closeup. There is no visible storm front on the horizon before the dust begins.

## Five fixes, in priority order
1. Put the lander in the pad hero shot: place the rocket on the pad itself and add a dark scorch decal and an exhaust-plume glow sprite under it, so crates visibly come off it.
2. Add a tiled regolith detail texture (grit, small stones, mottled tone) and a large soft dark blob shadow under every prop and rock. This is texture-only and fixes the floating and flat-ground look.
3. Raise the in-world label scale: world-space speech bubbles and nametags at least 2.5x their current size, with the same contrast as the captions.
4. Add a dark, dusty storm wall on the horizon, ahead of the dust streaks, with the horizon haze thickened and tinted toward #5A3A2A. Use a gradient billboard, no geometry.
5. Match the exterior to the interior material language: apply the panel-line and rivet texture, dust tint and edge wear to the pad building and lander, replace the black slab windows with an emissive warm strip, and give the boulders the dusted rock texture the science rocks already have.

## Leave alone
The airlock door (stripes, glow, signage), the Mars sky colour grade and the REAL MARS credit card layout.
