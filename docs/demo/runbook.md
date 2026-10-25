# Demo-day runbook (Sun 2026-10-25)

Everything runs on the MacBook; the phone is the headset. Do it in this order, 20 minutes before judging. The show is about 3 minutes: [script.md](script.md).

## 1. Network
- Turn on the iPhone's Personal Hotspot; join the Mac to it (venue Wi-Fi is slow and may isolate clients). The headset app tries 172.20.10.2-14 after its baked addresses.
- If the headset can't find the Mac within a minute: run `scripts/build-ios.sh` once while the Mac is on the hotspot (it bakes the current IPs), phone unlocked.
- The cloud layer needs the hotspot's internet. Without it the agents use the local model (slow, 10-15 s), then rules; the show still completes.

## 2. Start
```bash
scripts/start-local-llm.sh                    # fresh Ollama, model warm
node packages/server/src/main.ts              # :8787; look for "LLM layers: local ...; cloud ...; mode auto"
scripts/build-spectator.sh                    # Mac spectator, full screen in its own Space (swipe to it); --windowed to test
open http://localhost:8787                    # the console
```
Open Ares on the phone (unlocked, Auto-Lock Never) and put it in the viewer. The console header should show the headset connected and the model layers.

## 3. The run
- Console: **Reset**, then **Start show** (or `curl -X POST localhost:8787/api/show/start`). The title appears as the judge puts the headset on.
- **Autoplay show** (or `POST /api/show/autoplay` with `{"choice":"drill"|"lab"|"buy"}`) plays everything hands-free, choosing that option: use it for recordings, not for judges.
- The judge only follows the one glowing thing: Science (tap for the stereo image), the door (gaze and tap; auto-enters after 20 s), the card (gaze at an option to hear the tradeoff, tap to choose), then the Engineer (Act 4, the real panorama; tap again to come back).
- The console pill shows the act, the cue and the line being said, with its `llm` or `rules` badge. `GET /api/show/log` has the full log.
- After the end card: look at a robot and press to ask it; on the console, Inject → Report (presets or any text) comes back as a card from Life, Science or Rules.
- Expected timings from the automated check: inside at about 44 s, the card at about 111 s, explore at about 177 s.

## 4. If something breaks
| Symptom | Do |
|---|---|
| An agent is slow or says odd things | Console **SAFE MODE** (instant, every agent on rules). Mode group → auto to return. |
| Show stuck or judge lost | Console **Reset**, then **Start show**. Or **Autoplay show** to get to the end. |
| Phone loses the server | The headset plays a recorded run labelled REPLAY; the spectator shows REPLAY too. It reconnects on its own. |
| Spectator not following the head | Quit and relaunch `scripts/build-spectator.sh`. |
| Headset won't launch | The phone must be unlocked for `devicectl process launch`. |
| Phone hot | Take it out of the viewer between judges. |
| Everything fails | Play the recording in `docs/demo/`. |

## 5. Between judges
Console **Reset**; the phone stays in the viewer.

## 6. What is real, if asked
Real: terrain (HiRISE DEM of Jezero), sun (Mars24), storm power curve (Opportunity 2018), Earth-Mars light time, the Perseverance stereo pair (sol 1529; NASA/JPL-Caltech/ASU), the Van Zyl Overlook panorama (sols 53-64; NASA/JPL-Caltech/ASU/MSSS; rover-deck gaps filled and labelled SIMULATED), the LOCATION screen map (PIA23976). SIMULATED: suppliers, prices ($400/kg freight, ~$38k per battery module, the 3x scam quote, ~$1.4M saved), budgets and limits (Rules $125k, commander $600k, Earth $25M). Events and staging are scripted; the agents' actions and exact words are live.

Evals if asked: the 30-seed LLM story eval predates the crew redesign. Current: rules scorecard on 200 seeds, recall 91.7%, 0 payments to fraud accounts, 0 integrity failures; run `scripts/show-check.ts` for the live-show check (first run: 23/23 lines in the rules, 9/9 promised outcomes). Run it before submission.
