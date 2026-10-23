#!/usr/bin/env bash
# Archive l'application pour iPhone sans signature, puis l'emballe en blurr-ios.ipa. Le fichier est signé au moment
# de l'installation (Sideloadly, AltStore) avec le compte Apple de l'utilisateur.
# Usage : build_ipa.sh [numéro de compilation]
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out
BUILD_NUMBER="${1:-1}"

rm -rf out/Blurr.xcarchive out/Payload out/blurr-ios.ipa
xcodebuild archive \
  -project Blurr.xcodeproj \
  -scheme Blurr \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath out/Blurr.xcarchive \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  2>&1 | tee out/xcodebuild-archive.log \
  | (grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)|\*\* " || true)

APP="out/Blurr.xcarchive/Products/Applications/Blurr.app"
test -d "$APP"
test -f "$APP/face_detection_yunet_2023mar.onnx"
test -f "$APP/PrivacyInfo.xcprivacy"
lipo -info "$APP/Blurr"

mkdir -p out/Payload
cp -R "$APP" out/Payload/
# Signature ad hoc (sans identité) : ajoute la signature de code attendue par les outils d'installation, qui la
# remplacent par celle du compte de l'utilisateur.
codesign --force --sign - --timestamp=none out/Payload/Blurr.app && codesign -dv out/Payload/Blurr.app 2>&1 | head -5 || true
(cd out && zip -qry blurr-ios.ipa Payload)
shasum -a 256 out/blurr-ios.ipa | tee out/blurr-ios.ipa.sha256
ls -la out/blurr-ios.ipa
