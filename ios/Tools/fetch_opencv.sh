#!/usr/bin/env bash
# Télécharge le cadre OpenCV pour iOS publié par le projet OpenCV (bibliothèque statique, licence Apache 2.0),
# vérifie son empreinte, puis ne garde que les architectures utiles : arm64 (iPhone) et x86_64 (simulateur sur Mac
# Intel). Usage : fetch_opencv.sh [version] [dossier de destination]
set -euo pipefail

VERSION="${1:-4.14.0}"
DEST="${2:-$(cd "$(dirname "$0")/.." && pwd)/Frameworks}"
URL="https://github.com/opencv/opencv/releases/download/${VERSION}/opencv-${VERSION}-ios-framework.zip"
# Empreinte de opencv-4.14.0-ios-framework.zip relevée le 23 octobre 2026.
EXPECTED_4_14_0="f4f428fa9270adf95b3ed4705eb18ba3028ed2c2777a4f1a002739b869986a6a"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Téléchargement de $URL"
curl -sSfL --retry 3 --retry-delay 5 -o "$WORK/opencv.zip" "$URL"
SUM="$(shasum -a 256 "$WORK/opencv.zip" | cut -d' ' -f1)"
echo "SHA-256 : $SUM"
if [ "$VERSION" = "4.14.0" ] && [ "$SUM" != "$EXPECTED_4_14_0" ]; then
  echo "Empreinte inattendue pour OpenCV $VERSION (attendue : $EXPECTED_4_14_0)" >&2
  exit 1
fi

unzip -q "$WORK/opencv.zip" -d "$WORK"
BIN="$WORK/opencv2.framework/Versions/A/opencv2"
lipo -info "$BIN"
lipo "$BIN" -extract arm64 -extract x86_64 -output "$BIN.thin"
mv "$BIN.thin" "$BIN"
lipo -info "$BIN"

mkdir -p "$DEST"
rm -rf "$DEST/opencv2.framework"
mv "$WORK/opencv2.framework" "$DEST/"
echo "OpenCV $VERSION installé dans $DEST/opencv2.framework"
