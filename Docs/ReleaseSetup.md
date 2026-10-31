# Release build setup

The checked-in `Piano/Config/Release.base.xcconfig` is the base configuration for both Release project and app settings. It optionally includes the ignored `Piano/Config/Release.xcconfig`. This keeps a clean checkout openable and Debug builds usable while making missing Release ad settings a clear build error. The local override already present on a developer machine is not changed by this setup.

## Supply the Release ad IDs

Get the production AdMob **app ID**, **banner ad unit ID**, and **app-open ad unit ID** for the same AdMob publisher. `Piano/Config/Release.example.xcconfig` lists the required setting names. Google sample IDs and placeholders are rejected for Release builds.

For a clean local checkout or CI job, expose the values as protected environment variables:

| Environment variable | Build setting written to the ignored file |
| --- | --- |
| `PIANOFLOW_RELEASE_GAD_APP_ID` | `GADApplicationIdentifier` |
| `PIANOFLOW_RELEASE_BANNER_AD_UNIT_ID` | `bannerViewAdUnitID` |
| `PIANOFLOW_RELEASE_APP_OPEN_AD_UNIT_ID` | `appOpenAdID` |

Run `Scripts/setup-release-config.sh` from any directory. It validates the values, creates `Piano/Config/Release.xcconfig` with owner-only permissions, and **refuses to overwrite** an existing file. CI should inject the three variables from its secret store immediately before running the setup script; do not put them in command arguments, committed files, or build logs. To change an existing local configuration, edit or replace it deliberately after keeping a private backup. The script accepts `PIANOFLOW_RELEASE_CONFIG_PATH` as an absolute path for an isolated checkout or setup test; normal builds use the path above.

The app target's **Validate Release ad IDs** phase runs on every Release build and checks Xcode's resolved build settings, including any command-line overrides. It fails for missing or unresolved values, malformed IDs, Google's sample publisher, or ad units from a different publisher. Diagnostics name the invalid setting without printing its value. Debug builds and the UI smoke suite are unaffected.

## Verify a distribution build

1. From a clean checkout with the ignored file supplied, create an **Apple-signed Release archive** using the `Piano` scheme and the team that owns its explicit App ID. Xcode may archive with development signing and then export/re-sign for App Store distribution within that same team. An unsigned device build checks compilation but is not an App Store distribution check.
2. Check the `.xcarchive` before export (the inspector reads the archive and does not modify it):

   ```sh
   Scripts/check-archive.sh /absolute/path/to/Piano.xcarchive
   ```

   The default requires an Apple-anchored code signature and an embedded, unexpired provisioning profile. A development-signed archive may pass because Xcode can export and re-sign it for distribution; the result states the detected profile type. When you expect the archive itself to use App Store signing, add `--require-app-store-signing` to require an App Store profile and disabled `get-task-allow`. `--allow-unsigned` is available only for structural diagnostics on an unsigned device archive; its output is explicitly **not a release pass**.

   The inspector compares the bundle ID, version, build, deployment target, device families, and primary icon metadata with the checked-in Release project, and requires the asset catalog. It checks the iOS device executable and app dSYM UUIDs; parses the app and embedded SDK privacy manifests; rejects `.xcconfig`, `.storekit`, test bundles, misplaced dSYMs, and symlink escapes inside Products; validates the built app's resolved AdMob settings without printing their values; and compares signing, team, entitlements, profile, and the profile's authorized signing certificates. App Store profiles must use this app's explicit App ID. Run `python3 Tests/ArchiveChecks.py` for isolated rejection fixtures. Fixture tests do not certify Apple signing.

3. Export the archive for App Store distribution in Xcode, upload it to TestFlight, and test the actual App Store Connect Premium product, free/premium ad behavior, and privacy options on devices. The local StoreKit fixture and its test price are separate from Sandbox and production. See [Premium setup](PremiumSetup.md) and [UI smoke tests](UISmokeTests.md) for their distinct checks. This local inspector does not replace Xcode export or App Store Connect processing.

The production IDs in an existing ignored `Release.xcconfig` are local machine configuration. Neither this setup nor the build validation changes that file automatically.

## Verified on 27 October 2026

- A clean source snapshot without the ignored local file failed with a clear missing-setting error from the Release validation phase.
- After provisioning the local file, the unsigned Release device build passed. Its bundle contained the app privacy manifest and no `.xcconfig` files; production ad settings resolved without appearing in the build log.
- Isolated script checks covered valid, missing, placeholder, unresolved, Google test, mismatched-publisher, and duplicate-unit settings. Setup created an owner-only file and refused to overwrite it.
- The default archive inspector passed the real signed PianoFlow 1.2 (7) archive at `/tmp/PianoFlow-Release-20261027/Piano-AppStore.xcarchive`. The archive used F694X76A5X development signing; checks passed for three privacy manifests, resolved production ad settings, matching app dSYM UUIDs, the Apple-anchored signature, and its embedded profile.
- Xcode App Store export succeeded at `/tmp/PianoFlow-Release-20261027/Export/Piano.ipa`. The exported app's Apple-anchored signature and team were verified, along with its F694X76A5X App Store profile for the explicit `com.appsbay.PianoFlow` App ID; `get-task-allow` was disabled. The archive and export stayed on the same developer team, without relying on cross-team re-signing.
- The 1.2 (7) upload to App Store Connect succeeded and processing completed. After the owner explicitly confirmed the export-compliance answer, it was saved and TestFlight showed **Ready to Submit**. Xcode warned that the archive lacks matching dSYMs for `GoogleMobileAds.framework` (UUID `5A6EC52E-3BA9-36B3-B91F-2FFE131BE3C4`) and `UserMessagingPlatform.framework` (UUID `2C6A0936-4EAA-35DD-849C-C95B93702DC5`). The app's own dSYM matches. The local Swift Package Manager artifacts for Google Mobile Ads 12.11.0 and User Messaging Platform 3.0.0 contain no vendor dSYMs; matching vendor symbols have not been located locally. Retain these warnings with the archive for crash-report investigation; they did not fail the upload.
- The signed archive, matching app dSYM, exported IPA, upload log, and screenshots are retained in the ignored `build/releases/PianoFlow-1.2-7-20261027/` directory.
- All 13 archive fixture tests passed. The strengthened signing checks also passed against the retained signed archive and the exported IPA, including signing-certificate membership in each profile and the explicit App Store App ID.
- The development-signed Release build 1.2 (7) installed and launched on the connected iPhone 16 Pro running iOS 26.7.1. The process remained alive during repeat checks; its actual landscape screenshot showed the complete toolbar, range controls, and keyboard without visible clipping, and the installed icon rendered correctly. This was a local Release install, not an installation through TestFlight. Physical audio, MIDI, AirPods, and real purchase/restore checks require hands-on feedback.
- The owner reported that active toolbar icons in build 1.2 (7) lost contrast. The toolbar styling was revised for build 1.2 (8), which still needs an on-device visual check.
- The signed 1.2 (8) Release archive passed the default archive inspector. Its App Store export passed explicit `F694X76A5X.com.appsbay.PianoFlow` App ID, authorized signing-certificate, app UUID, and dSYM checks. The archive, exported IPA, upload log, and active-toolbar simulator captures are retained in ignored `build/releases/PianoFlow-1.2-8-20261027/`. Build 1.2 (8) installed on the connected iPhone, but a launch attempt could not complete while the phone was locked; no build 8 UI or hardware behavior has been verified yet. The App Store Connect upload succeeded, and build 8 now has processing state VALID. It has not yet been added to the QA group.
- The build 8 upload repeated the two vendor dSYM warnings and reported **Potential Loss of Keychain Access** because the App ID prefix changed from `E6968P466E` to `F694X76A5X`. No first-party Keychain storage or entitlement was found in the repository's history. Saved recordings/imports use Application Support, settings/progress use UserDefaults, and Premium uses verified StoreKit transactions. Previous-prefix Keychain items, if any, would become inaccessible; historical third-party internals are not established by this source audit. An in-place App Store-version-to-TestFlight update with saved data and the privacy flow still needs device verification. See [Apple's prefix-change guidance](https://developer.apple.com/library/archive/qa/qa1726/_index.html).

## Verified on 28 October 2026

- A fresh signed PianoFlow 1.2 (9) Release archive passed the archive inspector. App Store export and verification of the exported IPA passed, and the upload to App Store Connect succeeded. All 13 isolated archive rejection fixtures passed. The archive, exported IPA, and build, export, and upload logs are retained in ignored `build/releases/PianoFlow-1.2-9-20261028/`.
- The build 9 upload repeated the known **Potential Loss of Keychain Access** warning for the `E6968P466E` to `F694X76A5X` App ID prefix change and the two missing vendor dSYM warnings for Google Mobile Ads and User Messaging Platform. These warnings did not prevent upload. The app's own dSYM and export signing checks passed; the retained logs preserve the exact warning details.
- App Store Connect review submission `d489d83c-73dc-47e1-8a49-b02f763e8663` contains the 1.2 build 9 app version and the first Premium non-consumable purchase together. The submission, app version, and Premium purchase are **Waiting for Review**. The app version uses manual release. A completed Premium App Review screenshot was uploaded from a simulator capture that makes no price claim. None of these states indicates approval or release.

Testing against the real Premium product and the remaining hands-on physical-device checks are separate release steps. See [physical-device results](PhysicalDeviceChecks.md) for observed passes and pending accessory checks. The owner delegated the production price choice; the US $4.99 price schedule and availability for all 175 currently offered countries and regions were saved in App Store Connect, with automatic inclusion of future countries off. The internal TestFlight group contains build 1.2 (7) and one invited tester; neither build 8 nor build 9 has been confirmed in that group. Invitation acceptance, Sandbox purchase and restore, and remaining hardware behavior remain unverified.

## Tracking rejection corrected and resubmitted on 29 October 2026

App Review rejected 1.2 (9) under Guideline 5.1.2(i) because its tracking disclosures were not matched by an ATT permission request. The 28 October review status above is a historical snapshot. Build 1.2 (10) adds regional UMP consent → Apple ATT → Google Mobile Ads sequencing, blocks unresolved permission, uses non-personalized treatment for denial/restriction, disables publisher first-party ID, and continues to skip ads for Premium users. Existing tracking privacy labels are retained. See [tracking privacy and saved review notes](TrackingPrivacy.md) for the flow, regional behavior, purpose text, and testing limits.

The full `bash Scripts/check-features.sh` suite and all 13 archive-inspector fixtures passed. The final signed 1.2 (10) device archive passed inspection, and its exported App Store IPA passed explicit App ID and distribution-signing checks. The build's only warning concerned unused App Intents metadata extraction.

The opt-in native ATT denial test passed 1/1 with zero failures in 88.6 seconds on a dedicated iPad 13 simulator running iOS 27.0. It used the actual app without `--uitesting` or a UMP bypass, with the production UMP application configuration and Google test ad units. It observed the native prompt, declined tracking, played the piano, saved a one-note recording, and relaunched without another prompt. The two native captures are retained in ignored `build/releases/PianoFlow-1.2-10-20261029/`. An iPhone 17 Pro Max native startup attempt stalled, so no passing result is claimed there. See [native test precautions](TrackingPrivacy.md#opt-in-native-permission-test) before enabling this otherwise skipped test on a disposable simulator; never bypass system permission through TCC changes.

The App Store upload succeeded, and processing completed as VALID for build `6f5c2ed6-7a5c-4b0d-a6a4-db4dfe577687`. Build 10 is selected for version 1.2; the previously owner-confirmed export-compliance answer and updated ATT review notes were saved and read back. The upload repeated the known App ID prefix-change warning and missing Google Mobile Ads/User Messaging Platform dSYM warnings described above. The app's own dSYM and exported distribution signing remain valid.

The rejected app item was resolved to Ready for Review, the existing Premium item was retained, and submission `d489d83c-73dc-47e1-8a49-b02f763e8663` was successfully resubmitted. API readback confirmed **Waiting for Review** for the submission, app version, and Premium parent product. The contained items remain Ready for Review while the submission waits. The app retains **manual release**; no approval or publication is claimed. The [29 October submission report](../StoreAssets/ReleaseSubmission-2026-10-29.json) records the current receipt. This followed [Apple's unresolved-submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues/).

Apple references: [privacy manifest placement and validity](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk), [code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), and [matching dSYM UUIDs](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file).

## GDPR/ATT order corrected and resubmitted on 1 November 2026

On 31 October 2026, App Review flagged 1.2 (10) under Guideline 5.1.1(iv): the ATT request appeared after the user tapped "Do not consent" on Google's GDPR form. Build 1.2 (11) skips ATT whenever the stored TCF choice declines tracking purposes. Personalization now requires both regional consent and ATT authorization. See [tracking privacy](TrackingPrivacy.md#build-11-correction) for the logic and the EEA simulator verification.

The full `bash Scripts/check-features.sh` suite and the archive fixtures passed. The signed archive passed inspection. The exported IPA is signed Apple Distribution for `F694X76A5X.com.appsbay.PianoFlow` with `get-task-allow` false. It contains the TCF check and none of the Debug-only EEA override. The upload, authenticated with the App Store Connect API key, succeeded. It repeated only the known Google Mobile Ads and User Messaging Platform dSYM warnings. Build `5ecc49d6-e060-46a0-a135-7c9a08327f85` processed as VALID.

Then:

- The previously confirmed export-compliance answer (no non-exempt encryption) was saved.
- Build 11 was attached to version 1.2.
- New review notes were saved and read back. They explain the GDPR-region variation and how to review both paths.
- The rejected app item was resolved. Submission `d489d83c-73dc-47e1-8a49-b02f763e8663` was resubmitted with the existing Premium item.

Readback shows **Waiting for Review** with manual release. The record is in [the 1 November submission report](../StoreAssets/ReleaseSubmission-2026-11-01.json); nothing is approved or released yet.
