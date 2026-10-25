# Spectator review, fix7 (audience view)

Issues, most damaging first:

1. **The decision card never shows what was chosen** (frames 061-073). The card shows "WHAT DO WE GIVE UP?" with three options and a LOOKING tag that follows the gaze. By 073 the card is gone and the Engineer says "Drill powered down", and nothing on screen says "Commander chose: Shut down the drill". The choice is only visible as "ICE DRILL OFFLINE". Fix: hold a "CHOSEN: Shut down the drill" banner for about 3 s after the tap.
2. **The decision question is unclear** (061-067). The question ("What do we give up?") appears without context, and the situation (a power shortfall, with the scam already blocked) is not restated. Fix: add a one-line header such as "Power is short. Pick one to cut."
3. **The speaker bar sits on top of the card's top edge and is cramped** (061-067). Both the subtitle and the card are up at once, and the card fills the bottom third. The "LOOK AT AN OPTION" pill sits tight against the subtitle bar (about 15 px gap). In 061 the pill also overlaps the "Engineer" 3D tag. Fix: add spacing, or put the pill inside the card.
4. **Subtitle ownership is ambiguous when the speaker is off screen** (013, 029, 037, 045, 077). The subtitle label (ENGINEER, SUPPLY, RULES) is clear, but the speaker is usually not in frame, so you can't tell who is talking. Fix: add a small "off-screen" arrow, or hold the camera on the speaker.
5. **The "SCAM BLOCKED / $1.4M SAVED" title is poorly placed** (085, 097). The dark band is wide and semi-transparent. The 3D scene shows through it, and the gaze dot sits right on "$1.4M" (085). The closing title in 097 has the same problem: "$1.4M" shows through the band, and the gaze dot lands on "when to ask you". Fix: make the band opaque, and hide the gaze dot during titles.
6. **3D world labels clip and interfere with the subtitle** (033, 045, 089). The world-space "Engineer" tag runs under the LIVE badge (033), and the "Rules" tag clips behind the progress badge (045, 081). In 089 the red "BLOCKED" banner pokes out under the subtitle bar. Fix: clamp or fade tags near the screen edges and the overlay zones.
7. **Half-cut world screens read as clutter** (017, 021, 053-057). The camera sweep shows chopped text ("hinking...", "am is handling it", a half-cut "Checking"). The cut-off screens compete with the subtitle for attention. This partly comes from the sweep, but the tags still add noise. Fix: show a single prominent speaker cue and fade the other tags.
8. **The "thinking..." tag and the top badge fight** (045, 081). Tags that overlap the badge zone are hard to read. Fix: reserve the top strip for the two badges and keep tags out of it.
9. **Overlay contrast is inconsistent.** The "6 of 7 Commander decides" badge reads fine on dark scenes but is weaker on the bright outdoor frames (009, 097). The LIVE badge is faint at the opening title (001). Fix: use an opaque pill.
10. **Minor:** "Live · 127.0.0.1" appears on the Money screen (029, 041, 065), which reads as a debug string to the audience. The small "Suppliers... SIMULATED" text is unreadable from a metre away. Fix: hide the IP and enlarge the SIMULATED label.

**What works:** the speaker name and colour on every subtitle bar, the subtitle moving to the top while the card is up, the card leaving after the choice (073 has no card), and the opening title, which is clear and readable.

**Score: 6/10.** It's readable and mostly easy to follow, but the chosen option is never confirmed visibly, and several overlays crowd or cut into each other.
