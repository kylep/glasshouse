#!/usr/bin/env bash
# The integration gate: build and run against the iOS Simulator.
#
# Slower than scripts/test.sh by a couple of orders of magnitude, so this is a
# gate rather than a loop. It proves the app target links and launches; it
# proves very little about sensors, because most of them report no data in a
# simulator at all. See docs/simulator-reality.md.
set -euo pipefail

cd "$(dirname "$0")/.."

DESTINATION="${GLASSHOUSE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"

./scripts/bootstrap.sh

xcodebuild build \
    -project Glasshouse.xcodeproj \
    -scheme Glasshouse \
    -destination "$DESTINATION" \
    CODE_SIGNING_ALLOWED=NO \
    | (command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat)
