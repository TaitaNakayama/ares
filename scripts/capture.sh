#!/bin/zsh
# Capture the headset's view with a forced head direction: scripts/capture.sh <name> [yaw] [pitch]
cd "$(dirname "$0")/.."
NAME=$1; YAW=${2:-0}; PITCH=${3:-0}
mkdir -p .cache/views
before=$(stat -f %m .cache/captures/latest.jpg 2>/dev/null || echo 0)
curl -s -X POST "localhost:8787/api/capture/request?yaw=$YAW&pitch=$PITCH" > /dev/null
for i in 1 2 3 4 5 6 7 8; do sleep 1; [ "$(stat -f %m .cache/captures/latest.jpg 2>/dev/null)" != "$before" ] && break; done
cp .cache/captures/latest.jpg .cache/views/$NAME.jpg && echo ".cache/views/$NAME.jpg"
