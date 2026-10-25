# Demo-day runbook (Sun 2026-10-25)

Everything runs on the MacBook; the phone is the headset. Do it in this order, 20 minutes before judging. The show is about 5 minutes: [script.md](script.md).

## 1. Network (hotspots are not allowed at judging)
- **Primary: the USB cable.** Phone to Mac with a long cable (2 m or more). The phone reaches the Mac over the cable's own link (iPhone USB, a 169.254.x address) with no Wi-Fi or hotspot at all; the headset app tries every baked address at once and keeps the first that answers, and a cut link comes back in under a second (device-tested: 14/14 forced drops, 0.42 s). Keep the cable plugged in for the whole session.
- Mac on venue Wi-Fi for the cloud model. Without internet the agents use the local model (slow, 10-15 s), then rules; the show still completes.
- Backup: venue Wi-Fi for the phone too, only if the venue lets devices reach each other (many don't).
- Last resort: the offline replay (the recorded run, no live agents).
- If the headset can't find the Mac within a minute: run `scripts/build-ios.sh` once with the cable in and the phone unlocked (it bakes the current addresses).
- Check: `curl -s localhost:8787/api/debug/pose` shows `openHeadsetSockets: 1` and a small `msSinceRelay` while the app is open.

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

Evals if asked: the 30-seed LLM story eval predates the crew redesign. Current: rules scorecard on 200 seeds, recall 91.7%, 0 payments to fraud accounts, 0 integrity failures; live-show check (`scripts/show-check.ts`): 10/10 runs kept all 9 promised outcomes, 260/260 lines by the model within the text rules (most replayed from the response cache, labelled `cached`; the empty-cache run had 26/26 fresh).
