#!/usr/bin/env bash
# Regenerate the Xcode project from project.yml.
#
# The .xcodeproj is a build artifact here, not a source file. It is gitignored,
# and editing it by hand will be silently overwritten the next time this runs.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is not installed."
    echo "       brew install xcodegen"
    exit 1
fi

xcodegen generate
echo "Generated Glasshouse.xcodeproj from project.yml"
