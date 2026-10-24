# Ares

An AI agent team that runs procure-to-pay (request -> receive -> three-way match -> approve -> pay) on its own under deterministic controls, demoed on a crewed Mars base in Cardboard VR (native iOS: Swift + SceneKit + Google Cardboard SDK, iPhone 16 Pro) plus a laptop console. Cal Hacks 13.0, solo; Devpost deadline Sun 2026-10-25 09:00 PT.

Read first: [BRIEF.md](BRIEF.md) (the spec), [PLAN.md](PLAN.md) (decisions, timeline, cut list), [CLAIMS.md](CLAIMS.md) (Tier 1 register), [ARCHITECTURE.md](ARCHITECTURE.md), [STATUS.md](STATUS.md).

## Verification protocol (brief)
- Tier 1 = anything that forces a rebuild or kills the demo if wrong. It passes four checks before anything is built on it:
  1. Context check against the detected setup.
  2. Two or more dated sources.
  3. An Opus adversarial reviewer that hasn't seen our reasoning.
  4. A hands-on spike on the real device.
- Until then a claim is UNVERIFIED and has a named fallback. Track it in CLAIMS.md. Never present an unverified claim as fact.
- Tier 2 (features, UI) is tested at milestones: end-to-end runs, the eval harness, on-device playthroughs.

## Key rules
- Work autonomously. Stop only for:
  - the user's physical presence (phone unlocked/in the viewer, signing);
  - a failed Tier 1 spike that forces a foundational change;
  - anything that costs money, needs a new account or needs an API key;
  - destructive actions outside the repo.

  Batch asks into one message and keep working.
- **LLM agents only PROPOSE.** `Engine.submit` -> `policy.evaluate` -> verdict -> executor. Only an `allow` verdict mints the one-shot ledger token. Never let LLM output write state directly.
- **`packages/engine` never mentions Mars.** It uses generic P2P roles; worlds supply display names, events and levers.
- Price anomalies use statistics (robust log z-score vs history), not the LLM.
- Invented data is labeled SIMULATED; real data carries its citation.
- Commit at every working milestone. No Claude/Anthropic attribution in commits or PRs.
- Subagents: pass `model: "sonnet"` by default and Opus for Tier 1 reviewers. Never Haiku.
- Update STATUS.md at each milestone.

## Commands
```bash
pnpm install                      # workspace deps
pnpm test                         # vitest: engine scenarios + adversarial fuzz
pnpm typecheck                    # tsc 7 --noEmit over packages/*
node packages/server/src/main.ts  # backend on :8787 (Node 26 runs .ts directly)
pnpm --filter @ares/console dev   # laptop console
node packages/eval/src/main.ts --seeds 500   # scorecard
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # xcode-select points at CLT
xcrun devicectl list devices      # phone: B177F8D9-2156-5A6C-8882-05087D03426A
scripts/build-ios.sh              # XcodeGen -> xcodebuild (signed) -> devicectl install + launch (phone must be unlocked)
scripts/build-cardboard.sh        # rebuild Cardboard SDK static libs (vr/Vendor, gitignored)
scripts/build-spectator.sh        # Mac spectator view, full screen (Release; --debug = mouse camera, --windowed)
curl -X POST localhost:8787/api/capture/request   # headset uploads its current frame to .cache/captures/latest.jpg
curl localhost:8787/api/vr/stats  # headset fps / thermal / link
node scripts/record-tape.ts       # re-record the offline replay tape from the live server
scripts/record-demo.sh            # director-camera MP4 of a full autoplay run (headset on the desk)
```

## Gotchas
- Unity is NOT used (its 2026-06-30 terms bar AI-agent/CLI use without authorized access); Unity 6000.0.85f1 stays installed only as fallback B.
- iOS app bundles must not contain a top-level `Resources/` folder (codesign fails); resources are copied flat.
- Eye textures: `flipV = false` (top_v 1, bottom_v 0), as in Google's Unity plugin.
- The phone must be unlocked for `devicectl process launch`; Auto-Lock Never during the event.
- Venue Wi-Fi is slow (about 0.5 MB/s) and may isolate clients. The phone hotspot is the primary network (verified); offline replay is the last resort.
