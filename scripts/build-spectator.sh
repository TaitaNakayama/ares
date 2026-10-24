#!/bin/zsh
# Build and launch the Mac spectator view (full screen in its own Space).
#   scripts/build-spectator.sh               # demo build (Release): no mouse camera, headset or recorded run only
#   scripts/build-spectator.sh --debug       # debug build: mouse camera while no headset is connected
#   scripts/build-spectator.sh --windowed    # open in a window instead of full screen (also --background)
#   scripts/build-spectator.sh --no-launch   # build only
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG=Release
LAUNCH=1
ARGS=()
for a in "$@"; do
  case $a in
    --debug) CONFIG=Debug ;;
    --no-launch) LAUNCH=0 ;;
    *) ARGS+=($a) ;;
  esac
done
cd $ROOT/vr && xcodegen generate --quiet
LOG=$ROOT/vr/build/spectator-xcodebuild.log
mkdir -p $ROOT/vr/build
if ! xcodebuild -project AresVR.xcodeproj -scheme AresSpectator -configuration $CONFIG -destination 'platform=macOS' -derivedDataPath $ROOT/vr/build build > $LOG 2>&1; then
  grep -E "error:|BUILD FAILED" $LOG | head -30
  exit 1
fi
echo "BUILD SUCCEEDED ($CONFIG)"
APP=$ROOT/vr/build/Build/Products/$CONFIG/AresSpectator.app
pkill -x AresSpectator 2>/dev/null || true
if [ $LAUNCH = 1 ]; then
  if [[ " ${ARGS[*]} " == *" --background "* ]]; then open -g -n $APP --args $ARGS; else open -n $APP --args $ARGS; fi
  echo "Launched $APP $ARGS"
fi
