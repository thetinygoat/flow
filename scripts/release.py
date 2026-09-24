#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Builds, signs, notarizes and packages a Flow release, and writes the
Sparkle feed entry for it. Nothing leaves this Mac except the notarization
upload to Apple, unless --publish is given.

  uv run scripts/release.py 0.1.0            build dist/Flow-0.1.0.dmg and dist/appcast.xml
  uv run scripts/release.py 0.1.0 --publish  publish exactly those files: push the branch
                                             and tag, and create the GitHub release

Needs: a Developer ID Application certificate for TEAM, the NOTARY_PROFILE
notarytool keychain profile, the Sparkle private key in the keychain,
create-dmg, and gh.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime, parsedate_to_datetime
from pathlib import Path

TEAM = "DP5STKBRSS"
REPO = "thetinygoat/flow"
NOTARY_PROFILE = "flow-notary"
MINIMUM_SYSTEM = "14.0"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
FEED_KEEP = 15

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "release"
DIST = ROOT / "dist"
APP = BUILD / "Build" / "Products" / "Release" / "Flow.app"


class ReleaseError(Exception):
    pass


def step(message):
    print(f"\n==> {message}", flush=True)


def run(*args, check=True, capture=False, quiet=False):
    result = subprocess.run(
        [str(arg) for arg in args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE if capture or quiet else None,
        stderr=subprocess.DEVNULL if quiet else None,
    )
    if check and result.returncode != 0:
        raise ReleaseError(f"{args[0]} failed (exit {result.returncode}): {' '.join(map(str, args))}")
    return result


def output(*args):
    return run(*args, capture=True).stdout.strip()


def succeeds(*args):
    return run(*args, check=False, quiet=True).returncode == 0


# --- Decisions, kept free of side effects so they can be tested ---


def tag_action(tag, tag_commit, head, pushed):
    """A tag that was never pushed can follow HEAD when a failed build is
    fixed and rerun; a pushed tag is never moved."""
    if tag_commit is None:
        return "create"
    if tag_commit == head:
        return "keep"
    if pushed:
        raise ReleaseError(f"{tag} is already pushed at another commit")
    return "move"


def notarization_result(text):
    """Apple's verdict and submission id, or ("unknown", None) when notarytool
    gave no readable answer."""
    try:
        data = json.loads(text)
        return data.get("status", "unknown"), data.get("id")
    except (json.JSONDecodeError, AttributeError):
        return "unknown", None


def parse_sign_update(text):
    match = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', text)
    if not match:
        raise ReleaseError("sign_update produced no signature")
    return match.group(1), int(match.group(2))


def developer_id(find_identity_output, team):
    match = re.search(rf'"(Developer ID Application: .*\({team}\))"', find_identity_output)
    return match.group(1) if match else None


def _sparkle(tag):
    return f"{{{SPARKLE_NS}}}{tag}"


def _build_number(item):
    element = item.find(_sparkle("version"))
    text = element.text if element is not None else None
    return int(text) if text and text.isdigit() else -1


def _published(item):
    try:
        return parsedate_to_datetime(item.find("pubDate").text)
    except (AttributeError, TypeError, ValueError):
        return datetime.min.replace(tzinfo=timezone.utc)


def update_appcast(feed, version, build, url, length, signature, notes_url, minimum_system, now=None):
    """Returns the feed with this release added.

    Sparkle offers each user the newest entry whose build number is higher
    than theirs and whose minimum macOS they meet, so older entries stay in
    the feed: a user on an older macOS still finds the last release that runs
    there. The feed keeps the newest FEED_KEEP entries."""
    ET.register_namespace("sparkle", SPARKLE_NS)
    if feed is None:
        root = ET.Element("rss", {"version": "2.0"})
        ET.SubElement(ET.SubElement(root, "channel"), "title").text = "Flow"
    else:
        root = ET.fromstring(feed)
    channel = root.find("channel")

    items = channel.findall("item")
    newest = max((_build_number(item) for item in items), default=-1)
    if build <= newest and not any(_build_number(item) == build for item in items):
        raise ReleaseError(f"build {build} is not newer than the feed's newest build {newest}")

    # Two entries with one build number make Sparkle check a download against
    # the wrong signature, so a rebuilt release replaces its old entry.
    for item in items:
        if _build_number(item) == build:
            channel.remove(item)

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Flow {version}"
    ET.SubElement(item, "pubDate").text = format_datetime(now or datetime.now(timezone.utc))
    ET.SubElement(item, _sparkle("version")).text = str(build)
    ET.SubElement(item, _sparkle("shortVersionString")).text = version
    ET.SubElement(item, _sparkle("minimumSystemVersion")).text = minimum_system
    ET.SubElement(item, _sparkle("releaseNotesLink")).text = notes_url
    ET.SubElement(item, "enclosure", {
        "url": url,
        "length": str(length),
        "type": "application/octet-stream",
        _sparkle("edSignature"): signature,
    })

    for stale in sorted(channel.findall("item"), key=_published, reverse=True)[FEED_KEEP:]:
        channel.remove(stale)

    ET.indent(root)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


# --- Steps ---


class Release:
    def __init__(self, version):
        self.version = version
        self.tag = f"v{version}"
        self.dmg = DIST / f"Flow-{version}.dmg"
        self.appcast = DIST / "appcast.xml"
        self.notes_url = f"https://getflowterm.app/releases/{version}"

    def release_exists(self):
        return succeeds("gh", "release", "view", self.tag, "--repo", REPO)

    def tag_commit(self):
        result = run("git", "rev-parse", "-q", "--verify", f"refs/tags/{self.tag}^{{commit}}", check=False, capture=True)
        return result.stdout.strip() if result.returncode == 0 else None

    def head(self):
        return output("git", "rev-parse", "HEAD")

    def previous_feed(self):
        """Only a repository with no releases at all starts a new feed. Once a
        release exists its feed must download, or older versions, and the
        users on older macOS they serve, would drop out of the feed."""
        releases = run("gh", "release", "list", "--repo", REPO, "--limit", "1", capture=True, check=False)
        if releases.returncode != 0:
            raise ReleaseError("could not list releases on GitHub")
        if not releases.stdout.strip():
            print("no releases yet; starting a new feed")
            return None
        previous = DIST / "appcast-previous.xml"
        previous.unlink(missing_ok=True)
        if not succeeds("gh", "release", "download", "--repo", REPO, "--pattern", "appcast.xml", "--output", previous):
            raise ReleaseError("could not download the published appcast.xml")
        feed = previous.read_bytes()
        previous.unlink()
        return feed

    def prepare_tag(self):
        commit = self.tag_commit()
        pushed = commit is not None and succeeds("git", "ls-remote", "--exit-code", "--tags", "origin", f"refs/tags/{self.tag}")
        action = tag_action(self.tag, commit, self.head(), pushed)
        if action == "create":
            run("git", "tag", "-a", self.tag, "-m", f"Flow {self.version}")
            print(f"tagged HEAD as {self.tag} (local only until --publish)")
        elif action == "move":
            run("git", "tag", "-f", "-a", self.tag, "-m", f"Flow {self.version}", quiet=True)
            print(f"moved the unpublished tag {self.tag} to HEAD")

    def check(self):
        step("Checking the tree and tools")
        # The ghostty submodule carries local build patches, so its working
        # copy is allowed to differ; everything else must be committed.
        if output("git", "status", "--porcelain", "--ignore-submodules=dirty"):
            raise ReleaseError("commit or stash your changes first")
        identity = developer_id(output("security", "find-identity", "-v", "-p", "codesigning"), TEAM)
        if not identity:
            raise ReleaseError(f"no Developer ID Application certificate for team {TEAM}")
        if not shutil.which("create-dmg"):
            raise ReleaseError("create-dmg not found (npm install --global create-dmg)")
        if not shutil.which("gh"):
            raise ReleaseError("gh not found")
        if not succeeds("xcrun", "notarytool", "history", "--keychain-profile", NOTARY_PROFILE):
            raise ReleaseError(f"notarytool profile {NOTARY_PROFILE} is missing")
        if self.release_exists():
            raise ReleaseError(f"release {self.tag} already exists on GitHub; published releases are never replaced")
        stamp = ROOT / "Vendor" / "GhosttyKit.stamp"
        if not stamp.exists() or stamp.read_text().strip() != output(ROOT / "scripts" / "ghosttykit-stamp.sh"):
            raise ReleaseError("libghostty is out of date or unrecorded; rebuild it with scripts/build-ghosttykit.sh")
        self.prepare_tag()
        print(f"signing as: {identity}")
        return identity

    def build(self):
        step("Building Release")
        shutil.rmtree(BUILD, ignore_errors=True)
        shutil.rmtree(DIST, ignore_errors=True)
        DIST.mkdir(parents=True)
        run("xcodegen", "generate", "--quiet")
        run("xcodebuild", "-scheme", "flow", "-configuration", "Release", "-derivedDataPath", BUILD, "build", "-quiet")
        plist = APP / "Contents" / "Info.plist"
        built = output("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", plist)
        number = output("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", plist)
        if built != self.version:
            raise ReleaseError(f"the app says {built}, expected {self.version}")
        print(f"Flow {built} ({number})")
        return int(number)

    def sign(self, identity):
        step("Signing")

        def sign(*args):
            run("codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp", *args)

        # Xcode signs Sparkle's outer framework but leaves the helpers inside
        # it ad-hoc, which notarization rejects. They are signed innermost
        # first, then the framework, then the app.
        sparkle = APP / "Contents" / "Frameworks" / "Sparkle.framework"
        sign(sparkle / "Versions/B/XPCServices/Installer.xpc")
        sign("--preserve-metadata=entitlements", sparkle / "Versions/B/XPCServices/Downloader.xpc")
        sign(sparkle / "Versions/B/Autoupdate")
        sign(sparkle / "Versions/B/Updater.app")
        sign(sparkle)
        sign("--entitlements", ROOT / "Resources" / "Flow.entitlements", APP)
        run("codesign", "--verify", "--deep", "--strict", APP)
        entitlements = run("codesign", "-d", "--entitlements", "-", APP, quiet=True).stdout
        if "get-task-allow" in entitlements:
            raise ReleaseError("the app carries get-task-allow, which notarization rejects")

    def package(self, identity):
        step("Packaging")
        run("create-dmg", APP, DIST, "--overwrite", f"--identity={identity}", quiet=True)
        (DIST / f"Flow {self.version}.dmg").rename(self.dmg)
        print(self.dmg)

    def notarize(self):
        step("Notarizing (this can take a few minutes)")
        submitted = run("xcrun", "notarytool", "submit", self.dmg, "--keychain-profile", NOTARY_PROFILE,
                        "--wait", "--output-format", "json", capture=True, check=False)
        report = DIST / "notarization.json"
        report.write_text(submitted.stdout)
        status, submission = notarization_result(submitted.stdout)
        if status != "Accepted":
            log = DIST / "notarization-log.json"
            if submission:
                run("xcrun", "notarytool", "log", submission, "--keychain-profile", NOTARY_PROFILE, log, check=False)
            raise ReleaseError(f"notarization {status}; see {report} and {log}")
        run("xcrun", "stapler", "staple", self.dmg)
        run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", self.dmg)
        print("notarized and stapled")

    def write_feed(self, build_number):
        step("Updating the Sparkle feed")
        sign_update = BUILD / "SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
        signature, length = parse_sign_update(output(sign_update, self.dmg))
        self.appcast.write_bytes(update_appcast(
            self.previous_feed(),
            version=self.version,
            build=build_number,
            url=f"https://github.com/{REPO}/releases/download/{self.tag}/{self.dmg.name}",
            length=length,
            signature=signature,
            notes_url=self.notes_url,
            minimum_system=MINIMUM_SYSTEM,
        ))
        print(self.appcast)

    def make(self):
        identity = self.check()
        build_number = self.build()
        self.sign(identity)
        self.package(identity)
        self.notarize()
        self.write_feed(build_number)
        step(f"Done. Review dist/, then run: uv run scripts/release.py {self.version} --publish")

    def publish(self):
        step(f"Publishing {self.tag}")
        if not (self.dmg.exists() and self.appcast.exists()):
            raise ReleaseError(f"build the release first: uv run scripts/release.py {self.version}")
        if self.release_exists():
            raise ReleaseError(f"release {self.tag} already exists on GitHub")
        if self.tag_commit() != self.head():
            raise ReleaseError(f"tag {self.tag} is not at HEAD")
        if not succeeds("xcrun", "stapler", "validate", self.dmg):
            raise ReleaseError(f"{self.dmg} is not notarized")
        branch = output("git", "branch", "--show-current")
        if not branch:
            raise ReleaseError("check out the branch being released")
        run("git", "push", "origin", branch, self.tag)
        run("gh", "release", "create", self.tag, self.dmg, self.appcast,
            "--repo", REPO, "--title", f"Flow {self.version}", "--notes", f"Release notes: {self.notes_url}")
        print(f"published https://github.com/{REPO}/releases/tag/{self.tag}")


def main():
    parser = argparse.ArgumentParser(description="Build, or publish, a Flow release.")
    parser.add_argument("version", help="X.Y.Z")
    parser.add_argument("--publish", action="store_true", help="publish the release already built in dist/")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("version must be X.Y.Z")

    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    release = Release(args.version)
    try:
        release.publish() if args.publish else release.make()
    except ReleaseError as error:
        sys.exit(f"error: {error}")


if __name__ == "__main__":
    main()
