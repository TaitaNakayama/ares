# STATUS

_Updated Fri 2026-10-23 19:30 PT_

## Works
- Engine core (world-agnostic): double-entry ledger with hash chain and capability-token posting, policy engine (RBAC, SoD, limits, three-way match, duplicates, bank-change hold + verify, robust price statistics, runway), escalations with remote delay, verifications, audit trail, trace-to-source.
- 12 tests passing, including a fast-check adversarial fuzz (300 seeds x 400 random/malicious proposals): ledger always balances, 0 forbidden actions executed, no payment to an unverified account.
- Research: 8 tracks in `research/`. Terrain crops (CTX DEM, HiRISE 5 km DTM) downloaded; CC0 assets + OFL fonts downloaded.

## In progress
- Unity 6000.0.85f1 + iOS module download (resumable, `.cache/unity/fetch.sh`).
- Opus adversarial reviews: Unity/Cardboard, network, libraries/terrain, engine code.
- Agent brains + orchestrator, Mars world, server.

## Blocked / needs you
- Unity Hub sign-in + Personal license once the editor is installed.
- `OPENAI_API_KEY` in `.env`. Optional: the rules brain works without it.
- Hotspot OK for the Unity download? It would speed it up.

## Next
- Checkpoint 1: hello Cardboard scene on the iPhone (stereo, head tracking, gaze + tap, QR profile).
