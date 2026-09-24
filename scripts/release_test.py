#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""uv run scripts/release_test.py"""

import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone

from release import (
    FEED_KEEP,
    SPARKLE_NS,
    ReleaseError,
    can_resume,
    developer_id,
    notarization_result,
    parse_sign_update,
    tag_action,
    update_appcast,
)

START = datetime(2026, 1, 1, tzinfo=timezone.utc)


def add(feed, build, version=None, now=START, signature="sig"):
    return update_appcast(
        feed,
        version=version or f"0.{build}.0",
        build=build,
        url=f"https://example.com/{build}.dmg",
        length=100,
        signature=signature,
        notes_url=f"https://getflowterm.app/releases/{build}",
        minimum_system="14.0",
        now=now,
    )


def builds(feed):
    return [int(item.find(f"{{{SPARKLE_NS}}}version").text) for item in ET.fromstring(feed).iter("item")]


class TagTests(unittest.TestCase):
    def test_creates_a_missing_tag(self):
        self.assertEqual(tag_action("v0.1.0", None, "abc", pushed=False), "create")

    def test_keeps_a_tag_at_head(self):
        self.assertEqual(tag_action("v0.1.0", "abc", "abc", pushed=True), "keep")

    def test_moves_an_unpushed_tag_to_head(self):
        self.assertEqual(tag_action("v0.1.0", "old", "abc", pushed=False), "move")

    def test_never_moves_a_pushed_tag(self):
        with self.assertRaisesRegex(ReleaseError, "v0.1.0 is already pushed"):
            tag_action("v0.1.0", "old", "abc", pushed=True)


class ResumeTests(unittest.TestCase):
    STATE = {"version": "0.1.0", "commit": "abc", "build": 42, "submission": "id"}

    def test_resumes_the_build_of_the_tagged_commit(self):
        self.assertTrue(can_resume(self.STATE, "0.1.0", "abc"))

    def test_rebuilds_when_anything_differs(self):
        self.assertFalse(can_resume(None, "0.1.0", "abc"))
        self.assertFalse(can_resume(self.STATE, "0.1.1", "abc"))
        self.assertFalse(can_resume(self.STATE, "0.1.0", "moved"))
        self.assertFalse(can_resume(self.STATE, "0.1.0", None))


class NotarizationTests(unittest.TestCase):
    def test_reads_status_and_id(self):
        self.assertEqual(notarization_result('{"id": "123", "status": "Invalid"}'), ("Invalid", "123"))

    def test_unreadable_output_is_unknown(self):
        for text in ["", "Error: network", "[]", "{}"]:
            with self.subTest(text=text):
                self.assertEqual(notarization_result(text)[0], "unknown")


class ToolOutputTests(unittest.TestCase):
    def test_sign_update(self):
        text = 'sparkle:edSignature="ab+/cd==" length="4096"\n'
        self.assertEqual(parse_sign_update(text), ("ab+/cd==", 4096))

    def test_sign_update_without_signature(self):
        with self.assertRaises(ReleaseError):
            parse_sign_update("error: no key in keychain")

    def test_developer_id_for_the_team(self):
        text = '''  1) AAA "Apple Development: Someone (ZZZ)"
  2) BBB "Developer ID Application: Someone (OTHERTEAM)"
  3) CCC "Developer ID Application: Someone (DP5STKBRSS)"
     3 valid identities found'''
        self.assertEqual(developer_id(text, "DP5STKBRSS"), "Developer ID Application: Someone (DP5STKBRSS)")
        self.assertIsNone(developer_id(text, "NOPE"))


class AppcastTests(unittest.TestCase):
    def test_first_release_starts_a_feed(self):
        feed = add(None, 10, version="0.1.0")
        root = ET.fromstring(feed)
        item = root.find("channel/item")
        self.assertEqual(builds(feed), [10])
        self.assertEqual(item.find("title").text, "Flow 0.1.0")
        self.assertEqual(item.find(f"{{{SPARKLE_NS}}}minimumSystemVersion").text, "14.0")
        self.assertEqual(item.find("enclosure").get(f"{{{SPARKLE_NS}}}edSignature"), "sig")
        self.assertIn(b"xmlns:sparkle", feed)

    def test_later_release_keeps_older_entries(self):
        feed = add(add(None, 10), 20, now=START + timedelta(days=1))
        self.assertEqual(sorted(builds(feed)), [10, 20])

    def test_refuses_another_version_with_the_same_build(self):
        feed = add(None, 10, version="0.1.0")
        with self.assertRaisesRegex(ReleaseError, "not newer"):
            add(feed, 10, version="0.1.1")

    def test_refuses_an_older_build(self):
        with self.assertRaisesRegex(ReleaseError, "not newer"):
            add(add(None, 20), 10)

    def test_keeps_the_newest_entries(self):
        feed = None
        for n in range(FEED_KEEP + 3):
            feed = add(feed, n + 1, now=START + timedelta(days=n))
        self.assertEqual(sorted(builds(feed)), list(range(4, FEED_KEEP + 4)))


if __name__ == "__main__":
    unittest.main()
