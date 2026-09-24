#!/bin/sh
# Builds GhosttyKit.xcframework from the ghostty submodule and stages it,
# together with the terminfo and shell integration files, under Vendor/.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHOSTTY="$ROOT/Vendor/ghostty"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [ ! -f "$GHOSTTY/build.zig" ]; then
  echo "ghostty submodule is empty, run: git submodule update --init" >&2
  exit 1
fi

cd "$GHOSTTY"
# Upstream fixes that landed after the pinned release, needed for Xcode 27.
for patch in "$ROOT"/patches/*.patch; do
  if git apply --check --reverse "$patch" >/dev/null 2>&1; then
    continue
  fi
  git apply "$patch"
done

zig build \
  -Dapp-runtime=none \
  -Demit-xcframework=true \
  -Demit-macos-app=false \
  -Dsentry=false \
  -Di18n=false \
  -Doptimize=ReleaseFast

rm -rf "$ROOT/Vendor/GhosttyKit.xcframework" "$ROOT/Vendor/GhosttyResources"
mkdir -p "$ROOT/Vendor/GhosttyResources"
cp -R "$GHOSTTY/macos/GhosttyKit.xcframework" "$ROOT/Vendor/"
cp -R "$GHOSTTY/zig-out/share/terminfo" "$GHOSTTY/zig-out/share/ghostty" "$ROOT/Vendor/GhosttyResources/"

# Xcode's linker can miss symbols in the copied universal archive until its
# symbol index is rebuilt.
xcrun ranlib "$ROOT/Vendor/GhosttyKit.xcframework/macos-arm64_x86_64/libghostty.a"

# Records what was built, so a release can refuse a stale libghostty.
"$ROOT/scripts/ghosttykit-stamp.sh" > "$ROOT/Vendor/GhosttyKit.stamp"

echo "GhosttyKit staged in $ROOT/Vendor"
