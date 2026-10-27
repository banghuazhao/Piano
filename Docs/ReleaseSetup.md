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

1. From a clean checkout with the ignored file supplied, create a **signed Release archive** using the `Piano` scheme and your distribution signing setup. An unsigned device build checks compilation but is not an App Store distribution check.
2. Inspect the archive's `Piano.app`: it should contain `PrivacyInfo.xcprivacy` and should contain **no** `.xcconfig` files. The `Piano` filesystem-synchronized target explicitly excludes all four files in `Piano/Config` from app resources.
3. Upload the signed archive to TestFlight and test the actual App Store Connect Premium product, free/premium ad behavior, and privacy options on devices. The local StoreKit fixture and its test price are separate from Sandbox and production. See [Premium setup](PremiumSetup.md) and [UI smoke tests](UISmokeTests.md) for their distinct checks.

The production IDs in an existing ignored `Release.xcconfig` are local machine configuration. Neither this setup nor the build validation changes that file automatically.

## Verified on 27 October 2026

- A clean source snapshot without the ignored local file failed with a clear missing-setting error from the Release validation phase.
- After provisioning the local file, the unsigned Release device build passed. Its bundle contained the app privacy manifest and no `.xcconfig` files; production ad settings resolved without appearing in the build log.
- Isolated script checks covered valid, missing, placeholder, unresolved, Google test, mismatched-publisher, and duplicate-unit settings. Setup created an owner-only file and refused to overwrite it.

A signed archive and testing against the real App Store Connect product are still separate release checks.
