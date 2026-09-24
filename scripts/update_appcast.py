#!/usr/bin/env python3
"""Adds a release to Flow's Sparkle appcast.

Sparkle offers each user the newest entry whose build number is higher than
theirs and whose minimum macOS they meet, so older entries stay in the feed:
a user on an older macOS still finds the last release that runs there. The
feed keeps the newest KEEP entries.

Usage:
  update_appcast.py FEED_IN FEED_OUT --version 0.1.0 --build 142 \
      --url https://.../Flow-0.1.0.dmg --length 1234 --signature BASE64 \
      --notes-url https://getflowterm.app/releases/0.1.0 --minimum-system 14.0

FEED_IN may be missing (first release).
"""

import argparse
import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime, parsedate_to_datetime

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
KEEP = 15


def sparkle(tag):
    return f"{{{SPARKLE}}}{tag}"


def empty_feed():
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Flow"
    return ET.ElementTree(rss)


def build_number(item):
    element = item.find(sparkle("version"))
    return int(element.text) if element is not None and element.text and element.text.isdigit() else -1


def published(item):
    element = item.find("pubDate")
    try:
        return parsedate_to_datetime(element.text)
    except (AttributeError, TypeError, ValueError):
        return datetime.min.replace(tzinfo=timezone.utc)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("feed_in")
    parser.add_argument("feed_out")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--notes-url", required=True)
    parser.add_argument("--minimum-system", required=True)
    args = parser.parse_args()

    ET.register_namespace("sparkle", SPARKLE)
    tree = ET.parse(args.feed_in) if os.path.exists(args.feed_in) else empty_feed()
    channel = tree.getroot().find("channel")

    items = channel.findall("item")
    newest = max((build_number(item) for item in items), default=-1)
    if args.build <= newest and not any(build_number(item) == args.build for item in items):
        sys.exit(f"build {args.build} is not newer than the feed's newest build {newest}")

    # Two entries with one build number make Sparkle check a download against
    # the wrong signature, so a rebuilt release replaces its old entry.
    for item in items:
        if build_number(item) == args.build:
            channel.remove(item)

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Flow {args.version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, sparkle("version")).text = str(args.build)
    ET.SubElement(item, sparkle("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = args.minimum_system
    ET.SubElement(item, sparkle("releaseNotesLink")).text = args.notes_url
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": args.length,
        "type": "application/octet-stream",
        sparkle("edSignature"): args.signature,
    })

    items = sorted(channel.findall("item"), key=published, reverse=True)
    for stale in items[KEEP:]:
        channel.remove(stale)

    ET.indent(tree)
    tree.write(args.feed_out, xml_declaration=True, encoding="utf-8")


if __name__ == "__main__":
    main()
