#!/usr/bin/env bash
# Lance les tests de l'application (pont C++, chaîne vidéo complète) sur le simulateur iPhone le plus récent.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out

UDID="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in items:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            key = (version, d["name"])
            if best is None or key > best[0]:
                best = (key, d["udid"], runtime, d["name"])
if best is None:
    sys.exit("aucun simulateur iPhone disponible")
print(best[1])
print("Simulateur : %s (%s)" % (best[3], best[2]), file=sys.stderr)
')"

rm -rf out/tests.xcresult
xcodebuild test \
  -project Blurr.xcodeproj \
  -scheme Blurr \
  -destination "id=$UDID" \
  -resultBundlePath out/tests.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee out/xcodebuild-test.log \
  | (grep -E "Test Case .*(passed|failed|skipped)|error:|Executed|TEST (SUCCEEDED|FAILED)|\*\* " || true)
