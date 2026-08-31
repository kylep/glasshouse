#!/usr/bin/env bash
# The development loop: pure-Swift unit tests on macOS, no simulator involved.
#
# This is what agents run while iterating. It completes in seconds because
# GlasshouseCore imports no Apple sensor frameworks and needs no signing,
# no simulator boot, and no Xcode project.
#
# For the slower simulator gate, use scripts/test-simulator.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
exec swift test "$@"
