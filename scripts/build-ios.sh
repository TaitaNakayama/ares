#!/bin/zsh
# Build, sign, install and launch the native VR app on the paired iPhone.
#   scripts/build-ios.sh            # Debug build
#   CONFIG=Release scripts/build-ios.sh
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEVICE=${DEVICE:-B177F8D9-2156-5A6C-8882-05087D03426A}
CONFIG=${CONFIG:-Release}
[ -f $ROOT/vr/Vendor/Cardboard/lib/libCardboardSDK.a ] || $ROOT/scripts/build-cardboard.sh
# Bake every reachable address of this Mac into the app (Wi-Fi, hotspot, USB), plus mDNS name.
IPS=$(ifconfig | awk '/inet / && $2 != "127.0.0.1" {print $2}')
HOST=$(scutil --get LocalHostName 2>/dev/null || echo "")
mkdir -p $ROOT/vr/AresVR/Resources
TOKEN_FILE=$ROOT/.cache/headset-token
[ -f $TOKEN_FILE ] || { mkdir -p $ROOT/.cache; openssl rand -hex 16 > $TOKEN_FILE; }
TOKEN=$(cat $TOKEN_FILE)
{
  echo "{ \"token\": \"$TOKEN\", \"servers\": ["
  for ip in ${(f)IPS}; do echo "  \"ws://$ip:8787/?client=vr\","; done
  [ -n "$HOST" ] && echo "  \"ws://$HOST.local:8787/?client=vr\","
  # iPhone Personal Hotspot hands out 172.20.10.2-14; try them all after the known addresses.
  for n in $(seq 2 14); do sep=","; [ $n = 14 ] && sep=""; echo "  \"ws://172.20.10.$n:8787/?client=vr\"$sep"; done
  echo '] }'
} > $ROOT/vr/AresVR/Resources/ares.json
sed -E 's/"token": "[^"]+"/"token": "(hidden)"/' $ROOT/vr/AresVR/Resources/ares.json
cd $ROOT/vr && xcodegen generate --quiet
LOG=$ROOT/vr/build/xcodebuild.log
mkdir -p $ROOT/vr/build
if ! xcodebuild -project AresVR.xcodeproj -scheme AresVR -configuration $CONFIG -sdk iphoneos -derivedDataPath $ROOT/vr/build -allowProvisioningUpdates build > $LOG 2>&1; then
  grep -E "error:" $LOG | head -30; echo "BUILD FAILED (log: $LOG)"; exit 1
fi
echo "BUILD SUCCEEDED"
APP=$ROOT/vr/build/Build/Products/$CONFIG-iphoneos/AresVR.app
[ -d $APP ] || { echo "no app built"; exit 1; }
xcrun devicectl device install app --device $DEVICE $APP | tail -1
xcrun devicectl device process launch --terminate-existing --device $DEVICE io.nakayama.ares.vr | tail -1
