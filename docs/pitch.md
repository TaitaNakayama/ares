# Pitch (about 3 minutes)

**The one idea:** On Mars, nobody can call Earth for help. An AI crew keeps the base alive on its own and only brings the commander the decisions that really matter.

Setup before each judge: console open, **Reset**, phone in the viewer, spectator on the laptop. Spoken parts are in quotes. Full timeline: [script.md](demo/script.md).

## 0:00-0:30 Before the headset goes on (you say this)
"On Mars you can't call Earth for help. A message takes 25 minutes round trip, and a dust storm doesn't wait. So the base runs itself. Five AI robots handle power, air, science, supplies and money, and they only come to you for the decisions that really matter. You're the commander. Put this on."

(Press **Start show** as the headset goes on. The judge does not need instructions: one glowing thing at a time shows what to look at.)

## 0:30-2:30 What the judge experiences (about 2 minutes; stay quiet, point at the spectator if they want context)
- **Outside**, on the real Jezero terrain. The Engineer welcomes them. Science offers the real Perseverance stereo image in 3D (tap it). Supply finds two crates missing and won't pay for them. A storm rises. "Commander, get inside."
- **Inside**, the storm hits and power drops. Supply finds batteries on Earth at triple the normal price, to a new bank account. Rules: "That's a scam. Payment blocked." It asks Earth, which is 25 minutes away, and then asks the judge: "What do we give up?"
- **The decision**: three options on a card (shut the drill, pause the lab, buy trusted batteries). Looking at one makes the affected robot say the cost. The judge picks, and the base changes: lights go dark, power recovers. "25 minutes later" Earth confirms the scam: "SCAM BLOCKED · $1.4M SAVED."
- **Optional**: "Want to see where we really are?" opens the real Perseverance 360° panorama. "This is real Mars. The base isn't built yet."

## 2:30-3:00 How it works, in 30 seconds (you say this)
"The robots are language-model agents, but they only propose. Every action goes through deterministic controls: price statistics, three-way match, bank verification, spending limits, segregation of duties. Only an approved action can move money, and if a model is slow or off-script, plain rules take over and the log says so. Every action is labelled by what produced it, and SAFE MODE switches every agent to rules instantly. What the robots say follows text rules: one bubble at a time, ten words at most, one number, numbers on the wall screens. A line that breaks a rule is retried shorter, then replaced. Events are scripted; what the agents do and say is live."

## Close
"The robots kept the base alive, caught a scam, and asked you what to give up. Independent reviewers attacked the controls three times and we fixed everything they found. On 200 fresh scenarios the rules brains paid no fraudster and the books always balanced. And the engine never mentions Mars: the same code could run a ship or a restaurant."

## Questions and deep dives
- **Is the crew really AI?** Yes, five model-backed agents. Engineer, Life and Science use their own tools on the base (the drill, power rationing, life support, the lab); the world checks each use. Supply is one face for three separate engine roles (receiving, bills, payments) so segregation of duties holds. Rules approves every payment.
- **Ask a robot**: look at one and press; it answers live from the current state.
- **Invent an event** on the console (after the show): free text or a preset. Broken pump and injury go to Life, supplier bankruptcy to Rules, and a card comes back from that crew member.
- **SAFE MODE**: every agent drops to rules instantly.
- **Rogue Rules** (console): a malicious Rules brain approves the fraudster, pays without approval, confirms the fake bank. Every attempt is refused by policy.
- **Trace** (Ledger, click a payment): request, quote, order, payment, every rule that passed, who proposed and who approved, the hash chain.
- **Policy editor**: change a limit and replay; give the controller payment rights and it is rejected.
- **Scorecard**: 200 fresh seeds in seconds. Recall 91.7% overall; subtle 3-7% overpricing is caught far less often, and we show that on purpose.
- **Real vs invented**: real terrain (HiRISE), real sun (Mars24), real storm power curve (Opportunity 2018), real light time, real Perseverance images with credits. Suppliers, prices ($400/kg freight, ~$38k per battery module) and budgets are SIMULATED.

## Numbers we quote
The earlier 30-seed LLM story eval (30/30 promised outcomes, 4% rules fallbacks) predates the crew redesign; say so if asked. Live-show checker (`scripts/show-check.ts`): first run 23/23 model lines within the text rules and all 9 promised outcomes; run again before submission.

## If something breaks
- **Model slow or odd**: SAFE MODE. The show still runs.
- **Connection lost**: the headset plays a recorded run labelled REPLAY.
- **Show stuck**: **Reset**, then **Start show** or **Autoplay show**.
- **Last resort**: the screen recording in `docs/demo/`.
