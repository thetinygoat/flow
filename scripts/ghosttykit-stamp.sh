#!/bin/sh
# Prints what GhosttyKit is built from: the ghostty commit the repository pins.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "ghostty $(git rev-parse HEAD:Vendor/ghostty)"
