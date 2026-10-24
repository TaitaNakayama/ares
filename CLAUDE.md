# Ares

An AI agent team that runs procure-to-pay (request -> receive -> three-way match -> approve -> pay) on its own under deterministic controls, demoed on a crewed Mars base in Cardboard VR (Unity, iPhone 16 Pro) plus a laptop console. Cal Hacks 13.0, solo; Devpost deadline Sun 2026-10-25 09:00 PT.

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
  - the user's physical presence (phone, viewer, signing, Unity Hub sign-in);
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
scripts/build-ios.sh              # Unity batchmode -> xcodebuild -> devicectl install + launch
```

## Gotchas
- Unity batchmode fails if the project is open in the editor. Editor log: `~/Library/Logs/Unity/Editor.log`.
- Cardboard: keep MSAA off (bug #442); Initialize XR on Startup; Landscape Left; new Input System.
- Venue Wi-Fi is slow (about 0.5 MB/s) and may isolate clients. The phone hotspot is the fallback network; offline replay is the last resort.
