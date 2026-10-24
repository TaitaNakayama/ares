#!/bin/zsh
# Soak test: loops autoplay (cycling choices) and logs headset fps/thermal every 30 s.
cd "$(dirname "$0")/.."
MIN=${1:-20}
LOG=docs/evidence/soak-$(date +%H%M).log
end=$(( $(date +%s) + MIN * 60 ))
i=0
choices=(buy lever wait reject)
while [ $(date +%s) -lt $end ]; do
  c=${choices[$(( i % 4 + 1 ))]}
  curl -s -X POST localhost:8787/api/director/autoplay -H 'content-type: application/json' -d "{\"choice\":\"$c\",\"decideAfterMs\":6000}" > /dev/null
  for k in 1 2 3; do
    sleep 30
    s=$(curl -s localhost:8787/api/vr/stats)
    echo "$(date +%H:%M:%S) run=$i choice=$c $(echo $s | python3 -c 'import sys,json; d=json.load(sys.stdin); print("fps=%.1f thermal=%s uptime=%.0f link=%s at=%s" % (d.get("fps",0), d.get("thermal"), d.get("uptime",0), d.get("link"), d.get("receivedAt","")[11:19]))' 2>/dev/null)" | tee -a $LOG
  done
  i=$(( i + 1 ))
done
echo "log: $LOG"
