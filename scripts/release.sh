#!/bin/bash
# Builds, signs, notarizes and packages a Flow release, and writes the
# Sparkle feed entry for it. Nothing leaves this Mac except the notarization
# upload to Apple, unless --publish is given.
#
#   scripts/release.sh 0.1.0            build dist/Flow-0.1.0.dmg and dist/appcast.xml
#   scripts/release.sh 0.1.0 --publish  publish exactly those files: push the tag
#                                       and create the GitHub release
#
# Needs: a Developer ID Application certificate for the team below, the
# `flow-notary` notarytool keychain profile, the Sparkle private key in the
# keychain, create-dmg, and gh.
set -euo pipefail

VERSION="${1:-}"
PUBLISH="${2:-}"
TEAM=DP5STKBRSS
REPO=thetinygoat/flow
NOTARY_PROFILE=flow-notary
MINIMUM_SYSTEM=14.0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
DIST="$ROOT/dist"
TAG="v$VERSION"
DMG="$DIST/Flow-$VERSION.dmg"
APP="$BUILD/Build/Products/Release/Flow.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

fail() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: scripts/release.sh X.Y.Z [--publish]"
[[ -z "$PUBLISH" || "$PUBLISH" == "--publish" ]] || fail "unknown option $PUBLISH"

cd "$ROOT"

publish() {
    step "Publishing $TAG"
    [[ -f "$DMG" && -f "$DIST/appcast.xml" ]] || fail "build the release first: scripts/release.sh $VERSION"
    gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && fail "release $TAG already exists on GitHub"
    [[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse HEAD)" ]] || fail "tag $TAG is not at HEAD"
    xcrun stapler validate "$DMG" >/dev/null || fail "$DMG is not notarized"
    git push origin "$TAG"
    gh release create "$TAG" "$DMG" "$DIST/appcast.xml" \
        --repo "$REPO" \
        --title "Flow $VERSION" \
        --notes "Release notes: https://getflowterm.app/releases/$VERSION"
    echo "published https://github.com/$REPO/releases/tag/$TAG"
}

if [[ "$PUBLISH" == "--publish" ]]; then
    publish
    exit 0
fi

step "Checking the tree and tools"
# The ghostty submodule carries local build patches, so its working copy is
# allowed to differ; everything else must be committed.
[[ -z "$(git status --porcelain --ignore-submodules=dirty)" ]] || fail "commit or stash your changes first"
IDENTITY="$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM)\)\"/\1/p" | head -1)"
[[ -n "$IDENTITY" ]] || fail "no Developer ID Application certificate for team $TEAM"
command -v create-dmg >/dev/null || fail "create-dmg not found (npm install --global create-dmg)"
command -v gh >/dev/null || fail "gh not found"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null || fail "notarytool profile $NOTARY_PROFILE is missing"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    fail "release $TAG already exists on GitHub; published releases are never replaced"
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    [[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse HEAD)" ]] || fail "tag $TAG exists but is not at HEAD"
else
    git tag -a "$TAG" -m "Flow $VERSION"
    echo "tagged HEAD as $TAG (local only until --publish)"
fi
echo "signing as: $IDENTITY"

step "Building Release"
rm -rf "$BUILD" "$DIST"
mkdir -p "$DIST"
xcodegen generate --quiet
xcodebuild -scheme flow -configuration Release -derivedDataPath "$BUILD" build -quiet
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || fail "the app says $BUILT_VERSION, expected $VERSION"
echo "Flow $BUILT_VERSION ($BUILD_NUMBER)"

step "Signing"
# Xcode signs Sparkle's outer framework but leaves the helpers inside it
# ad-hoc, which notarization rejects. They are signed innermost first, then
# the framework, then the app.
sign() { codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign --entitlements "$ROOT/Resources/Flow.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow; then
    fail "the app carries get-task-allow, which notarization rejects"
fi

step "Packaging"
create-dmg "$APP" "$DIST" --overwrite --identity="$IDENTITY" >/dev/null
mv "$DIST/Flow $VERSION.dmg" "$DMG"
echo "$DMG"

step "Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$DIST/notarization.json"
STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$DIST/notarization.json")"
if [[ "$STATUS" != "Accepted" ]]; then
    ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$DIST/notarization.json")"
    xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" "$DIST/notarization-log.json" || true
    fail "notarization $STATUS; see $DIST/notarization-log.json"
fi
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
echo "notarized and stapled"

step "Updating the Sparkle feed"
SIGN_UPDATE="$BUILD/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
read -r SIGNATURE LENGTH < <("$SIGN_UPDATE" "$DMG" | sed -E 's/.*sparkle:edSignature="([^"]+)" length="([0-9]+)".*/\1 \2/')
[[ -n "$SIGNATURE" && -n "$LENGTH" ]] || fail "sign_update produced no signature"
rm -f "$DIST/appcast-previous.xml"
gh release download --repo "$REPO" --pattern appcast.xml --output "$DIST/appcast-previous.xml" 2>/dev/null \
    || echo "no published feed yet; starting a new one"
python3 "$ROOT/scripts/update_appcast.py" "$DIST/appcast-previous.xml" "$DIST/appcast.xml" \
    --version "$VERSION" \
    --build "$BUILD_NUMBER" \
    --url "https://github.com/$REPO/releases/download/$TAG/Flow-$VERSION.dmg" \
    --length "$LENGTH" \
    --signature "$SIGNATURE" \
    --notes-url "https://getflowterm.app/releases/$VERSION" \
    --minimum-system "$MINIMUM_SYSTEM"
rm -f "$DIST/appcast-previous.xml"
echo "$DIST/appcast.xml"

step "Done. Review dist/, then run: scripts/release.sh $VERSION --publish"
