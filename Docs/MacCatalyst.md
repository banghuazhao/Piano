# Mac Catalyst support

PianoFlow runs on the Mac through **Mac Catalyst** on the existing `Piano` target. There is no
second target and no second App Store record: the Mac build keeps the `com.appsbay.PianoFlow`
bundle identifier, so App Store Connect treats it as the macOS platform of the same app and
Universal Purchase gives Mac users the Premium purchase they already own.

## What the Mac build shares

| | Shared with iOS |
| --- | --- |
| Bundle identifier | `com.appsbay.PianoFlow` (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`) |
| App Store record | The same app; macOS is an added platform, not a new app |
| Premium purchase | The same non-consumable `com.appsbay.PianoFlow.premium` |
| Sources | Every file in `Piano/`; `PremiumStore` is unchanged StoreKit 2 |
| Version and build | `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` |

`PremiumStore` needs no platform code. `Transaction.currentEntitlements` returns the purchase on
the Mac for the same Apple Account, and `AppStore.sync()` restores it. Premium unlocks the same
Warm Studio and Bright Hall sounds, advanced playback and trimming, and lossless WAV export.

## What differs on the Mac

- **No ads.** The Google Mobile Ads SDK publishes no Mac Catalyst slice, so the package is linked
  for iOS only (`platformFilters = (ios)` on its build file) and `AdManager.swift` is wrapped in
  `#if !targetEnvironment(macCatalyst)`. `AdManagerMac.swift` supplies no-op `AdPrivacyManager`,
  `OpenAd`, and `BannerView` stand-ins so the shared SwiftUI call sites stay unconditional.
- **No ad identifiers or tracking keys.** `INFOPLIST_FILE[sdk=macosx*]` points at
  `Piano/Info-MacCatalyst.plist`, which carries only the Bluetooth MIDI usage description. The
  Mac bundle contains no `GADApplicationIdentifier`, no ad unit IDs, no `SKAdNetworkItems`, and no
  `NSUserTrackingUsageDescription`. `Scripts/check-release-config.sh` exits early when
  `IS_MACCATALYST` is `YES`, so a Release Mac build needs no AdMob configuration.
- **No ad-free benefit in the paywall.** `PremiumFeature.purchasable` drops `.adFree` on Mac
  Catalyst, and `PremiumFeature.unlockedSummary` matches. There is no GDPR privacy-options row,
  because `AdPrivacyManager.privacyOptionsRequired` is always `false`.
- **App Sandbox.** `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` points at `Piano/PianoMac.entitlements`:
  sandbox on, user-selected file read/write for MIDI import and export, and Bluetooth for MIDI
  keyboards. The iOS build keeps its default entitlements, unchanged.
- **Mac app icon.** The asset catalog gained a `mac` idiom set rendered from the iOS artwork into
  the macOS rounded tile. Regenerate it with `Scripts/render-mac-app-icon.swift` after any icon
  change and commit the PNGs.
- **Window.** `pianoMacWindowSizing()` sets a 960×600 minimum so the toolbar, range controls, and
  keyboard stay usable. macOS remembers whatever larger size the player chooses.
- **Product name.** `PRODUCT_NAME[sdk=macosx*] = PianoFlow`, so the Mac app is `PianoFlow.app` and
  its menu bar reads PianoFlow. The iOS product stays `Piano.app` with the `PianoFlow` display name.
- **Deployment target.** macOS 14.6, derived from the iOS 17.6 deployment target.

## Build and run

```sh
xcodebuild -project Piano.xcodeproj -scheme Piano -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build
```

In Xcode, pick the `Piano` scheme and the **My Mac (Mac Catalyst)** destination. The
`PianoStoreKitTests` and `PianoUITests` targets are iOS only; run them on a simulator as before.

## App Store Connect

The macOS platform is **staged but not submitted**. Done on 1 November 2026, recorded in
[AppStoreConnect-mac-sync-2026-11-01.json](../StoreAssets/AppStoreConnect-mac-sync-2026-11-01.json):

- The macOS platform already existed on the app record as an empty auto-created **1.0** version
  with no copy, no screenshots, and no build. Its version string was changed to **1.2** so it
  matches the binary's `MARKETING_VERSION`.
- Build **1.2 (12)** was uploaded with `xcrun altool` and reached processing state VALID, and is
  attached to the macOS version.
- The English listing from [Listing-mac-en-US.json](../StoreAssets/Listing-mac-en-US.json) was
  saved: description, promotional text, and keywords. `whatsNew` is rejected for the first version
  on a platform, so it stays in the JSON for the first macOS update.
- Two `APP_DESKTOP` screenshots from `StoreAssets/en-US/Mac` were uploaded and both reached
  asset delivery state COMPLETE at 2880 × 1800.
- The App Review notes were replaced. The auto-created version had inherited the iOS ATT notes,
  which do not apply to a build that links no ad SDK and never requests tracking. The iOS 1.2
  review detail is a separate record and was not touched.
- The release type was changed from the inherited `AFTER_APPROVAL` to **`MANUAL`**, so the Mac
  app waits for an explicit release after approval, as iOS 1.2 does.

One thing is deliberately left for the owner: **export compliance** on build 12 is unanswered
(`usesNonExemptEncryption` is null). It is a legal declaration and is not made on the owner's
behalf. Submission is blocked until it is answered.

Premium needs nothing: `com.appsbay.PianoFlow.premium` belongs to the app record and Universal
Purchase delivers it to the Mac. No macOS-specific product exists or is needed.

iOS version 1.2 build 11 is a separate platform version and was not touched; it remains Waiting
for Review.

`Scripts/check-archive.sh` inspects **iOS** archives: it expects an iOS device executable, iOS
device families, and resolved AdMob settings. It does not apply to a Mac Catalyst archive.

## Verified on 1 November 2026

- The Mac Catalyst Debug build succeeded and the app launched on macOS 27.0 (Darwin 27.0.0). The
  window showed the complete toolbar, range controls, and keyboard; the menu bar read PianoFlow.
- The built Mac bundle had bundle ID `com.appsbay.PianoFlow`, `LSMinimumSystemVersion` 14.6,
  `LSApplicationCategoryType` `public.app-category.music`, and `UIDeviceFamily` `[2]`.
- The Mac binary linked StoreKit, CoreMIDI, and AVFAudio, and linked neither GoogleMobileAds nor
  UserMessagingPlatform. No framework was embedded.
- Signed entitlements were app-sandbox, user-selected read/write, and Bluetooth.
- The Mac `Info.plist` contained no AdMob, SKAdNetwork, or tracking keys. The compiled asset
  catalog carried the full Mac icon set from 16×16 through 512×512@2x.
- The iOS simulator build still embedded GoogleMobileAds and UserMessagingPlatform, kept all 50
  SKAdNetwork entries, and kept the same bundle identifier.
- `Scripts/check-features.sh` passed, and the iOS Release ad-ID validation still passed against
  the local production configuration.
- The iOS UI smoke plan (Regular) on iPhone 17 Pro, iOS 26.5, ran 10 cases with 2 skipped and one
  failure: `testLargestTextToolbarAndSettingsRemainUsable` could not scroll `settings.scroll` to
  `settings.keyLabels`. The same test fails identically on unmodified `main` on that simulator, so
  it is pre-existing and not caused by the Mac Catalyst work. The validated simulators in
  [UI smoke tests](UISmokeTests.md) are iPhone 17 and iPad Pro 13-inch, not iPhone 17 Pro.
- The premium copy was checked on the running Mac build: the settings panel reads "More piano
  sounds and studio tools" with no ad claim, and the paywall lists exactly three benefits — the two
  piano sounds, the advanced recording studio, and lossless WAV export — with no ad-free row.
- StoreKit on the Mac resolved the real `com.appsbay.PianoFlow.premium` product and showed its
  localized price. That is evidence the Mac build reaches the shared product; it is not a completed
  purchase and does not establish Universal Purchase entitlement delivery.
- A signed Mac Catalyst **Release archive** of 1.2 (12) succeeded (team F694X76A5X, Apple
  Development signing, no embedded frameworks, sandbox entitlements, no ad or tracking keys).
- The App Store **export** succeeded: `PianoFlow.pkg`, a universal x86_64 + arm64 build signed with
  an Apple Distribution certificate under the `Mac Catalyst Team Store Provisioning Profile:
  com.appsbay.PianoFlow`, explicit App ID `F694X76A5X.com.appsbay.PianoFlow`, `get-task-allow`
  false, symbols included, installer signed by `3rd Party Mac Developer Installer: APPS BAY
  LIMITED`. The archive, package, and logs are retained in ignored
  `build/releases/PianoFlow-1.2-12-mac-20261101/`.
- Two macOS store cards were rendered at 2880 × 1800, opaque RGB, losslessly compressed, from
  authentic Mac Catalyst window captures. The already-uploaded iOS and creative cards were left
  byte-for-byte unchanged.
- The upload succeeded (delivery UUID `d44e607e-3730-45dc-b86a-2aa0c5637056`, 11,532,271 bytes)
  and App Store Connect reported build 12 as VALID.

Not verified: any real or Sandbox purchase on the Mac, Universal Purchase entitlement delivery
to a Mac, App Review's response, MIDI hardware, and audio output. The macOS version has not
been submitted and cannot be until export compliance is answered.
