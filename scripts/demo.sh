#!/bin/zsh
# The demo, one command: starts whatever isn't running (server, Mac spectator), waits for the phone, parks the show at the
# real-Mars opening and prints GO. Run it before each judge; the judge then presses the marker in the viewer.
#   scripts/demo.sh              # spectator full screen (judging)
#   scripts/demo.sh --windowed   # spectator in a window (rehearsal)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
BASE=http://localhost:8787
ok(){ printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad(){ printf "  \033[31m✗\033[0m %s\n" "$1"; }

# 0. the local model (the offline fallback behind the cloud): started if it isn't, never fatal
if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
  [ -x scripts/start-local-llm.sh ] && { echo "starting the local model…"; scripts/start-local-llm.sh >/dev/null 2>&1 || true; }
fi
curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && ok "local model (Ollama) up" || bad "local model not running: cloud only (fine with internet; run scripts/start-local-llm.sh for the offline fallback, then restart the server)"

# 1. the server
if ! curl -sf $BASE/api/vr/stats >/dev/null 2>&1; then
  echo "starting the server…"
  (nohup node packages/server/src/main.ts > .cache/server.log 2>&1 &)
  for i in $(seq 1 40); do curl -sf $BASE/api/vr >/dev/null 2>&1 && break; sleep 0.5; done
fi
curl -sf $BASE/api/vr >/dev/null 2>&1 && ok "server on :8787" || { bad "server not answering (see .cache/server.log)"; exit 1; }
llm=$(grep -a -m1 'LLM layers' .cache/server.log 2>/dev/null | sed 's/LLM layers: //'); [ -n "$llm" ] && ok "agents: $llm"

# 2. the Mac spectator (the judging config: full screen, camera follows the judge; --windowed for a rehearsal)
if ! pgrep -x AresSpectator >/dev/null; then
  APP=vr/build/Build/Products/Release/AresSpectator.app
  [ -d "$APP" ] || { bad "spectator not built: run scripts/build-spectator.sh"; exit 1; }
  if [[ " $* " == *" --windowed "* ]]; then open -g -n "$APP" --args --director --windowed --background; else open -n "$APP" --args --director; fi
  sleep 4
fi
pgrep -x AresSpectator >/dev/null && ok "spectator running" || { bad "spectator not running"; exit 1; }

# 3. the phone (Ares open, unlocked, cable in)
printf "  waiting for the phone"
for i in $(seq 1 60); do
  live=$(curl -s $BASE/api/debug/pose | python3 -c "import json,sys; d=json.load(sys.stdin); print(1 if d['openHeadsetSockets']>0 and d['msSinceRelay'] is not None and d['msSinceRelay']<800 else 0)" 2>/dev/null)
  [ "$live" = 1 ] && break; printf "."; sleep 1
done; echo
if [ "$live" = 1 ]; then
  curl -s $BASE/api/vr/stats | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"  \033[32m✓\033[0m phone {d.get('link')} · {round(d.get('fps',0))} fps · thermal {d.get('thermal')}\")"
else
  bad "no phone pose: open Ares on the phone (unlocked), check the USB cable, then run this again"; exit 1
fi
sleep 2
mode=$(curl -s $BASE/api/spectator/stats | python3 -c "import json,sys; print(json.load(sys.stdin).get('mode'))" 2>/dev/null)
[ "$mode" = live ] && ok "spectator mirrors the phone (LIVE)" || bad "spectator mode is '$mode' (should be live within a few seconds)"

# 4. a clean show, parked at the real-Mars opening
curl -sf -X POST $BASE/api/dev/vrstate -H 'content-type: application/json' -d '{"patch":null}' >/dev/null
curl -sf -X POST $BASE/api/show/start >/dev/null
act=$(curl -s $BASE/api/show/log | python3 -c "import json,sys; print(json.load(sys.stdin)['act'])")
[ "$act" = real ] && ok "show parked at the opening (the judge presses the marker to begin)" || bad "show act is '$act'"
echo
echo "GO. Console: http://localhost:8787  ·  log of the run: curl -s $BASE/api/show/log | python3 -m json.tool | less"
echo "Judge: viewer on → press the marker → (Science: press for the rock) → look at the door, press → at the card look ~1 s, press → after the end card, look at a robot and press."
