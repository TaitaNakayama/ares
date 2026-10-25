# Mars crew redesign: the final experience

This REPLACES experience-redesign.md. Read this whole file before starting. Keep everything that already works (engine, policy, evals, spectator view, real imagery, hotspot, safe mode) and rebuild the experience on top of it.

## The one idea

**"On Mars, nobody can call Earth for help. An AI crew keeps the base alive on its own (power, air, science, supplies, money) and only brings the commander the decisions that really matter."**

Mars is the reason for everything: Earth is too far to ask, storms are deadly, and every choice trades one survival need against another. Money is one of the things the crew handles, not the whole job.

What a judge should walk away saying: "The robots kept the base alive, caught a scam, and asked me what to give up."

## The crew (5 agents, all real LLM agents)

| Agent | Color | Icon | Job |
|---|---|---|---|
| Engineer | blue | wrench | Power, solar panels, the ice drill, machines |
| Life | white | heart or droplet | Oxygen, water, crew health |
| Science | green | microscope | Samples and research; owns the real stereo images |
| Supply | orange | box | Cargo, orders, bills, payments |
| Rules | purple | shield | Oversight: approves spending, catches scams, decides what reaches the commander |

Implementation:
- Engineer, Life, and Science are real LLM agents in the world layer, with tools for their domains (e.g., Engineer: allocate power, power down/up equipment; Life: set life-support priorities, report reserves; Science: protect or pause the lab, report sample risk). Their tools change real simulation state (power, oxygen, water, lab status), and consequences follow from that state.
- Any of them can request a purchase through the core engine (they act as requesters).
- Supply is the face of the core engine's receiver, accounts-payable, and treasury roles. Rules is the controller.
- The core engine stays world-agnostic and unchanged in its controls: Supply can never approve its own payments; Rules approves every one; segregation of duties holds.
- Honesty: the console shows which core role produced each Supply action (receiving, bill-checking, or paying), and every action keeps its honest source label (llm / rules / parser).
- Same safety design as before: facts come from engine/simulation state, lines are validated, rules fallback, safe mode.

## Text and interaction rules (apply everywhere, including live LLM lines)

1. One speech bubble at a time. Lines are queued, with at least 1 second between them.
2. Max 10 words per line. No semicolons. At most one number per line. Spoken like a crewmate, not a report.
3. Each line stays visible for at least 2.5 s plus 0.4 s per word, and until the next line replaces it.
4. Numbers live on the wall screens as visuals (gauges, bars, icons), not in speech.
5. Bubbles sit beside their agent, clamped inside the room (below the ceiling, away from walls), always facing the viewer. Fix the purple agent's bubble clipping into the roof.
6. Whoever speaks glows, turns toward the judge, and its nametag (one-word name + role icon) pulses.
7. The validator enforces rules 2 for LLM lines: too long, semicolons, or too many numbers = retry once shorter, then the rules line.
8. Spectator subtitles follow the same rules, in the speaker's color.

## The script (target lines; events are scripted, agents' actions and exact wording are live)

Before the headset goes on, I'll say a short intro myself. The experience starts after that.

### Act 1: Outside (~35 s)
- 0:00 Black. Text: "JEZERO CRATER, MARS · SOL 214." Wind.
- 0:03 Fade in on real Jezero terrain. Ahead: the base. Left: a cargo lander. Right: the solar field and the ice drill.
- 0:05 ENGINEER floats up: "Welcome, Commander. The crew has the base."
- 0:10 SCIENCE, grinding a rock with its arm, dust puffing: "Grinding into ancient delta rock. Want a closer look?" If the judge taps Science: the real Perseverance stereo image in 3D for ~5 s with its caption, then back. If not, continue.
- 0:20 SUPPLY at the lander, scanning crates (hologram 34/36): "Two crates missing. I won't pay for those."
- 0:27 Wind rises. ENGINEER turns to the crater rim; a dust wall rises over it: "Dust storm incoming."
- 0:31 ENGINEER, back to the judge: "Commander, get inside. Now."
- 0:34 A marker glows on the door. The judge gazes and taps, walks to the door over ~4 s at a steady speed; the door opens with a hiss.

### Act 2: Inside (~55 s)
- 0:40 The door seals. Warm light, soft hum, plants under grow lights, glowing wall screens, the storm visible through the window.
- Meet them at work (no roll call): the two agents the judge hasn't met are mid-task and glance up as the judge enters.
  - LIFE, tending the oxygen machine beside the plants: "Welcome back, Commander. Air's fresh."
  - RULES, at the main console: "Quiet day. Nothing suspicious."
- ~0:50 The window turns dark brown, the panels outside fade, the Power screen drops into red, a low alarm.
- LIFE: "Power's dropping. The oxygen makers need it."
- ENGINEER: "We can't run air, drill, and lab."
- SUPPLY: "I found batteries on Earth."
- SUPPLY: "This quote is triple the normal price."
- SUPPLY: "And they want payment to a new account."
- RULES turns red, eyes narrowing: "That's a scam. Payment blocked."
- RULES: "I've asked Earth to check. That takes 25 minutes." (Use the real round-trip light time for the scene's date.)
- RULES floats toward the judge; the others turn to face them: "We can't wait, Commander. What do we give up?"

### Act 3: The decision (~40 s)
- A decision card with three large options, max 4 words each, with icons. Options are proposed by the agents within the rules, based on the real simulation state (typical: Shut down the drill / Pause the science lab / Buy trusted batteries).
- When the judge's gaze rests on an option, the affected agent leans in and speaks its tradeoff (e.g., Drill -> LIFE: "No new water for a while." Lab -> SCIENCE: "Our samples could spoil." Batteries -> SUPPLY: "Fewer batteries, and they arrive later.").
- The judge taps. The consequence is SHOWN in the world (drill lights go dark and motor winds down / lab lights go out / a cargo icon appears on the Money screen), the Power screen recovers, and the relevant agents react in one short line each (e.g., ENGINEER: "Drill's off. The oxygen makers are stable." LIFE: "Air is safe. Water lasts nine more days.").
- Text on the window: "25 MINUTES LATER."
- RULES: "Earth confirms it. That account was a scam." The Money screen shows one big number: the amount saved.
- RULES: "Supplier blocked. The base is safe, Commander."
- The storm thins. End card over the window: "An AI crew that keeps a Mars base alive. And knows when to ask you."

### Act 4: Optional explore
- ENGINEER: "Want to see where we really are?" If the judge taps: the base, crew, and props fade into the real Perseverance panorama. Caption: "This is real Mars. The base isn't built yet." (plus credit).
- Then free exploration: tap any robot to ask what it's doing; the stereo view; the other markers.
- The laptop console stays as is (freeform events and presets, scorecard, policy editor, trace, safe mode). Update the presets and freeform handling so Life and Science respond to relevant events too.

Must fix: the "amount saved" number. The current $88.9M is far too large for emergency batteries and a judge will notice. Make all battery prices and the saved amount believable, and keep them consistent everywhere.

## Making it feel natural (the priority)

The interaction should feel like a real crew, not a scripted sequence. Specifically:
- Agents look at whoever they're talking to: at the judge when addressing them, at each other when reacting to each other.
- Agents keep doing their jobs in the background (Life tending plants, Engineer checking a panel, Supply sorting crates, Science at its bench), with idle motion and occasional glances at the judge.
- Pacing feels conversational: brief pauses between lines, quicker back-and-forth when urgent, a held beat before Rules asks the question.
- Nothing appears without a reason: every marker, card, and screen change follows from what just happened.
- The judge always knows what to do next, without instructions: one obvious glowing thing to look at when an action is needed.
- Sound supports it: storm wind rising, the alarm, the door hiss, a soft tone when someone speaks, quiet after the storm passes.

## Iterate until it feels intuitive and natural

Run the whole experience over and over, and improve it each round:
1. Write the full script with timings into docs/demo/script.md first, and check every line against the text rules.
2. Build, then run the full experience end to end with live agents, at least 10 times across different seeds and each of the three choices.
3. After each round, render screenshots and a short recording of the key moments (outside, entering, the crisis, the decision card, the consequence, the end card, the reality check).
4. Have a separate reviewer subagent with fresh context act as a first-time judge who has never heard of the project. It reviews the recordings/screenshots and the subtitle log and answers:
   - Could I tell who was speaking every time, and what each robot does?
   - Could I read every line before it disappeared?
   - Did anything feel robotic, rushed, confusing, or unmotivated?
   - Did I always know what to do next?
   - Can I state the one idea in a sentence?
   Score each 1-10 and list the worst issues.
5. Fix the worst issues first, then repeat. Keep going until every score is at least 8 and the reviewer can state the one idea correctly. Use a fresh reviewer each round so it doesn't get used to the flaws.
6. Also run an automated check over all live runs: no line breaks the text rules, every promised outcome holds, no bubble overlaps geometry, frame rate stays at a steady 60 fps on the phone.
7. Send me the screenshots, the recording, the scores, and the script after each round so I can redirect.

## Order and time

It's late Saturday and the Devpost deadline is Sunday 9:00 PT. Order of work:
1. The crew change (Life and Science as real agents, Supply as the face of the finance roles), the text and bubble rules, and the new script.
2. The natural-interaction details and iteration rounds.
3. Act 4 and console updates.
4. Re-record the demo video and update README, pitch, and Devpost to the new idea and crew.

If time runs short, cut in this order: extra iteration rounds beyond the scores target, Act 4 polish, background idle animations. Never cut: the text rules, the crisis and decision, the visible consequence, honest labels.

Commit and push at each milestone, and keep STATUS.md updated.
