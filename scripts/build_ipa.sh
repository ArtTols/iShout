#!/usr/bin/env bash
# Produces an UNSIGNED ShoutcastEncoder-unsigned.ipa (macOS + Xcode required)
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Vendor/lame/lib/libmp3lame.a ] || bash scripts/build_lame.sh
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
rm -rf build Payload ShoutcastEncoder-unsigned.ipa
xcodebuild -project ShoutcastEncoder.xcodeproj -scheme ShoutcastEncoder \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir Payload
cp -R build/Build/Products/Release-iphoneos/ShoutcastEncoder.app Payload/
zip -qry ShoutcastEncoder-unsigned.ipa Payload
echo "Built ShoutcastEncoder-unsigned.ipa"
