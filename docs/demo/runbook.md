# Demo-day runbook (Sun 2026-10-25)

Everything below runs on the MacBook; the phone is the headset. Do it in this order, 20 minutes before judging.

## 1. Network
- Turn on the iPhone's Personal Hotspot; join the Mac to it (venue Wi-Fi is slow and may isolate clients). The headset app tries 172.20.10.2-14 after its baked addresses.
- If the headset can't find the Mac within a minute: `scripts/build-ios.sh` once while the Mac is on the hotspot (it bakes the current IPs), phone unlocked.
- Cloud (OpenAI) needs the hotspot's internet. Without it the agents use the local model (slow, 10-15 s) and then rules; the story still completes.

## 2. Start
```bash
scripts/start-local-llm.sh                    # fresh Ollama (memory back to ~9 GB), model warm
node packages/server/src/main.ts              # :8787; watch for "LLM layers: local qwen3.5:9b; cloud gpt-6.1-sol; mode auto"
scripts/build-spectator.sh                    # Mac spectator, full screen in its own Space (swipe to it)
open http://localhost:8787                    # the console, in a browser on the laptop
```
Then open Ares on the phone (unlocked, Auto-Lock Never), put it in the viewer. The console header should show the headset connected and "LLM local … · cloud …".

## 3. The run (about 3-3.5 min)
- Console → Director → **Autoplay** (or press **Next** for each beat yourself: pad → science → solar → door → inside; then the agents run).
- Part 1 (≈40 s): the judge is at the landing pad; walks to the scientist (gaze + press: the real Perseverance close-up); to the solar field (storm warning); to the door (gaze + press to enter; auto-enter after 25 s).
- Part 2: the delivery/invoice beat resolves, the storm hits, the fake quote is flagged, Rules asks Earth and escalates: the judge decides on the card (one option is tagged "proposed by Rules"). Earth's answer arrives after a time-lapse; "$88.9M saved".
- Judge autonomy: look at a robot and press (it explains itself); after the story, Console → Inject → Report (the three presets or any text).

## 4. If something breaks
| Symptom | Do |
|---|---|
| An agent is slow or says odd things | Console → **SAFE MODE** (instant; all agents on rules). Mode group → auto to return. |
| Phone loses the server | The headset plays the recorded run, labelled REPLAY; the spectator shows REPLAY too. Reconnects on its own. |
| Spectator not following the head | Quit and relaunch `scripts/build-spectator.sh`; it reconnects to the headset's pose stream. |
| Phone hot | It is Release at 60 fps; take it out of the viewer between judges. |
| Story stuck before the decision | Console → Director → Next (or Reset + Autoplay; 40 s to be back at the storm). |
| Dust inside the room | Fixed (f5fb69b); if seen, it's an old build: reinstall. |

## 5. Between judges
Console → **Reset** (fresh seed or the demo seed), phone stays in the viewer. The agents' first decisions after a reset come from the cloud in 2-8 s each.

## 6. What is real, if asked
Terrain: HiRISE DEM of Jezero; sun: Mars24; the scientist's close-up: Perseverance WATSON "Kenmore", sol 1526 (PIA26576); the LOCATION screen: PIA23976; power curve: Opportunity 2018 storm (JPL). Suppliers, prices, budget, crew names: SIMULATED/fictional. The agents: a model proposes, deterministic controls decide, rules are the floor; 30-seed eval 30/30 on every promised outcome; 4% of decisions fell back to rules.
