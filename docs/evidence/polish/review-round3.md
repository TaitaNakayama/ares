# Round 3 visual review (inside the room, screens, robots)

## Room

**(a) Effortful: 8/10**
- Dense, layered dressing: grow shelf, crates, barrel, lockers, whiteboard, airlock, table with mug and toolbox, floor chevrons, floor drain, cable runs, hazard tape.
- The ceiling is still a brown grid with a few cream bands. It is the one big surface with no detail (no pipes, ducts or lamp housings), and the floor's central disc is still bare.
- Cables and the drain (headset frame) are a real gain. The floor streak texture reads as scratches, but it looks like noise rather than wear.

**(b) Consistent style: 7/10**
- Stencil signs, muted palette and panel wall hold together. Machines and shelves share one flat cartoon-PBR look.
- The whiteboard and screens are still separate typographic voices. The ceiling grid is a flat-shaded plane in a different style from the textured walls.

**(c) Readable text: 6/10**
- Signs and the machine titles read well. The big whiteboard heading reads, and the locker names are bigger.
- The headset frame shows only the lower floor, so legibility at 1200 px per eye could not be checked. The small screen text in the Mac captures is the risk: footers, "Saved so far", the HUD box and the Location data rows.
- Text still gets cut off at frame edges in the two wide spectator captures (POWER "Chargi", LOCATION "Sol 411 00"). That is partly the camera, but it hides content.

**(d) Believable Mars base: 7/10**
- Rivets, conduits, the window with the lander, and the warm pool of light sell shelter.
- Machines still float with no contact shadows. The ceiling and the empty floor are the least believable parts.

## Screens

**(e) Designed: 8/10**
- POWER (ring gauge, ON pill, sparkline) and MONEY (KPI tiles) are well built. The LOCATION card, with its NASA image background and credit, looks credible.

**(f) Legible hierarchy: 6/10**
- Hero numbers ($180.0M, 298 days, 100%) win clearly.
- Robot nametags still cover screen headers: "Engineer · Requester" sits on the POWER "kWh per sol" label, and "Money Keeper · Treasury" sits on the MONEY title and Cash tile.
- Footers ("Solar model...", "...budget are SIMULATED") are still microscopic.

**(g) Consistent with the room: 7/10**
- Dark navy panels with scuffed bezels sit better than before. They still emit no cool light onto the wall and are noticeably cleaner than the room.

## Robots

**(h) Appealing and alive: 8/10**
- Distinct silhouettes (box, capsule, pod, round), glossy faces with highlights, coloured rings and floating pads. The speaking pose and big caption read at once.
- Faces are blank and a little samey. The bubbles are clipped ("runwa...", "hown").

**(i) Consistent with the room: 6/10**
- Their saturated rounded-toon look is the most polished part and differs the most from the rough room. The pastel shells and neon rings are bright against the muted palette.
- The floating pads and rings hover with no shadow on the console.

## Round-2 fixes

1. Contact shadows and a floor pool: **partly landed.** A soft dark pool is under the console, but the machines, lockers and shelf still show none.
2. Bigger secondary screen text: **partly landed.** MONEY and LOCATION are better, but footers are still tiny.
3. Tags kept out of the screens: **not landed.** Tags still overlap the POWER and MONEY headers.
4. Blank screen and HUD: **mostly landed.** The Location card now has content. The HUD box has real lines but still clips at the right edge in one view.
5. Wall-side lighting and bezels: **partly landed.** The bezels have wear, and there is no screen spill.

## Next five fixes

1. Anchor each robot tag above the head and offset it from any screen rectangle, or fade it when it overlaps a screen, so no screen header is covered.
2. Detail the ceiling with pipe runs, duct boxes and lamp housings, and add a darker perimeter gradient so it stops reading as a flat plane.
3. Bake blob contact shadows under every machine, locker, shelf, barrel and table.
4. Raise every screen footer and secondary label to at least 60% of the label size, and verify them on a real headset frame facing a wall (the supplied headset frame only shows the floor).
5. Desaturate the robot shells and rings about 15%, add a drop shadow under each pad, and give each robot a distinct eye shape, so they share the room's palette.

## Leave alone

The riveted wall and wear band, grow-light shelf, stencil signs, cables and floor drain, the Location card, and the robots' silhouettes and glossy faces.
