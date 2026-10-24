# Pitch (about 3 min core plus optional deep dives)

Total demo: part 1 outside is about 40 s (autoplay), then the control-room story is about 2-3 min.

Setup before each judge:
- Phone in the viewer, on a fresh run (console → **Reset**).
- Console open on the Live feed.
- Speak while they look.

## 0:00-0:30 Part 1, outside (judge puts the headset on; about 30 s of speaking over the ~40 s walk)
"You're the commander of a Mars base, standing on the real Jezero terrain. Nobody here handles money. The finance team, the bank and the suppliers are on Earth, 25 light-minutes away. Five AI agents run purchasing and payments for you. A model proposes, deterministic controls decide, and plain rules are the floor. They have to be *more* trustworthy than a person, not less."

"A cargo lander just arrived. Cargo, the green one, counted the boxes: 34 air filters, two short. The invoice bills 36. Bills matches it against the order and the receipt and pays for 34. No human needed. Walk on: the crew scientist is sampling the delta rock. Look at her and tap, and you get a real Perseverance close-up with its NASA credit. Then the Engineer at the solar field warns the storm is rising. Look at the base door and tap to go inside."

(Beat 1 happens here, at the pad. Part 1 runs on autoplay in about 40 s; if the judge is slower, let them. Press **Next beat** when they are inside.)

## 0:30-1:20 Beats 2-5 (press **Next beat**): the storm and the fraud
"A dust storm, the one you saw rising outside. Look out the window: real Jezero terrain from NASA. Solar power drops on Opportunity's real 2018 curve. The Engineer, in orange, needs 40 batteries before the cargo manifest closes."

"Here's the trap. The usual supplier's quote is three times their price history and asks for payment to a new bank account. That's business email compromise, and it hit 74% of companies last year. Bills flags both, using statistics, not the model's opinion. Rules, in purple, reasons about it, asks Earth to verify by call-back and blocks it. Earth can't answer before the deadline, so it comes to you."

## 1:20-1:50 Beat 6: the judge decides
"Look at a card and press the button. Every option was checked against policy for you before it was shown, including ones the agent proposed itself: buy 15 from a supplier we've verified, wait, or shut the ice drill."

## 1:50-2:30 Beat 7 and the close
"Earth's answer just arrived, after the real light-time delay: the bank change was fake. $89 million saved. Here's the key part: the agents only *propose*. Deterministic code checks every action against policy before anything moves, and if a model is slow or off-script, the rules answer and the proposal is labeled that way. Independent reviewers attacked the controls three times. We fixed everything they found, and on 100 held-out scenarios, with the rules brains, it never paid a fraudster."

## Deep dives (if they stay)
A0. **Look around the room**: the control room is textured and lived-in (lockers with fictional name tapes, hydroponics, wall screens, a LOCATION screen on the real Jezero orbital map). The Mac spectator view follows the judge's position and orientation through both parts.
A. **Ask an agent**: look at a robot, press the button. It answers live from current state. A "thinking" face shows while a model decides.
B. **Invent an event** (console → Inject → Report, after the story): type anything, or use a preset (broken water pump, crew injury needing medicine, supplier bankruptcy). The agent routes it to the commander with a recommendation.
C. **SAFE MODE** (console): every agent drops to the deterministic rules instantly. The story still runs.
0. **Rogue agent** (console → **Rogue Rules**, then Autoplay): "Now I've replaced Rules' brain with a malicious one. It approves the fraudster, pays without approval, and confirms the fake bank itself." The headset shows "REFUSED BY POLICY" on each attempt. "The agent's intent doesn't matter, only what the policy lets through." Turn it off afterwards.
1. **Trace** (console → Ledger → click the last payment): the request, quote, PO, payment, every rule that passed, who proposed and who approved, and the hash chain.
2. **Policy changes behavior** (Policy tab):
   - Lower the Commander's emergency limit from $12M to $5M and apply. Reset and replay: the option becomes "Buy 6".
   - Try to give the controller payment rights. It's rejected for segregation of duties.
3. **Your own invoice** (Inject → Paste a document): paste any invoice text. Change the bank or bill too many units, then watch the robots catch it.
4. **Scorecard** (run 50 fresh seeds): about 4 s.
   - 100% on blatant errors.
   - 35% on subtle +3-7% overpricing, with the trade-off curve. We show where it fails on purpose.
5. **Architecture:**
   - The engine never mentions Mars; the same code runs a restaurant or a research ship.
   - Three model layers: cloud first when online, a local model as the offline fallback (slower: 9-17 s on a cold prompt), rules as the floor. Every proposal is labeled `llm`, `rules`, `parser` or `human`.
   - Statistics, the three-way match, bank verification and escalation routing stay deterministic.
   - Eval: 30 seeds with the cloud layer, every promised outcome on 30/30, 271 model decisions, 22% fell back to rules, median 3.3 s per decision.
   - Money moves only through the executor, with one-shot ledger tokens.
6. **Hyphenate's own scenario:** use Inject to create a need, quote or invoice as they describe it.

## If something breaks
- **No connection:** the headset plays the recorded run (the "Offline replay" label shows). Keep the console story going on the laptop. The Mac spectator view shows REPLAY too.
- **A model is slow or down:** the rules answer and the story continues; or press SAFE MODE.
- **Headset is fine but the console isn't:** run `curl -X POST localhost:8787/api/director/next`.
- **Last resort:** the screen recording in `docs/demo/`.
