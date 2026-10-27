# PianoFlow Premium release setup

PianoFlow Premium is a **one-time, non-consumable** in-app purchase. The app grants it only from a verified StoreKit transaction.

| Feature | Free | Premium |
| --- | --- | --- |
| Concert Grand, 88 keys, sustain, metronome, MIDI input | Yes | Yes |
| Guided practice, Rhythm coach, sheet music, MIDI song import | Yes | Yes |
| Record, save, rename, replay, and share MIDI | Yes | Yes |
| Full-take Concert M4A audio export at normal speed | Yes | Yes |
| Ad-free playing | — | Yes |
| Warm Studio and Bright Hall sounds | — | Yes |
| Custom playback speed, looping, and selected sections | — | Yes |
| Save a trimmed copy | — | Yes |
| Lossless WAV audio export | — | Yes |

Locked controls open a contextual upgrade screen. A verified purchase or restore unlocks requested sounds/formats without starting playback or exporting automatically. Refunds reset paid selections and stop playback; previously saved performances remain available. Advanced operations also check access in `PerformanceStudio`: advanced playback rechecks access at each loop cycle, and protected exports refresh verified entitlements before rendering and recheck access before returning the file.

## App Store Connect

1. In the `com.appsbay.PianoFlow` app, create a **Non-Consumable** in-app purchase with the exact product ID `com.appsbay.PianoFlow.premium` and reference name “PianoFlow Premium.” Product IDs cannot be reused after creation.
2. Set the production price, availability, display name, description, and required review screenshot in App Store Connect. Check each supported localization. The paywall reads the localized price from StoreKit; it has no hard-coded production price.
3. Verify the Paid Apps agreement, tax, and banking information are active. For the app's first in-app purchase, submit the product for review with the new app version. Copy the display text and feature walkthrough from [Premium-IAP-en-US.json](../StoreAssets/Premium-IAP-en-US.json); this is a metadata draft, not an uploaded or activated product. Include a current review screenshot showing the Premium screen.
4. Test with Sandbox or TestFlight against the App Store Connect product before release. Confirm purchase, relaunch, restore on a fresh install, pending Ask to Buy, cancellation, and a refunded/revoked entitlement. Check that Premium users never see banners or app-open ads, and that free users are offered the privacy controls where required.

Apple setup: [create a non-consumable purchase](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases), [complete purchase metadata](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/view-and-edit-in-app-purchase-information), and [submit the first purchase with an app version](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

## Local StoreKit testing

`PianoFlow.storekit` is a **local test fixture**, referenced by the shared `Piano` scheme's Debug Run action. Its US `$9.99` price is test data and does not set the App Store price. The file is kept outside the app target's resources, so it is not shipped in release builds.

1. Open `Piano.xcodeproj`, choose the `Piano` scheme and a simulator, then Run. Confirm the scheme's Run → Options → StoreKit Configuration points to `PianoFlow.storekit`.
2. In Settings, open PianoFlow Premium. Check that the StoreKit price loads, buy Premium, and verify ads disappear, both sounds unlock, and recording Tools enables speed/loop/section controls, trimmed copies, and WAV export. Relaunch and verify the entitlement persists. Tap Restore Purchases to exercise the explicit sync flow.
3. In Xcode's StoreKit transaction manager, refund or delete the transaction and verify the app returns to Concert, normal-speed full replay, M4A export, and free ad behavior. Existing saved takes must remain available. Use StoreKit Testing's Ask to Buy and interrupted-purchase options for pending and cancellation behavior.
4. Before Sandbox or TestFlight testing, set Run → Options → StoreKit Configuration to **None**. Local StoreKit transactions are separate from Sandbox and production transactions.

Automated StoreKit cases are implemented in the `PianoStoreKitTests` target. The shared `PianoStoreKit.xctestplan` activates the fixture before the app host launches; pass the test plan explicitly in command-line runs. The plan also sets `PIANOFLOW_STOREKIT_TESTS=1`: in Debug simulator builds, this defers the optional app-initializer transaction listener until normal preparation so the test session can attach its catalog first. Release builds start observing at launch. `prepare()` waits for listener startup even when an earlier entitlement refresh has already completed.

```sh
xcodebuild test -project Piano.xcodeproj -scheme Piano -testPlan PianoStoreKit \
  -destination 'platform=iOS Simulator,name=<iOS 27 simulator>' \
  -parallel-testing-enabled NO
```

The seven cases cover purchase and refund, restore, Ask to Buy approval, automatic transaction updates after an early entitlement refresh, an injected purchase failure, concurrent product loading/purchase protection, and verified purchases/refunds unlocking/relocking advanced recording tools. StoreKit test sessions share one environment, so keep these tests serial. Also cancel the purchase sheet manually to exercise StoreKit's `.userCancelled` result. If an iOS 26.5 simulator reports `SKInternalErrorDomain Code=3` from `SKTestSession`, use a newer simulator runtime; [Apple acknowledged this StoreKit testing issue](https://developer.apple.com/forums/thread/826971). All seven cases passed on an iPad Pro simulator running iOS 27.0 with Xcode 27.1 on 27 October 2026.

Apple testing reference: [Set up StoreKit Testing in Xcode](https://developer.apple.com/documentation/Xcode/setting-up-storekit-testing-in-xcode).
