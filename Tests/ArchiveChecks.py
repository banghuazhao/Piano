#!/usr/bin/env python3
"""Fixture checks for the archive inspector's rejection paths.

These fixtures intentionally have no Mach-O signature or provisioning profile.
They test structural parsing and error handling, not Apple trust verification.
"""

from __future__ import annotations

import plistlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "Scripts"))
import check_archive as inspector  # noqa: E402


class ArchiveChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="pianoflow-archive-")
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / "Piano.xcarchive"
        self.app = self.archive / "Products/Applications/Piano.app"
        self.app.mkdir(parents=True)
        self.expected = inspector.Expectations(
            "com.appsbay.PianoFlow", "1.2", "7", "17.6", "F694X76A5X",
            frozenset({1, 2}), "Piano", "AppIcon")
        self.info = {
            "CFBundleIdentifier": self.expected.bundle_id,
            "CFBundleShortVersionString": self.expected.version,
            "CFBundleVersion": self.expected.build,
            "MinimumOSVersion": self.expected.minimum_os,
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "DTPlatformName": "iphoneos",
            "UIDeviceFamily": [1, 2],
            "CFBundleExecutable": "Piano",
            "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"}},
            "GADApplicationIdentifier": "ca-app-pub-1234567890123456~1234567890",
            "bannerViewAdUnitID": "ca-app-pub-1234567890123456/1234567890",
            "appOpenAdID": "ca-app-pub-1234567890123456/2234567890",
        }
        self.properties = {
            "ApplicationPath": "Applications/Piano.app",
            "CFBundleIdentifier": self.expected.bundle_id,
            "CFBundleShortVersionString": self.expected.version,
            "CFBundleVersion": self.expected.build,
            "Team": self.expected.team,
        }
        self.write_plist(self.app / "Info.plist", self.info)
        self.write_plist(self.archive / "Info.plist", {
            "ArchiveVersion": 2, "ApplicationProperties": self.properties})
        self.write_plist(self.app / "PrivacyInfo.xcprivacy", {
            "NSPrivacyAccessedAPITypes": [{
                "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
            }]})
        (self.app / "Piano").write_bytes(b"not a Mach-O executable")
        (self.app / "Assets.car").write_bytes(b"fixture")

    @staticmethod
    def write_plist(path: Path, value: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps(value))

    def test_structural_fixture_accepts_metadata_privacy_and_ads(self) -> None:
        app, properties, info = inspector.archive_paths(self.archive, self.expected)
        self.assertEqual(inspector.validate_metadata(app, properties, info, self.expected),
                         self.app / "Piano")
        inspector.validate_no_dev_files(self.archive)
        inspector.validate_privacy(app)
        inspector.validate_ad_settings(info)

    def test_swapped_version_is_rejected(self) -> None:
        self.info["CFBundleVersion"] = "8"
        self.write_plist(self.app / "Info.plist", self.info)
        app, properties, info = inspector.archive_paths(self.archive, self.expected)
        with self.assertRaisesRegex(inspector.ArchiveError, "CFBundleVersion"):
            inspector.validate_metadata(app, properties, info, self.expected)

    def test_numeric_version_and_build_are_rejected(self) -> None:
        for key, value in (("CFBundleShortVersionString", 1.2), ("CFBundleVersion", 7)):
            with self.subTest(key=key):
                info = dict(self.info)
                info[key] = value
                self.write_plist(self.app / "Info.plist", info)
                app, properties, parsed_info = inspector.archive_paths(self.archive, self.expected)
                with self.assertRaisesRegex(inspector.ArchiveError, key):
                    inspector.validate_metadata(app, properties, parsed_info, self.expected)

    def test_malformed_device_families_are_rejected_cleanly(self) -> None:
        for families in ([True, 2], [1, 1, 2], [[1], 2]):
            with self.subTest(families=families):
                info = dict(self.info)
                info["UIDeviceFamily"] = families
                self.write_plist(self.app / "Info.plist", info)
                app, properties, parsed_info = inspector.archive_paths(self.archive, self.expected)
                with self.assertRaisesRegex(inspector.ArchiveError, "device families"):
                    inspector.validate_metadata(app, properties, parsed_info, self.expected)

    def test_app_bundle_symlink_outside_archive_is_rejected(self) -> None:
        outside = Path(self.temp.name) / "External/Piano.app"
        outside.parent.mkdir(parents=True)
        self.app.rename(outside)
        self.app.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(inspector.ArchiveError):
            inspector.archive_paths(self.archive, self.expected)

    def test_truncated_xml_is_reported_as_archive_error(self) -> None:
        (self.app / "Info.plist").write_bytes(b"<plist><dict>")
        with self.assertRaisesRegex(inspector.ArchiveError, "valid property list"):
            inspector.archive_paths(self.archive, self.expected)

    def test_embedded_config_is_rejected(self) -> None:
        (self.app / "Release.xcconfig").write_text("private fixture")
        with self.assertRaisesRegex(inspector.ArchiveError, "Release.xcconfig"):
            inspector.validate_no_dev_files(self.archive)

    def test_malformed_root_and_embedded_privacy_are_rejected(self) -> None:
        (self.app / "PrivacyInfo.xcprivacy").write_text("not a plist")
        with self.assertRaisesRegex(inspector.ArchiveError, "valid property list"):
            inspector.validate_privacy(self.app)
        self.write_plist(self.app / "PrivacyInfo.xcprivacy", {"NSPrivacyTracking": False})
        embedded = self.app / "Frameworks/Example.framework/PrivacyInfo.xcprivacy"
        self.write_plist(embedded, {"UnexpectedPrivacyKey": []})
        with self.assertRaisesRegex(inspector.ArchiveError, "unexpected"):
            inspector.validate_privacy(self.app)

    def test_unresolved_ad_setting_is_rejected_without_echo(self) -> None:
        self.info["appOpenAdID"] = "$(appOpenAdID)"
        with self.assertRaises(inspector.ArchiveError) as raised:
            inspector.validate_ad_settings(self.info)
        self.assertIn("appOpenAdID", str(raised.exception))
        self.assertNotIn("$(appOpenAdID)", str(raised.exception))

    def test_missing_signature_is_rejected(self) -> None:
        with self.assertRaisesRegex(inspector.ArchiveError, "signature"):
            inspector.validate_signing(self.app, self.properties, self.expected)

    def test_profile_app_identifier_rules(self) -> None:
        app_id = f"{self.expected.team}.{self.expected.bundle_id}"
        wildcard = f"{self.expected.team}.*"
        inspector.validate_app_identifier(
            app_id, app_id, self.expected, "App Store", True)
        inspector.validate_app_identifier(
            app_id, wildcard, self.expected, "Development", False)
        for kind, require_app_store in (("App Store", False), ("Development", True)):
            with self.subTest(kind=kind, require_app_store=require_app_store):
                with self.assertRaises(inspector.ArchiveError):
                    inspector.validate_app_identifier(
                        app_id, wildcard, self.expected, kind, require_app_store)
        with self.assertRaises(inspector.ArchiveError):
            inspector.validate_app_identifier(
                f"OTHERTEAM.{self.expected.bundle_id}", wildcard,
                self.expected, "Development", False)
        with self.assertRaises(inspector.ArchiveError):
            inspector.validate_app_identifier(
                app_id, f"{self.expected.team}.different.app",
                self.expected, "Development", False)

    def test_signer_certificate_must_be_in_embedded_profile(self) -> None:
        leaf_certificate = b"fixture signing certificate DER"

        def fake_tool(args: list[str], message: str, **kwargs: object) -> bytes:
            self.assertEqual(args[:2], ["codesign", "-d"])
            self.assertTrue(args[2].startswith("--extract-certificates="))
            self.assertEqual(args[3], str(self.app))
            prefix = args[2].split("=", 1)[1]
            Path(prefix + "0").write_bytes(leaf_certificate)
            return b""

        with patch.object(inspector, "tool", side_effect=fake_tool):
            inspector.signer_certificate_matches_profile(
                self.app, {"DeveloperCertificates": [b"other", leaf_certificate]})
            with self.assertRaises(inspector.ArchiveError):
                inspector.signer_certificate_matches_profile(
                    self.app, {"DeveloperCertificates": [b"different certificate"]})
            with self.assertRaises(inspector.ArchiveError):
                inspector.signer_certificate_matches_profile(
                    self.app, {"DeveloperCertificates": []})

    def test_mismatched_dsym_uuid_is_rejected(self) -> None:
        binary = inspector.parse_uuids(
            b"UUID: AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA (arm64) Piano\n")
        symbols = inspector.parse_uuids(
            b"UUID: BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB (arm64) Piano.app.dSYM\n")
        with self.assertRaisesRegex(inspector.ArchiveError, "dSYM UUIDs"):
            inspector.compare_dsym_uuids(binary, symbols)


if __name__ == "__main__":
    unittest.main()
