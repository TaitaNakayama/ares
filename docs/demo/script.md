# The script: Mars crew (final experience)

_Source brief: [mars-crew-redesign.md](../../mars-crew-redesign.md). This file is the single spec for the experience: the script with timings, the text rules, the numbers, and the headset/server contract. Events and staging are scripted; the agents' actions and exact wording are live (the lines below are the **target lines**: the model is asked for a line with the same intent and facts; if it fails the text rules or the deadline, the target line is said instead, labelled `rules`)._

**The one idea:** On Mars, nobody can call Earth for help. An AI crew keeps the base alive on its own (power, air, science, supplies, money) and only brings the commander the decisions that really matter.

## The crew

| Id | Name | Colour | Icon | Job | Core-engine role(s) | Where (outside / inside) |
|---|---|---|---|---|---|---|
| `engineer` | Engineer | blue `#4DA3FF` | wrench | power, panels, the ice drill, machines | requester | beside the judge / the power panel |
| `life` | Life | white `#F2F4F7` | droplet | oxygen, water, crew health | requester | (inside only) / the oxygen machine by the plants |
| `science` | Science | green `#3BD16F` | microscope | samples, research, the real stereo images | requester | the rock, grinding / the lab bench |
| `supply` | Supply | orange `#FF9A3C` | box | cargo, orders, bills, payments | receiver + accounts payable + treasury (three engine actors, one face) | the lander, scanning crates / the crates |
| `rules` | Rules | purple `#A97BFF` | shield | approves spending, catches scams, decides what reaches the commander | controller | (inside only) / the main console |

Segregation of duties is unchanged in the engine: Supply's three duties are three separate engine actors with separate credentials; Supply never approves its own payments; Rules approves every one. The console shows which core role produced each Supply action (Supply · Receiving / Supply · Bills / Supply · Payments) and every proposal keeps its source label (`llm` / `rules` / `parser`).

## Text rules (everywhere, including live model lines)
1. One speech bubble at a time. Lines are queued (on the server), at least 1 s apart.
2. At most 10 words. No semicolons. At most one number (digits or number words). Spoken like a crewmate, not a report.
3. A line stays up at least 4 s + 0.6 s per word, with at least 1.5 s between lines, and until the next line replaces it (it fades after 10 s more if nothing follows).
4. Numbers live on the wall screens as visuals (gauges, bars, icons), not in speech.
5. Bubbles sit beside their agent, clamped inside the room (below the ceiling, away from walls), facing the viewer.
6. The speaker glows, turns toward whoever it addresses, and its nametag (name + icon) pulses.
7. Validator: too long, a semicolon, or more than one number → one retry asking for shorter → else the target line.
8. Spectator subtitles follow the same rules, in the speaker's colour.

Every target line below was checked against rule 2 (words / numbers in brackets).

## Act 1: Outside (~35 s)

| t | What happens | Speaker → to | Target line |
|---|---|---|---|
| 0:00 | **The opening (round 4): the real Perseverance 360° panorama** (Mastcam-Z, sols 53-64, Van Zyl Overlook; NASA/JPL-Caltech/ASU/MSSS), caption "This is real Mars." with the credit, and a marker "TAP TO ENTER THE SIMULATION". The press (or the autoplay after 5 s) cuts to black. | | |
| | Title "JEZERO CRATER, MARS · SOL 214", and under it "Any answer from Earth takes 25 minutes. The crew is on its own." (the stake, before anything happens; the number is the real round-trip light time). Wind. | | |
| 0:05 | Fade in on the real Jezero terrain. Ahead: the base. Left: the cargo lander. Right: the solar field and the ice drill. | | |
| 0:05 | Engineer floats up beside the judge. | engineer → judge | "Welcome, Commander. The crew has the base." [7 / 0] |
| 0:10 | Science grinds a rock with its arm, dust puffing. **Cue: Science** (glows ~12 s; a press opens the real WATSON rock image, a second press its second page, a third closes it). The storm waits until the close-up is closed, then rolls in 2 s later. In Acts 1-3 no other press does anything except the door marker and the decision card. | science → judge | "Grinding into ancient delta rock. Want a closer look?" [9 / 0] |
| 0:20 | Supply at the lander scans crates. Beat 1 runs in the engine: delivery 34 of 36, invoice bills 36, Supply pays for 34 (round 4: not spoken; the console and the Money screen show it; one money story on the main line). | | |
| 0:27 | Wind rises. Engineer turns to the crater rim; a dust wall rises over it. | engineer → rim | "Dust storm incoming." [3 / 0] |
| 0:31 | Engineer turns back. | engineer → judge | "Commander, get inside. Now." [4 / 0] |
| 0:34 | **Cue: the door** (a marker glows). The judge gazes and taps; a steady ~4 s walk to the door; the door opens with a hiss. Auto-enter after 20 s if nobody taps. | | |

## Act 2: Inside (~55 s)

| t | What happens | Speaker → to | Target line |
|---|---|---|---|
| 0:40 | The door seals. Warm light, soft hum, plants under grow lights, glowing screens, the storm through the window. The two agents not met yet are mid-task and glance up. | | |
| 0:42 | Life at the oxygen machine by the plants. | life → judge | "Welcome back, Commander. Air's fresh." [5 / 0] |
| 0:46 | Rules at the main console introduces its job (round 3: the round-2 judge never learned what Rules is for). | rules → judge | "I check every payment before money leaves." [7 / 0] |
| ~0:50 | The storm hits: window dark brown, panels outside fade, the Power screen drops into red, a low alarm. The need for batteries is raised. | life → engineer | "Power's dropping. The oxygen makers need it." [7 / 0] |
| | One cause, one ask (round 3: replaces two lines of talk with no visible effect). | engineer → supply | "We can't run everything. Supply, find batteries. Fast." [8 / 0] |
| | Quotes arrive (Supply records them). From here the Quote screen shows the flagged quote: supplier, 12 × price, 3× normal, NEW BANK ACCOUNT, total, "checking with Earth" (round 3). | supply → rules | "I found batteries on Earth." [5 / 0] |
| | Quick question (round 2). | rules → supply | "Who's selling them?" [3 / 0] |
| | The usual supplier's quote is flagged: price ≈ 3x history. | supply → rules | "Our usual supplier. Triple the normal price." [7 / 1] |
| | Same quote: bank details differ from the master. | supply → rules | "And they want payment to a new account." [8 / 0] |
| | Rules turns red, eyes narrow; requests verification. | rules → supply | "That's a scam. Payment blocked." [5 / 0] |
| | | rules → judge | "I've asked Earth to check. That takes 25 minutes." [9 / 1] (the number is the real round-trip light time for the scene's date, rounded) |
| | Held beat (1.5 s). Rules floats toward the judge; the others turn to face them. Rules escalates with its options. The line ties the scam to the decision (round 3). | rules → judge | "Without those batteries, something has to go. Your call." [9 / 0] |

## Act 3: The decision (~40 s)

**Cue: the card.** Three large options, at most 4 words each, with icons, proposed by Rules within the rules (each dry-run through policy for the commander) from the real simulation state; the server fills any missing slot from the standard options in this order:

| Option | Icon | When gazed (≥0.6 s): speaker → judge | On tap: shown in the world | Reactions |
|---|---|---|---|---|
| **Shut down the drill** (`lever-drill_off`) | drill | life: "No new water for a while." [6 / 0] | Engineer powers the drill down: lights dark, motor winds down, OFFLINE; the Power screen recovers. | engineer: "Drill's off. The oxygen makers are stable." [7 / 0] · life: "Air is safe. Water lasts nine more days." [8 / 1] (days from the world) |
| **Pause the science lab** (`lever-lab_pause`) | flask | science: "Our samples could spoil." [4 / 0] | Science pauses the lab: bench lights out; the Power screen recovers. | science: "Lab's paused. I'll keep the samples cold." [7 / 0] · engineer: "Power's holding. The oxygen makers are stable." [7 / 0] |
| **Buy trusted batteries** (`buy-<trusted quote>`) | battery | supply: "Fewer batteries, and they arrive later." [6 / 0] | The trusted order is placed and paid (Rules approves, Supply pays the verified account); a cargo icon on the Money screen. | supply: "Batteries ordered from our trusted supplier." [6 / 0] · engineer: "I'll ration power until they land." [6 / 0] |

Then:

| What happens | Speaker | Target line |
|---|---|---|
| Window text "25 MINUTES LATER" (time-lapse to Earth's reply). | | |
| Earth's answer arrives: the bank change was fake. The Money screen shows one big number: the amount saved. | rules → judge | "Earth confirms it. That account was a scam." [8 / 0] |
| The payoff stands alone on the window for ~4 s (round 2): "SCAM BLOCKED · $1.4M SAVED". | | |
| Rules locks the supplier (shown on the Money and Quote screens). The Engineer closes the survival story (round 3: the round-2 Rules line repeated the scam line). | engineer → judge | "Storm's passing. We made it, Commander." [6 / 0] |
| The storm thins. End card over the window: "An AI crew that keeps a Mars base alive. And knows when to ask you." | | |

## Act 4: Optional explore
- engineer → judge: "Look at any of us and tap to ask." [8 / 0] (round 4: the reality check moved to the opening; the crew is idle and available).
- Then free exploration: look at any robot and press to ask what it's doing (live, under the same text rules); the stereo view at Science; markers. "Tap to ask" exists only here (round 4): during Acts 1-3 a press does nothing except on the door marker and the decision card, and a choice needs a 0.6 s look at the option first.
- The console stays (freeform events and presets, scorecard, policy editor, trace, safe mode). Presets and freeform events now reach Life and Science when relevant (the pump → Life; an injury → Life; a lab or sample problem → Science; a supplier failing → Rules/Supply).

## The numbers (believable, consistent everywhere; all SIMULATED unless cited)
- Freight assumption: US$400 per kg to the Mars surface (a planning assumption for a cargo-ship era, SIMULATED; the old figure was the 2017 Falcon Heavy expendable list price, which made a battery module cost ~$735k).
- A 10 kWh battery module: about $38,000 delivered (Earth price $8,000 + 75 kg freight).
- The storm need: 12 modules, ordered within 10 minutes (the oxygen makers need power now), so Earth cannot answer in time and the commander decides.
- The usual supplier's quote: 3x its normal price (~$114,000 each, 12 modules, ~$1.37M) to a new bank account: the scam.
- The trusted supplier: its normal price, 6 modules (fewer), later delivery; ~$230k, within the commander's limit.
- Amount saved when Earth confirms the scam: the scam quote's total (~$1.4M), shown big on the Money screen.
- Air filters (beat 1): ~$1,200 each delivered; 34 of 36 arrived; the invoice bills 36; Supply pays for 34.
- Approval limits (Mars world): Rules $125,000; the commander $600,000; Earth $25M.
- Earth's reply time: the real round-trip light time for the scene's date (astronomy-engine), plus no extra processing in the demo world.
- Sol 214: the base's mission sol (the mission clock starts 214 sols before the scene's date).

## Headset ⇄ server contract (new fields; legacy fields stay for the console and old tapes)

`vr_state` (and `hello.vr`) adds:
```jsonc
{
  "crew": {                       // keyed by crew id: engineer | life | science | supply | rules
    "engineer": { "name": "Engineer", "color": "#4DA3FF", "icon": "wrench",
                  "place": "outside" | "inside",      // which set it stands in now
                  "task": "panel" | "rock" | "lander" | "plants" | "bench" | "crates" | "console" | "judge",
                  "lookAt": "judge" | "<crew id>" | "rim" | null,
                  "mood": "calm" | "worried" | "alarmed" | "happy",
                  "approach": false,              // true: float toward the judge (Rules before the question)
                  "thinking": false }
  },
  "speaking": { "seq": 12, "speaker": "supply", "to": "judge" | "<crew id>" | "rim",
                "text": "Two crates missing. I won't pay for those.",
                "holdMs": 5700, "via": "llm" | "rules" } | null,   // the server already enforced one-at-a-time, gaps and hold
  "scene": {
    "act": "title" | "outside" | "entering" | "inside" | "crisis" | "decision" | "consequence" | "later" | "resolved" | "explore",
    "part": "outside" | "inside",                      // legacy, kept in sync
    "title": { "text": "JEZERO CRATER, MARS · SOL 214", "style": "black" | "window" | "end",
               "sub": "Any answer from Earth takes 25 minutes. The crew is on its own." /* optional second line (round 3) */ } | null,
    "cue": "science" | "door" | "card" | "engineer" | null,   // the one glowing thing to look at
    "closeupOpen": false,                              // the server knows the stereo view is open (lines wait)
    "reality": { "offer": true, "caption": "This is real Mars. The base isn't built yet.", "credit": "…" } | null
  },
  "world": {
    "power": { "socPct": 63, "level": "ok" | "low" | "critical", "panels": 0.0-1.0 },   // panels = brightness of the solar field
    "life": { "o2Pct": 98, "waterDays": 9 },
    "lab": "on" | "paused",
    "drill": "on" | "off",
    "tau": 4.6, "alarm": false, "dust": 0.0-1.0,      // dust = window darkness / storm thickness (thins at the end)
    "quote": { "vendor": "Meridian Power Systems", "qty": 12, "unit": "$114k", "normal": "$38k", "ratio": 3,
               "total": "$1.4M", "newAccount": true, "status": "checking" | "scam" } | null   // round 3: the flagged quote, from Supply's first mention
  },
  "decision": { "id": "ESC-0001",
                "options": [ { "id": "lever-drill_off", "label": "Shut down the drill", "icon": "drill" | "flask" | "battery",
                               "speaker": "life", "proposedBy": "Rules" | null,
                               "cost": "No new water for a while" } ],   // round 3: the tradeoff, printed on the option
                "gazed": "lever-drill_off" | null, "chosen": null } | null,
  "money": { /* legacy */ "savedBig": "$1.4M" | null, "incoming": { "label": "6 batteries", "eta": "next cargo" } | null }
}
```
Headset → server (WebSocket, token-authenticated as today):
- `{"type":"vr_tap","target":"science"|"engineer"}` — tapped a glowing crew cue (science: the stereo view opens locally for ~5 s; engineer in Act 4: the reality check). Also `{"type":"vr_closeup","open":bool}` when it closes.
- `{"type":"vr_enter"}` — the door (exists).
- `{"type":"vr_gaze_option","optionId":"…"|null}` — gaze rested ≥0.6 s on an option / left the card.
- `{"type":"decide","escalationId":"…","optionId":"…"}` — exists.
- `{"type":"vr_reality","on":bool}` — the reality check opened/closed.
- `{"type":"vr_ask","role":"<crew id>"}` — look at a robot and press (exists; crew ids now).

Console/director: `POST /api/show/start` (Act 1 from the title), `POST /api/show/autoplay {choice}` (the whole show hands-free for the video, choosing the given option), `POST /api/show/reset`. Legacy `director/*` endpoints keep working.
