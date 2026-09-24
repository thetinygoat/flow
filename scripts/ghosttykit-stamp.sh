#!/bin/sh
# Prints what GhosttyKit is built from: the ghostty commit the repository
# pins, and a hash of the patches applied on top of it.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "ghostty $(git rev-parse HEAD:Vendor/ghostty)"
echo "patches $(cat patches/*.patch | shasum -a 256 | cut -d' ' -f1)"
