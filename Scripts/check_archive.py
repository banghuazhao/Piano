#!/usr/bin/env python3
"""Read-only structural and signing checks for a PianoFlow .xcarchive.

This validates an archive before Xcode exports and App Store Connect processes it.
It deliberately never prints ad identifiers, signing entitlements, or profile data.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from xml.parsers.expat import ExpatError


REPO = Path(__file__).resolve().parent.parent
TEAM_PATTERN = re.compile(r"^[A-Z0-9]{10}$")
UUID_LINE = re.compile(r"^UUID: ([0-9A-Fa-f-]{36}) \(([^)]+)\) ")
PRIVACY_KEYS = {
    "NSPrivacyTracking",
    "NSPrivacyTrackingDomains",
    "NSPrivacyCollectedDataTypes",
    "NSPrivacyAccessedAPITypes",
}
FORBIDDEN_SUFFIXES = {".xcconfig", ".storekit", ".xctest", ".xcresult", ".dSYM"}


class ArchiveError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ArchiveError(message)


def tool(args: list[str], message: str, *, env: dict[str, str] | None = None) -> bytes:
    try:
        result = subprocess.run(args, capture_output=True, env=env, timeout=45, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ArchiveError(message) from error
    require(result.returncode == 0, message)
    return result.stdout


def plist(path: Path, label: str) -> dict:
    require(path.is_file(), f"{label} is missing.")
    try:
        value = plistlib.loads(path.read_bytes())
    except (OSError, ValueError, TypeError, OverflowError, ExpatError) as error:
        raise ArchiveError(f"{label} is not a valid property list.") from error
    require(isinstance(value, dict), f"{label} must contain a dictionary.")
    return value


@dataclass(frozen=True)
class Expectations:
    bundle_id: str
    version: str
    build: str
    minimum_os: str
    team: str
    device_families: frozenset[int]
    app_name: str
    icon_name: str


def project_expectations(project: Path = REPO / "Piano.xcodeproj/project.pbxproj") -> Expectations:
    raw = tool(["plutil", "-convert", "json", "-o", "-", str(project)],
               "The Xcode project could not be read for archive expectations.")
    try:
        objects = json.loads(raw)["objects"]
        target = next(value for value in objects.values()
                      if value.get("isa") == "PBXNativeTarget" and value.get("name") == "Piano")
        configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
        release = next(objects[key] for key in configs if objects[key]["name"] == "Release")
        settings = release["buildSettings"]
        values = [str(settings[key]) for key in (
            "PRODUCT_BUNDLE_IDENTIFIER", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION",
            "IPHONEOS_DEPLOYMENT_TARGET", "DEVELOPMENT_TEAM", "TARGETED_DEVICE_FAMILY",
            "ASSETCATALOG_COMPILER_APPICON_NAME")]
        families = frozenset(int(item.strip()) for item in values[5].split(","))
    except (ValueError, TypeError, KeyError, StopIteration) as error:
        raise ArchiveError("Release app expectations are missing from the Xcode project.") from error
    require(all("$(" not in value and "${" not in value for value in values),
            "Release app expectations must be literal project values.")
    require(bool(TEAM_PATTERN.fullmatch(values[4])), "Release development team is invalid.")
    require(families == frozenset({1, 2}), "Unexpected Release device families.")
    return Expectations(values[0], values[1], values[2], values[3], values[4],
                        families, target["name"], values[6])


def archive_paths(archive: Path, expected: Expectations) -> tuple[Path, dict, dict]:
    require(archive.is_dir() and archive.suffix == ".xcarchive",
            "Input must be an existing .xcarchive directory.")
    archive_info = plist(archive / "Info.plist", "Archive Info.plist")
    require(archive_info.get("ArchiveVersion") == 2,
            "Archive Info.plist has an unexpected archive format version.")
    properties = archive_info.get("ApplicationProperties")
    require(isinstance(properties, dict), "Archive application metadata is missing.")
    relative = properties.get("ApplicationPath")
    require(isinstance(relative, str), "Archive application path is missing.")
    path = PurePosixPath(relative)
    require(not path.is_absolute() and ".." not in path.parts and path.parts[:1] == ("Applications",),
            "Archive application path is invalid.")
    products = archive / "Products"
    require(products.is_dir() and not products.is_symlink(),
            "Archive Products directory is missing or is a symbolic link.")
    app = products / Path(*path.parts)
    try:
        app.resolve(strict=True).relative_to(products.resolve())
    except (OSError, RuntimeError, ValueError) as error:
        raise ArchiveError("Archive application path escapes Products or is broken.") from error
    require(app.is_dir() and app.name == f"{expected.app_name}.app",
            "Archive does not contain the expected app bundle.")
    applications = products / "Applications"
    require(len(list(applications.glob("*.app"))) == 1,
            "Archive must contain exactly one application bundle.")
    app_info = plist(app / "Info.plist", "App Info.plist")
    return app, properties, app_info


def validate_metadata(app: Path, properties: dict, info: dict, expected: Expectations) -> Path:
    fields = (
        ("CFBundleIdentifier", expected.bundle_id),
        ("CFBundleShortVersionString", expected.version),
        ("CFBundleVersion", expected.build),
    )
    for key, value in fields:
        require(isinstance(info.get(key), str) and info[key] == value,
                f"App {key} differs from the Release project.")
        require(isinstance(properties.get(key), str) and properties[key] == value,
                f"Archive {key} differs from the app and Release project.")
    require(isinstance(info.get("MinimumOSVersion"), str) and
            info["MinimumOSVersion"] == expected.minimum_os,
            "App MinimumOSVersion differs from the Release deployment target.")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"] and
            info.get("DTPlatformName") == "iphoneos",
            "Archive is not an iOS device build.")
    families = info.get("UIDeviceFamily")
    require(isinstance(families, list) and
            len(families) == len(expected.device_families) and
            all(type(family) is int for family in families) and
            frozenset(families) == expected.device_families,
            "App device families differ from the Release project.")
    icons = info.get("CFBundleIcons")
    require(isinstance(icons, dict), "Primary icon metadata or asset catalog is missing or incorrect.")
    icon = icons.get("CFBundlePrimaryIcon")
    require(isinstance(icon, dict), "Primary icon metadata or asset catalog is missing or incorrect.")
    require(icon.get("CFBundleIconName") == expected.icon_name and (app / "Assets.car").is_file(),
            "Primary icon metadata or asset catalog is missing or incorrect.")
    executable_name = info.get("CFBundleExecutable")
    require(isinstance(executable_name, str) and executable_name == expected.app_name,
            "App executable name is incorrect.")
    executable = app / executable_name
    require(executable.is_file(), "App executable is missing.")
    return executable


def validate_no_dev_files(archive: Path) -> None:
    products = archive / "Products"
    require(products.is_dir() and not products.is_symlink(),
            "Archive Products directory is missing or is a symbolic link.")
    products_root = products.resolve()
    for path in products.rglob("*"):
        if path.is_symlink():
            try:
                path.resolve(strict=True).relative_to(products_root)
            except (OSError, RuntimeError, ValueError) as error:
                raise ArchiveError(f"Archive Products contains an escaping or broken symbolic link: {path.name}.") from error
        if any(path.name.lower().endswith(suffix.lower()) for suffix in FORBIDDEN_SUFFIXES):
            raise ArchiveError(f"Development or test artifact is embedded in Products: {path.name}.")


def _strings(values: object, label: str, *, nonempty: bool = False) -> None:
    require(isinstance(values, list), f"{label} must be an array.")
    require(not nonempty or len(values) > 0, f"{label} must not be empty.")
    require(all(isinstance(value, str) and value for value in values),
            f"{label} must contain nonempty strings.")


def validate_privacy_manifest(path: Path) -> None:
    data = plist(path, f"Privacy manifest {path.name}")
    require(bool(data) and set(data) <= PRIVACY_KEYS,
            f"Privacy manifest at {path.parent.name} has unexpected or no keys.")
    if "NSPrivacyTracking" in data:
        require(type(data["NSPrivacyTracking"]) is bool, "Privacy tracking must be a Boolean.")
    if "NSPrivacyTrackingDomains" in data:
        _strings(data["NSPrivacyTrackingDomains"], "Privacy tracking domains")
    if "NSPrivacyAccessedAPITypes" in data:
        entries = data["NSPrivacyAccessedAPITypes"]
        require(isinstance(entries, list), "Privacy accessed API types must be an array.")
        for entry in entries:
            require(isinstance(entry, dict) and set(entry) == {
                "NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"},
                "Privacy accessed API entry has invalid keys.")
            require(isinstance(entry["NSPrivacyAccessedAPIType"], str) and
                    bool(entry["NSPrivacyAccessedAPIType"]),
                    "Privacy accessed API type is invalid.")
            _strings(entry["NSPrivacyAccessedAPITypeReasons"],
                     "Privacy accessed API reasons", nonempty=True)
    if "NSPrivacyCollectedDataTypes" in data:
        entries = data["NSPrivacyCollectedDataTypes"]
        require(isinstance(entries, list), "Privacy collected data types must be an array.")
        for entry in entries:
            require(isinstance(entry, dict) and set(entry) == {
                "NSPrivacyCollectedDataType", "NSPrivacyCollectedDataTypeLinked",
                "NSPrivacyCollectedDataTypeTracking", "NSPrivacyCollectedDataTypePurposes"},
                "Privacy collected data entry has invalid keys.")
            require(isinstance(entry["NSPrivacyCollectedDataType"], str) and
                    bool(entry["NSPrivacyCollectedDataType"]),
                    "Privacy collected data type is invalid.")
            require(type(entry["NSPrivacyCollectedDataTypeLinked"]) is bool and
                    type(entry["NSPrivacyCollectedDataTypeTracking"]) is bool,
                    "Privacy collected data flags must be Boolean.")
            _strings(entry["NSPrivacyCollectedDataTypePurposes"],
                     "Privacy collected data purposes", nonempty=True)


def validate_privacy(app: Path) -> None:
    require((app / "PrivacyInfo.xcprivacy").is_file(),
            "The app root PrivacyInfo.xcprivacy is missing.")
    manifests = list(app.rglob("PrivacyInfo.xcprivacy"))
    for path in manifests:
        validate_privacy_manifest(path)
    print(f"Privacy manifests parsed: {len(manifests)}.")


def validate_ad_settings(info: dict, validator: Path = REPO / "Scripts/check-release-config.sh") -> None:
    env = {"PATH": "/usr/bin:/bin"}
    for key in ("GADApplicationIdentifier", "bannerViewAdUnitID", "appOpenAdID"):
        value = info.get(key, "")
        env[key] = value if isinstance(value, str) else ""
    try:
        result = subprocess.run(["/bin/bash", str(validator)], capture_output=True,
                                env=env, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ArchiveError("Release ad settings could not be validated.") from error
    if result.returncode:
        # This validator reports names/reasons only; it never prints values.
        reason = result.stderr.decode("utf-8", "replace").strip()
        raise ArchiveError(reason or "Release ad settings are invalid.")
    print("Embedded Release ad settings validated.")


def validate_device_binary(executable: Path, expected: Expectations) -> None:
    arches = tool(["xcrun", "lipo", "-archs", str(executable)],
                  "App executable is not a readable Mach-O binary.").decode("utf-8", "replace").split()
    require("arm64" in arches and set(arches) <= {"arm64", "arm64e"},
            "App executable must contain only supported iOS device architectures.")
    for arch in arches:
        build = tool(["xcrun", "vtool", "-arch", arch, "-show-build", str(executable)],
                     "App executable has no readable platform load command.").decode("utf-8", "replace")
        require(re.search(r"^\s*platform IOS\s*$", build, re.MULTILINE) is not None,
                f"App executable {arch} slice is not built for iOS devices.")
        match = re.search(r"^\s*minos ([0-9.]+)\s*$", build, re.MULTILINE)
        require(match is not None and match.group(1) == expected.minimum_os,
                f"App executable {arch} minimum OS differs from the Release project.")


def parse_uuids(output: bytes) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in output.decode("utf-8", "replace").splitlines():
        match = UUID_LINE.match(line)
        if match:
            values[match.group(2)] = match.group(1).upper()
    return values


def compare_dsym_uuids(binary: dict[str, str], symbols: dict[str, str]) -> None:
    require(bool(binary) and binary == symbols,
            "App dSYM UUIDs do not match the archived executable for every architecture.")


def validate_dsym(archive: Path, app: Path, executable: Path) -> None:
    symbols = archive / "dSYMs" / f"{app.name}.dSYM"
    require(symbols.is_dir(), "The app dSYM is missing from the archive.")
    binary_uuids = parse_uuids(tool(["xcrun", "dwarfdump", "--uuid", str(executable)],
                                   "App executable UUIDs could not be read."))
    symbol_uuids = parse_uuids(tool(["xcrun", "dwarfdump", "--uuid", str(symbols)],
                                   "App dSYM UUIDs could not be read."))
    compare_dsym_uuids(binary_uuids, symbol_uuids)


def _profile_type(profile: dict) -> str:
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("get-task-allow") is True:
        return "Development"
    if profile.get("ProvisionsAllDevices") is True:
        return "Enterprise"
    if profile.get("ProvisionedDevices"):
        return "Ad Hoc"
    if entitlements.get("beta-reports-active") is True:
        return "App Store"
    return "Unrecognized"


def _profile_authorizes(app_identifier: str, profile_identifier: object) -> bool:
    if not isinstance(profile_identifier, str):
        return False
    if profile_identifier.endswith(".*"):
        return app_identifier.startswith(profile_identifier[:-1])
    return app_identifier == profile_identifier


def validate_app_identifier(app_identifier: object, profile_identifier: object,
                            expected: Expectations, kind: str,
                            require_app_store: bool) -> None:
    expected_identifier = f"{expected.team}.{expected.bundle_id}"
    require(app_identifier == expected_identifier,
            "Signed application identifier differs from the Release app and team.")
    if kind == "App Store" or require_app_store:
        require(profile_identifier == expected_identifier,
                "App Store signing requires an explicit provisioning App ID for this app.")
    else:
        require(_profile_authorizes(expected_identifier, profile_identifier),
                "Provisioning profile does not authorize the signed application identifier.")


def signer_certificate_matches_profile(app: Path, profile: dict) -> None:
    certificates = profile.get("DeveloperCertificates")
    require(isinstance(certificates, list) and bool(certificates) and
            all(isinstance(certificate, bytes) and certificate for certificate in certificates),
            "Provisioning profile has no valid developer certificates.")
    try:
        with tempfile.TemporaryDirectory(prefix="pianoflow-signing-") as directory:
            prefix = Path(directory) / "certificate-"
            tool(["codesign", "-d", f"--extract-certificates={prefix}", str(app)],
                 "App signing certificate could not be extracted.")
            leaf = Path(f"{prefix}0")
            require(leaf.is_file(), "App signing certificate could not be extracted.")
            require(leaf.read_bytes() in certificates,
                    "App signing certificate is not authorized by the embedded provisioning profile.")
    except OSError as error:
        raise ArchiveError("App signing certificate could not be compared with the profile.") from error


def validate_signing(app: Path, properties: dict, expected: Expectations,
                     require_app_store: bool = False) -> str:
    tool(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)],
         "The app code signature failed strict verification.")
    requirement = (f'=anchor apple generic and identifier = "{expected.bundle_id}" '
                   f'and certificate leaf[subject.OU] = "{expected.team}"')
    tool(["codesign", "--verify", "-R", requirement, str(app)],
         "The app signature is not anchored to Apple for the expected app and team.")
    try:
        detail = subprocess.run(["codesign", "-d", "--verbose=4", str(app)],
                                capture_output=True, timeout=45, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ArchiveError("The app signing identity could not be read.") from error
    require(detail.returncode == 0, "The app signing identity could not be read.")
    lines = (detail.stdout + detail.stderr).decode("utf-8", "replace").splitlines()
    fields = [line.split("=", 1) for line in lines if "=" in line]
    team = next((value for key, value in fields if key == "TeamIdentifier"), None)
    authorities = [value for key, value in fields if key == "Authority"]
    require(team == expected.team and properties.get("Team") == expected.team,
            "Archive and app signing teams differ from the Release project.")
    require(bool(authorities) and authorities[0].startswith((
        "Apple Development:", "Apple Distribution:", "iPhone Developer:", "iPhone Distribution:")),
        "The app is not signed with a recognized Apple iOS development/distribution identity.")
    archived_identity = properties.get("SigningIdentity")
    require(isinstance(archived_identity, str) and archived_identity == authorities[0],
            "Archive signing identity differs from the app signature.")

    entitlements_xml = tool(["codesign", "-d", "--entitlements", "-", "--xml", str(app)],
                            "App signing entitlements could not be read.")
    try:
        entitlements = plistlib.loads(entitlements_xml)
    except (ValueError, TypeError, OverflowError, ExpatError) as error:
        raise ArchiveError("App signing entitlements are invalid.") from error
    require(isinstance(entitlements, dict), "App signing entitlements are invalid.")
    require(entitlements.get("com.apple.developer.team-identifier") == expected.team,
            "Signed entitlement team differs from the Release project.")
    app_identifier = entitlements.get("application-identifier")
    require(isinstance(app_identifier, str), "Signed application identifier is missing.")

    embedded = app / "embedded.mobileprovision"
    require(embedded.is_file(), "Embedded iOS provisioning profile is missing.")
    profile_xml = tool(["security", "cms", "-D", "-i", str(embedded)],
                       "Embedded provisioning profile could not be decoded.")
    try:
        profile = plistlib.loads(profile_xml)
    except (ValueError, TypeError, OverflowError, ExpatError) as error:
        raise ArchiveError("Embedded provisioning profile is invalid.") from error
    require(isinstance(profile, dict), "Embedded provisioning profile is invalid.")
    profile_teams = profile.get("TeamIdentifier")
    require(isinstance(profile_teams, list) and expected.team in profile_teams,
            "Provisioning profile team differs from the Release project.")
    profile_entitlements = profile.get("Entitlements")
    require(isinstance(profile_entitlements, dict),
            "Provisioning profile entitlements are missing.")
    require(profile_entitlements.get("com.apple.developer.team-identifier") == expected.team,
            "Provisioning profile entitlement team is incorrect.")
    expiration = profile.get("ExpirationDate")
    require(isinstance(expiration, dt.datetime), "Provisioning profile has no expiration date.")
    now = dt.datetime.now(expiration.tzinfo) if expiration.tzinfo else dt.datetime.utcnow()
    require(expiration > now, "Provisioning profile has expired.")
    profile_allows_debugging = profile_entitlements.get("get-task-allow") is True
    signed_allows_debugging = entitlements.get("get-task-allow") is True
    require(profile_allows_debugging == signed_allows_debugging,
            "Signed debugging entitlement differs from the provisioning profile.")
    kind = _profile_type(profile)
    require(kind != "Unrecognized", "Provisioning profile type could not be classified.")
    profile_identifier = profile_entitlements.get("application-identifier")
    validate_app_identifier(app_identifier, profile_identifier, expected, kind, require_app_store)
    signer_certificate_matches_profile(app, profile)
    is_development_identity = authorities[0].startswith(("Apple Development:", "iPhone Developer:"))
    require(is_development_identity == (kind == "Development"),
            "Signing identity and provisioning profile types differ.")
    if require_app_store:
        require(kind == "App Store" and not signed_allows_debugging,
                "App Store signing requires an App Store profile and disabled debugging entitlement.")
    if kind == "Development" and isinstance(profile_identifier, str) and profile_identifier.endswith(".*"):
        print("Wildcard Development App ID accepted for this archive; App Store export must re-sign with an explicit App ID profile for In-App Purchase.")
    return kind


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only PianoFlow .xcarchive validation")
    parser.add_argument("archive", type=Path, help="Path to a PianoFlow .xcarchive directory")
    parser.add_argument("--require-app-store-signing", action="store_true",
                        help="Require App Store profile/identity instead of allowing development-signed archives")
    parser.add_argument("--allow-unsigned", action="store_true",
                        help="diagnostic-only structural check; never certifies a release archive")
    args = parser.parse_args(argv)
    if args.allow_unsigned and args.require_app_store_signing:
        parser.error("--allow-unsigned cannot be combined with --require-app-store-signing")
    try:
        expected = project_expectations()
        archive = args.archive.resolve()
        app, properties, info = archive_paths(archive, expected)
        executable = validate_metadata(app, properties, info, expected)
        validate_no_dev_files(archive)
        validate_privacy(app)
        validate_ad_settings(info)
        validate_device_binary(executable, expected)
        validate_dsym(archive, app, executable)
        if args.allow_unsigned:
            print("DIAGNOSTIC ONLY: signing/profile checks skipped; this is not a release pass.")
        else:
            kind = validate_signing(app, properties, expected, args.require_app_store_signing)
            print(f"Apple-anchored signature and embedded profile validated; profile type: {kind}.")
            if kind != "App Store":
                print("This archive requires Xcode distribution export/re-signing before App Store upload.")
        print("Archive checks passed. Xcode export and App Store Connect validation remain required.")
        return 0
    except ArchiveError as error:
        print(f"error: Archive validation: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
