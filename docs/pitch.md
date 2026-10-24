# Pitch (2:00 core plus optional deep dives)

Setup before each judge:
- Phone in the viewer, on a fresh run (console → **Reset**).
- Console open on the Live feed.
- Speak while they look.

## 0:00-0:20 Hook (judge puts the headset on)
"You're the commander of a Mars base. Nobody here handles money. The finance team, the bank and the suppliers are on Earth, 25 light-minutes away. Five AI agents run purchasing and payments for you. A model proposes, deterministic controls decide, and plain rules are the floor. They have to be *more* trustworthy than a person, not less."

## 0:20-0:45 Beat 1 (press **Next beat**): routine
"Cargo Keeper, the green one, just counted a delivery: 34 air filters, two short. The invoice bills 36. Bill Checker matched it against the order and the receipt and pays for 34. No human needed."

## 0:45-1:20 Beats 2-5 (press **Next beat**): the storm and the fraud
"A dust storm. Look out the window: real Jezero terrain from NASA. Solar power drops on Opportunity's real 2018 curve. The Engineer, in orange, needs 40 batteries before the cargo manifest closes."

"Here's the trap. The usual supplier's quote is three times their price history and asks for payment to a new bank account. That's business email compromise, and it hit 74% of companies last year. Bill Checker flags both, using statistics, not the model's opinion. Rule Keeper, in purple, reasons about it, asks Earth to verify by call-back and blocks it. Earth can't answer before the deadline, so it comes to you."

## 1:20-1:40 Beat 6: the judge decides
"Look at a card and press the button. Every option was checked against policy for you before it was shown, including ones the agent proposed itself: buy 15 from a supplier we've verified, wait, or shut the ice drill."

## 1:40-2:00 Beat 7 and the close
"Earth's answer just arrived, after the real light-time delay: the bank change was fake. $89 million saved. Here's the key part: the agents only *propose*. Deterministic code checks every action against policy before anything moves, and if a model is slow or off-script, the rules answer and the proposal is labeled that way. Independent reviewers attacked the controls three times. We fixed everything they found, and on 100 held-out scenarios, with the rules brains, it never paid a fraudster."

## Deep dives (if they stay)
A. **Ask an agent**: look at a robot, press the button. It answers live from current state. A "thinking" face shows while a model decides.
B. **Invent an event** (console → Inject → Report, after the story): type anything, or use a preset (broken water pump, crew injury needing medicine, supplier bankruptcy). The agent routes it to the commander with a recommendation.
C. **SAFE MODE** (console): every agent drops to the deterministic rules instantly. The story still runs.
0. **Rogue agent** (console → **Rogue Rule Keeper**, then Autoplay): "Now I've replaced the Rule Keeper's brain with a malicious one. It approves the fraudster, pays without approval, and confirms the fake bank itself." The headset shows "REFUSED BY POLICY" on each attempt. "The agent's intent doesn't matter, only what the policy lets through." Turn it off afterwards.
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
   - Eval so far: 3 seeds with the cloud layer, all 7 beats in order 3/3; a 30-seed run is next.
   - Money moves only through the executor, with one-shot ledger tokens.
6. **Hyphenate's own scenario:** use Inject to create a need, quote or invoice as they describe it.

## If something breaks
- **No connection:** the headset plays the recorded run (the "Offline replay" label shows). Keep the console story going on the laptop. The Mac spectator view shows REPLAY too.
- **A model is slow or down:** the rules answer and the story continues; or press SAFE MODE.
- **Headset is fine but the console isn't:** run `curl -X POST localhost:8787/api/director/next`.
- **Last resort:** the screen recording in `docs/demo/`.
