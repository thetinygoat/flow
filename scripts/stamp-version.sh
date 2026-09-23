#!/bin/sh
# Writes the version, build number and commit into the built app's Info.plist.
#
# Git is the only source of truth: the version is the latest vX.Y.Z tag, the
# build number is the commit count (it only ever grows, which is what macOS and
# updaters compare), and builds not made exactly at a tag are marked -dev.
set -eu

cd "$SRCROOT"

tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)
version=${tag#v}
if ! git describe --tags --exact-match --match 'v[0-9]*' >/dev/null 2>&1; then
    version="$version-dev"
fi
build=$(git rev-list --count HEAD)
commit=$(git rev-parse --short=10 HEAD)

plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
/usr/libexec/PlistBuddy -c "Delete :FlowCommit" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :FlowCommit string $commit" "$plist"
