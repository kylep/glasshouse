#!/usr/bin/env bash
# Regenerate everything derived from the capability ledger, then the Xcode project.
#
# The .xcodeproj and App/Generated/Info.plist are build artifacts, not source.
# Both are gitignored, and editing either by hand is silently overwritten here.
#
# The generated docs under docs/ ARE committed, because they are meant to be
# read on GitHub. Regenerate and commit them whenever the ledger changes.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is not installed."
    echo "       brew install xcodegen"
    exit 1
fi

echo "→ Generating Info.plist from the capability ledger"
mkdir -p App/Generated
# Fails loudly if any required usage-description string is missing, which is
# the point: a capability cannot ship without a declared purpose.
swift run -q glasshouse-ledger plist > App/Generated/Info.plist

echo "→ Regenerating ledger-derived docs"
swift run -q glasshouse-ledger checklist > docs/device-verification.md
swift run -q glasshouse-ledger classification > docs/data-classification.md
python3 scripts/update-readme.py

echo "→ Generating Glasshouse.xcodeproj"
xcodegen generate

echo "Done."
