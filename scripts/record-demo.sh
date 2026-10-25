#!/bin/zsh
# Record the director-camera MP4 of a full autoplay run from the headset (docs/demo/ares-vr-<time>.mp4).
# The headset renders the director's camera while recording, so the viewer should be on the desk, not on a judge.
#   scripts/record-demo.sh [choice] [seconds]     # choice: buy (default) | lever | wait | reject; default 300 s
set -e
CHOICE=${1:-buy}
SECS=${2:-300}
BASE=${ARES_URL:-http://localhost:8787}
curl -sf $BASE/api/vr/stats | grep -q '"link":"Live' || { echo "headset is not connected"; exit 1; }
curl -sf -X POST $BASE/api/record/start -H 'content-type: application/json' -d '{"fps":12,"director":true}' >/dev/null
curl -sf -X POST $BASE/api/show/autoplay -H "content-type: application/json" -d "{\"choice\":\"$CHOICE\"}" >/dev/null
echo "recording $SECS s of autoplay (choice $CHOICE)..."
for i in $(seq 1 $((SECS/10))); do sleep 10; printf '.'; done; echo
curl -sf -X POST $BASE/api/record/stop
echo
ls -t docs/demo/*.mp4 | head -1
