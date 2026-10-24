ADD-ON: the outdoor opening (two-part demo) + a full visual polish pass. Don't interrupt current work; do this after priority 2 (agent-generated decision options) and before the tape re-record.

## A. The two-part demo

The demo becomes two parts: outside on Mars, then inside the base.

PART 1: OUTSIDE (the judge starts standing on the real Jezero terrain at ground level)
1. Landing pad: a cargo lander has just arrived. The Cargo Keeper is scanning boxes beside it ("34 air filters"). This IS beat 1 (the short delivery), now shown physically.
2. Science site: a scientist (a crew member or science robot, clearly labeled; part of the world, not one of the 5 agents) is taking soil/rock samples, with a visible action and a speech bubble ("Taking a sample of the delta rock"). Gaze + tap on the scientist opens a close-up view of a REAL Perseverance close-up image (e.g., from its rock-abrasion and microscope cameras), with a caption naming the instrument, the sol, and the source. Use only real NASA imagery here; no invented "Mars soil" visuals.
3. Solar field: the Engineer is checking the panels, then warns that a dust storm is coming. The storm is visibly rising over the real crater rim. "Commander, get inside."
4. The judge gazes at the base door and taps; the view moves them to the door over a few seconds (steady slow speed along a path, no sudden acceleration), then they're inside.

PART 2: INSIDE
5. The control room. Through the window, the storm hits and the crisis continues from beat 2.

Requirements:
- Real data: the same Jezero terrain and Mars24 sun. Standing at ground level needs extra near-field detail (small rocks, a detail texture near the feet) because the terrain data is blurry up close. Optionally, a real Mastcam-Z panorama as the far backdrop if it blends convincingly; skip it if it doesn't. Cite every real source on screen or in the scene's info.
- The scientist's and agents' lines follow the same rules as everything else: facts from the engine, lines validated, rules fallback.
- Ground-level rendering at a steady 60 fps on the iPhone is a Tier 1 performance claim: spike it before building the full scene.
- The spectator view follows the judge through both parts, including the walk to the door.
- Keep part 1 short: target 30-45 seconds before the judge is inside, so the full core demo stays near 2-3 minutes. Report the new total length.
- If time gets tight, the scientist is the first thing to cut from part 1. The landing pad and the storm warning carry the story.

## B. Visual polish: it currently looks plain and needs to look effortful

The goal: a judge putting on the headset should think "someone cared about every corner of this." Lived-in, detailed, cinematic, and still a steady 60 fps.

Art direction (write it into ARCHITECTURE.md or a short ART.md first, then build to it):
- Lighting: warm, cozy interior vs. cold, dusty exterior. The contrast sells "shelter." Use baked lighting where possible, emissive screens and lights, and fake glow sprites instead of expensive bloom.
- The control room, lived-in: consoles with live-looking screens, cables along the floor and walls, storage racks and crates, a small hydroponics corner with plants under grow lights, crew lockers, a whiteboard or sticky notes, a coffee mug, mission patches (original designs, not real agency logos), signage and labels on equipment, wear and scuffs on surfaces, air vents, ceiling lights, a pressure-door with warning stripes.
- The wall screens: designed, not plain text. Clean typography, the agents' colors, small icons, gauges and charts for power and cash, real NASA imagery (e.g., orbital views of Jezero) as backgrounds where it fits. Do not use NASA logos or insignia.
- Outside: habitat modules connected by tunnels, an antenna dish, the cargo lander with scorch marks, a parked rover, solar panels with a light coating of dust, footprints and tire tracks in the regolith, survey flags or markers, small rocks scattered near the judge, the ice drill rig with moving parts and lights.
- The robots: polished materials (subtle metal or plastic shading), soft glow in their color, gentle idle bobbing, eyes that blink and glance around, small reactions when they speak or think.
- The storm: layered dust particles, the sky shifting toward brown, the sun dimming, wind-blown dust streaks past the window, panels and lights dimming in sync with the power model.
- Sound if feasible: a quiet hum inside, wind outside that rises with the storm, soft UI chimes when an agent speaks.

Assets: free CC0 or permissive libraries (e.g., Poly Haven textures and models, Kenney, Quaternius) and real NASA imagery. Verify every license, list them in a CREDITS.md, and never use real agency logos or any copyrighted characters.

Process (so the result is actually good, not just "more stuff"):
1. Render screenshots of the current inside view, outside view, and spectator view as a baseline.
2. After each polish round, render the same screenshots and have a separate reviewer subagent (with fresh context) score them for: looks effortful, consistent style, readable text, believable Mars. Fix the lowest-scoring issue first.
3. Send me the before/after screenshots at each milestone so I can redirect early.
4. Check frame rate on the iPhone after each round. If it drops below a steady 60 fps, cut detail (texture sizes, particle counts, far-away objects) before cutting anything near the judge.

Treat polish as Tier 2 except the performance checks. Commit, push, and update STATUS.md when done.
