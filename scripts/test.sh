#!/usr/bin/env bash
# Runs the automated test suite. Fails on any error.
# All destructive tests operate only inside a temporary fixture directory.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT"

echo "▸ swift $(swift --version 2>/dev/null | head -1)"
swift test
echo "✓ Tests passed"
