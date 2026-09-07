#!/usr/bin/env bash
# Launch the installed app on a connected iPhone and print its capability report.
#
# Separate from scripts/device.sh, which builds and installs first. This one
# only runs what is already there, which makes it the fast way to re-check the
# device after granting a permission.
#
# Lived in /tmp until a machine restart deleted it mid-project. It is a real
# tool; it belongs in the repo.
set -uo pipefail
cd "$(dirname "$0")/.."

DEVICE="${GLASSHOUSE_DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/available/ && !/Watch/ {print $1; exit}')}"
[ -n "$DEVICE" ] || { echo "error: no connected device. Set GLASSHOUSE_DEVICE."; exit 1; }

LOG="${GLASSHOUSE_LOG:-/tmp/glasshouse-device.log}"

xcrun devicectl device process launch --device "$DEVICE" \
    --terminate-existing --console fit.glasshouse.app > "$LOG" 2>&1 &
PID=$!
sleep "${GLASSHOUSE_WAIT:-20}"
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true

if grep -q "GH|" "$LOG"; then
    grep "GH|" "$LOG" | sed 's/.*GH| //'
else
    echo "No report captured. Common causes:"
    grep -iE "locked|not.*unlocked|trust" "$LOG" | head -2 || true
    echo "  - phone locked (devicectl can install through a lock but not launch)"
    echo "  - developer profile not trusted: Settings > General > VPN & Device Management"
fi
