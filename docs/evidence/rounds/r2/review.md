# Round 2 judge review (cold viewer)

## 1. Who speaks, and what each robot does
Speaker is clear every time: a colour-coded name chip, bubble and bottom subtitle all agree.
- Engineer (blue, boxy, antenna): power and the base; warns of the storm.
- Science (green): rock samples and the lab.
- Supply (orange, round): buys crates and batteries; says "I won't pay for those".
- Life (white, drop shape): oxygen, "air must come first".
- Rules (purple, cube with red slit eyes): a checker or compliance robot. It blocks the scam. Its job is never stated, so I only inferred it.
Outside, Science and Supply labels are tiny and far away (03-outside.jpg). Several speakers are off-screen or only half framed (frames 0048, 0072).

## 2. Could I read every line?
Mostly. The lines are short (7-11 words, so about 5-7 s held), and the subtitle bar helps. Problems:
- The in-world bubble is often half out of frame or crossed by tags (0072: the Rules bubble sits on the Engineer tag). The bottom subtitle saves it.
- Lines 14 and 15 (97 s, 104 s) are 7 s apart, and the "triple the price" quote carries the key fact. I missed the price jump. The bank-account change is clear.
- 90-consequence.jpg shows the Supply line over the decision overlay, with the card, the tags and the subtitle all stacked. Too much text at once.
- 101-later.jpg: "25 MINUTES LATER" is half off-frame at the top, and the Engineer is silent, so I did not know what it meant.
- 118-explore.jpg: the tagline fades behind the speaking robot and the Engineer bubble is cut off ("where").

## 3. Robotic, rushed, confusing, unmotivated
- Line 8 (57 s, crisis): "Good catch on the missing crates, Supply. Otherwise quiet." This is a non-sequitur. It reads as filler, the only uncached LLM line, and it sits right where the crisis should start.
- Line 3 (18.8 s): "Two crates are missing. I won't pay for those" is never followed up. It is an unmotivated setup, and I did not realise it was the three-way-match point.
- 33-crisis.jpg: 20 s of banter inside before the first stake. Beats 3 to 5 (lines 9-12) are talk between robots with no visible consequence. The red POWER-CRITICAL screen (0048) is the only visual cue, and it is small.
- The Mars/dust-storm setup in 24-entering.jpg is a good opening, but the 5 s title card (01) then a 25 s wait before a stake is slow.
- 78-decision.jpg: I did not know I should pick, or how. "Look at the card" does not say tap or gaze. The decision card timing (line 18 at 126 s, choice by about 150 s) hides what an actual wait would feel like. Line 21, "trusted supplier has fewer batteries, arriving later", lands as a cost, but the card title reads as a vague "SUPPLY WILL SAY".
- Line 24 vs 25 (168 s, 178 s) says the same thing twice. "SCAM BLOCKED $1.4M SAVED" (108) is the best payoff but arrives about 2.5 minutes in.
- The "$1.4M saved" figure has no visible source (where does 1.4M come from?). "SIMULATED" is tiny.
- 90 s to 130 s: the scam is blocked by Rules at 111 s, before the Commander is asked anything. The Commander's decision is about power, not about the scam, so the two plots feel unconnected.

## 4. Did I know what to do next?
Mostly passive. The tags "tap to ask" appear but nothing tells me why to tap. The "LOOK AT Engineer" hint appears at the end (118) and "Tap to return" in the real-Mars view is good. A judge would be lost at 78-decision.jpg (how do I choose?) and after 108 (is it over? what now?). The final "want to see where we really are?" arrives at 194 s with no prompt to answer.

## 5. The one idea
"An AI crew runs a Mars base's purchasing and money on its own, blocks a scam payment by rule, and only calls the human when it needs a real decision."
I got most of this. "Blocks scam by rules, saves $1.4M" is clear, "knows when to ask you" is less so.

## Scores (1-10)
1. Speaker and role clarity: 7
2. Readability: 6
3. Feeling natural (not robotic, rushed or confusing): 5
4. Knowing what to do next: 4
5. Single-idea clarity: 6

## Worst issues
1. 33-crisis.jpg, line 8: filler "Good catch on the missing crates... Otherwise quiet." Fix: cache a line that states the stake ("Power is falling. Something has to go") or cut it.
2. 78-decision.jpg: no cue on how to choose. Fix: say "Gaze at a card for 2 s to choose" in the prompt, and say that the choice has costs.
3. Lines 9-12 (64-84 s): robots talk to each other with no visible cause. Fix: link each line to a screen change (red power bar, a pointer to the dial) and cut to 2 lines.
4. 101-later.jpg: "25 MINUTES LATER" is off-frame and unexplained. Fix: centre it and have a robot say "25 minutes passed. Earth replied."
5. Lines 14-15: the quote facts (triple price, new bank account) go by quickly. Fix: show the quote on the Supply screen and highlight the "new account" line.
6. Lines 24 and 25 repeat. Fix: merge into one line with the $1.4M figure.
7. 03-outside.jpg: the title card covers the first scene, tags are small. Fix: start the title card sooner and enlarge the Science and Supply labels.
8. Rules role is never introduced. Fix: Rules says "I check every payment against the rules" in line 7.
