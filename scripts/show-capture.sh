#!/bin/zsh
# One iteration round's evidence: run the show hands-free and keep the spectator's view of it
# (a frame every ~2 s, key moments by act, an MP4, and the spoken-line log) for the reviewer.
#   scripts/show-capture.sh <round-dir> [choice] [seed]     # e.g. docs/evidence/rounds/r1 drill
set -e
OUT=${1:?round dir}; CHOICE=${2:-drill}; SEED=${3:-ares-demo}
BASE=${ARES_URL:-http://localhost:8787}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p $OUT/frames
curl -sf -X POST $BASE/api/dev/vrstate -H 'content-type: application/json' -d '{"patch":null}' >/dev/null
curl -sf -X POST $BASE/api/show/autoplay -H 'content-type: application/json' -d "{\"choice\":\"$CHOICE\",\"seed\":\"$SEED\"}" >/dev/null
last=""; n=0; t0=$(date +%s)
while true; do
  act=$(curl -s $BASE/api/show/log | python3 -c "import json,sys; s=json.load(sys.stdin); print(s['act'] + ('-end' if (s['show']['scene'].get('title') or {}).get('style')=='end' else '') + ('-reality' if (s['show']['scene'].get('reality') or {}).get('on') else ''))")
  curl -s -X POST $BASE/api/spectator/capture >/dev/null; sleep 1.6
  n=$((n+1)); f=$(printf "%s/frames/%04d.jpg" $OUT $n)
  cp $ROOT/.cache/captures/spectator.jpg $f 2>/dev/null || true
  if [ "$act" != "$last" ]; then cp $f $OUT/$(printf "%02d" $n)-$act.jpg 2>/dev/null || true; last=$act; fi
  el=$(( $(date +%s) - t0 ))
  if [[ "$act" == explore* ]] && [ $el -gt 200 ]; then break; fi
  if [ $el -gt 330 ]; then break; fi
done
curl -s $BASE/api/show/log | python3 -c "
import json,sys; s=json.load(sys.stdin)
for l in s['lines']: print(f\"{l['at']/1000:6.1f}s  {l['act']:11s}  {l['speaker'].upper():8s} -> {l['to']:8s} [{l['via']}]  {l['text']}\")" > $OUT/subtitles.txt
ffmpeg -v error -y -framerate 0.6 -pattern_type glob -i "$OUT/frames/*.jpg" -vf "scale=1280:-2,fps=12" -c:v libx264 -pix_fmt yuv420p -crf 26 $OUT/show.mp4
echo "$n frames; $(wc -l < $OUT/subtitles.txt) lines; $OUT/show.mp4"
