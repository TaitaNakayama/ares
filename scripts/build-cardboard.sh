#!/bin/zsh
# Rebuild the Google Cardboard SDK (v1.36.0) static libs for iOS into vr/Vendor/Cardboard.
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/.cache/vendor/cardboard
[ -d $SRC ] || git clone -q --depth 1 --branch v1.36.0 https://github.com/googlevr/cardboard.git $SRC
cd $SRC && pod install >/dev/null
xcodebuild -workspace Cardboard.xcworkspace -scheme sdk -sdk iphoneos -configuration Release -derivedDataPath $ROOT/.cache/dd-cardboard build | tail -1
P=$ROOT/.cache/dd-cardboard/Build/Products/Release-iphoneos
V=$ROOT/vr/Vendor/Cardboard
mkdir -p $V/lib $V/include
cp $P/GfxPluginCardboard.a $V/lib/libCardboardSDK.a
cp $P/Protobuf-C++/libProtobuf-C++.a $V/lib/
cp $SRC/sdk/include/cardboard.h $V/include/
rm -rf $V/sdk.bundle && cp -R $SRC/sdk/qrcode/ios/sdk.bundle $V/
echo "Cardboard SDK ready in $V"
