# ART: direction for the Ares scene

_The target every polish round is judged against. A judge putting on the headset should think "someone cared about every corner of this." Lived-in, detailed, cinematic, and a steady 60 fps on the iPhone 16 Pro._

## The one idea
**Shelter.** Outside is cold, dusty, huge and indifferent; inside is warm, cramped, cared for. Every lighting and material choice should sharpen that contrast. The storm is the moment the two meet through the window.

## Lighting
- **Exterior:** low, cold sun from the Mars24 position (real), long soft shadows, dusty haze that thickens toward the horizon; sky from pale butterscotch at the horizon to grey-brown overhead, shifting to deep brown as tau rises. No blue.
- **Interior:** warm key light from ceiling strips (3200 K look), cool fill from the screens (their own colours), small practical lights (grow lights magenta, status LEDs green/amber). Baked where possible (vertex colour or lightmap textures), emissive materials for screens and lamps, **fake glow sprites instead of bloom**.
- **Storm:** the exterior desaturates and darkens in sync with the power model (solar kWh per sol); interior lights dim a step when the power model says so; the window gets wind-blown dust streaks.

## Materials
- Interior surfaces: matte painted metal panels with scuffs and wear at edges and hand height, rubber floor with a subtle grid, brushed aluminium trims. Nothing is clean-white.
- Exterior: regolith with a detail texture near the feet (small rocks, grit), dust coating on panels and the lander, scorch marks under the lander engines.
- Robots: satin plastic shells with a soft rim glow in the agent's colour, dark glass faces, subtle metal joints.

## Set dressing (interior, the control room)
Consoles with live-looking screens; cables along floor and walls in trays; storage racks and crates with stencilled labels; a hydroponics corner (trays of greens under magenta grow lights); crew lockers with name tapes; a whiteboard with a sol plan and sticky notes; a coffee mug; original mission patches (no real agency logos); signage and labels on every piece of equipment; air vents; ceiling light strips; a pressure door with warning stripes.

## Set dressing (exterior)
Habitat modules joined by tunnels; an antenna dish; the cargo lander with scorch marks and its cargo pallets; a parked rover; a solar field with a light dust coating; footprints and tyre tracks; survey flags; small rocks scattered within a few metres of the judge; the ice drill rig with moving parts and lights; the landing pad with markings.

## The wall screens
Designed, not plain text: clean typography (one sans family, two weights), the agents' colours as accents, small icons, gauges and sparklines for power and cash, the Sol clock. Real NASA imagery as backgrounds where it fits (orbital views of Jezero, credited on the screen). No NASA logos or insignia.

## The robots
Gentle idle bob, eyes that blink and glance, a small reaction (lean, brighten) when speaking, three pulsing dots when thinking, a glow pulse when their action goes through. Nametags and speech bubbles in their colour.

## Sound (if time)
A quiet hum inside; wind outside that rises with tau; a soft chime when an agent speaks; a deeper tone when the commander decides.

## Rules that never bend
- Real data stays real and credited (terrain, sun, NASA imagery, every third-party asset in CREDITS.md). Invented things are labelled SIMULATED where they carry numbers.
- Readable at Cardboard resolution: text never below the current card sizes; high contrast.
- 60 fps on the phone after every round; detail is cut far-to-near, never the thing in front of the judge.
- Free assets only (CC0 or permissive, licence verified in CREDITS.md). No real agency logos, no copyrighted characters.

## Reference palette
Agent colours as today. Exterior: #C27A4A regolith, #E6B98A haze, #5A3A2A storm sky. Interior: #F2D7B0 warm key, #9FB7C9 screen fill, #FF5FD2 grow light, #3BE17A status green, #FFB347 status amber.
