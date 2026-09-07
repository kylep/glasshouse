#!/usr/bin/env bash
# Build, install, and run on a connected iPhone, capturing the capability report.
#
# The Team ID is NOT the identifier inside the certificate's common name — that
# is a per-developer ID. It is the OU field, which this script reads rather than
# hardcoding, so the repo carries no account-specific values.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${GLASSHOUSE_DEVICE:-}"
if [ -z "$DEVICE" ]; then
    DEVICE=$(xcrun devicectl list devices 2>/dev/null \
        | awk '/available/ && !/Watch/ {print $1; exit}')
fi
[ -n "$DEVICE" ] || { echo "error: no connected device. Set GLASSHOUSE_DEVICE."; exit 1; }

TEAM=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"Apple Development: \(.*\)".*/\1/p' | head -1 \
    | xargs -I{} security find-certificate -c "Apple Development: {}" -p \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')
[ -n "$TEAM" ] || { echo "error: could not read a Team ID from your signing certificate."; exit 1; }

echo "→ Device: $DEVICE   Team: $TEAM"
./scripts/bootstrap.sh >/dev/null

echo "→ Building"
# Explicit derived-data path, deliberately. Xcode's shared tree silently served
# a cached binary for hours while reporting successful builds and installs —
# every check passed and the phone kept running old code. An isolated tree per
# project makes that failure impossible to reproduce.
xcodebuild build -project Glasshouse.xcodeproj -scheme Glasshouse \
    -destination "platform=iOS,name=$DEVICE" \
    -derivedDataPath .build/xcode \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
    | (command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat)

APP=".build/xcode/Build/Products/Debug-iphoneos/Glasshouse.app"

echo "→ Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null

echo "→ Running (capability report follows)"
xcrun devicectl device process launch --device "$DEVICE" \
    --terminate-existing --console fit.glasshouse.app > /tmp/glasshouse-device.log 2>&1 &
PID=$!
sleep 20
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true

grep "GH|" /tmp/glasshouse-device.log | sed 's/.*GH| //' || {
    echo "No report captured. If launch failed, trust the developer profile:"
    echo "  Settings → General → VPN & Device Management → Trust"
}
