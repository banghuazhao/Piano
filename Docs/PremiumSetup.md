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

The Mac Catalyst build is part of the same app record and the same purchase. Universal Purchase delivers `com.appsbay.PianoFlow.premium` to the Mac for an Apple Account that already owns it, so no second product is created. The Mac build shows no ads, so its paywall omits the ad-free row and lists only the sounds, recording tools, and lossless export. See [Mac Catalyst support](MacCatalyst.md).

Locked controls open a contextual upgrade screen. A verified purchase or restore unlocks requested sounds/formats without starting playback or exporting automatically. Refunds reset paid selections and stop playback; previously saved performances remain available. Advanced operations also check access in `PerformanceStudio`: advanced playback rechecks access at each loop cycle, and protected exports refresh verified entitlements before rendering and recheck access before returning the file.

## App Store Connect

The real **PianoFlow Premium** non-consumable record was created on 27 October 2026: [Apple ID 6827458121](https://appstoreconnect.apple.com/apps/6752531110/distribution/iaps/6827458121). Its English (U.S.) display name, description, and review notes are saved. The **US $4.99 one-time** price schedule is saved with the United States as the base territory and Apple's automatic regional equivalents. With the owner's authorization, availability was saved for all **175 currently offered countries and regions**; automatic inclusion of future countries is off. App Store Connect showed the Paid Apps agreement, tax forms, and banking status as active.

On 28 October 2026, an actual Premium-screen simulator capture at [premium-review.png](../StoreAssets/Sources/premium-review.png), with no price claim, was uploaded as the IAP App Review screenshot and reached completed asset state (`5dc24909-f41a-486b-9c1c-ed708e6dfe9c`). Premium version `69b1afd4-6dbf-4e5b-8c12-b69ad3359cb1` and PianoFlow 1.2 build 9 were submitted together in review submission `d489d83c-73dc-47e1-8a49-b02f763e8663`. After App Review rejected build 9 for its missing ATT permission request on 29 October, the app item was corrected with build **1.2 (10)** and resubmitted in the same submission with Premium retained. Both the app version and IAP are now **Waiting for Review**, confirmed by the [29 October receipt](../StoreAssets/ReleaseSubmission-2026-10-29.json). The app version is set to manual release. Submission does not mean App Review approval or a verified live purchase.

The owner delegated the price decision. The $4.99 base matches [Piano Keyboard Pro's permanent upgrade](https://apps.apple.com/us/app/piano-keyboard-pro-practice/id6818850223), sits above [We Play Piano's $2.99 ad removal](https://apps.apple.com/us/app/we-play-piano-piano-keyboard/id1625018611), and below [Perfect Piano's $5.99 lifetime VIP](https://apps.apple.com/us/app/perfect-piano-learn-to-play/id942937409), using the US App Store prices checked on 27 October 2026. These comparisons guide positioning; they do not establish expected conversion or revenue.

1. Keep the existing product in the `com.appsbay.PianoFlow` app with the exact product ID `com.appsbay.PianoFlow.premium` and reference name “PianoFlow Premium.” Product IDs cannot be reused after creation.
2. Before release, recheck the saved production price, current-storefront availability, display name, description, and completed review screenshot in App Store Connect. The paywall reads the localized price from StoreKit; it has no hard-coded production price.
3. Verify the Paid Apps agreement, tax, and banking information remain active. The first IAP and new app version are in the same review submission. [Premium-IAP-en-US.json](../StoreAssets/Premium-IAP-en-US.json) tracks the product ID, saved English text, price, availability, and feature walkthrough; it does not set App Store Connect values.
4. Test with Sandbox or TestFlight against the App Store Connect product before release. Confirm purchase, relaunch, restore on a fresh install, pending Ask to Buy, cancellation, and a refunded/revoked entitlement. Check that Premium users never see banners or app-open ads, and that free users are offered the privacy controls where required.

Apple setup: [create a non-consumable purchase](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases), [complete purchase metadata](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/view-and-edit-in-app-purchase-information), and [submit the first purchase with an app version](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

## Live product testing on a device

The internal [PianoFlow Release QA group](https://appstoreconnect.apple.com/teams/947c7ee7-4c99-4b7a-96b7-227a9bf35ed5/apps/6752531110/testflight/groups/3976af58-6c1e-4383-b2c2-d9b595df2cce) contains build 1.2 (7), marked Ready to Test. Automatic distribution is off. The owner authorized an invitation to their existing App Store Connect account; it was sent, and App Store Connect lists one tester as **Invited**. Build 1.2 (8) was uploaded and processed; build 1.2 (9) was uploaded and later rejected for its missing ATT prompt. Corrected build 1.2 (10) is Waiting for Review with Premium. Builds 8, 9, and 10 have not been confirmed in the QA group. Invitation acceptance, TestFlight installation, and live Sandbox purchase and restore have not been verified.

Use the TestFlight build to test the real SKU after the invitation is accepted. TestFlight purchases use Sandbox and do not incur real charges. The local Release copy is suitable for hardware checks, but its wildcard development provisioning profile cannot test Sandbox purchases. Apple requires an explicit App ID for live Sandbox IAP. The exported TestFlight package has the explicit `F694X76A5X.com.appsbay.PianoFlow` App ID and its authorized distribution certificate.

For Xcode device debugging, use an explicit development profile for the owning F694X76A5X team and disable the scheme's local StoreKit configuration. The normal `Piano` Run action uses Debug, the E6968P466E development team, and the local fixture; it does not validate the real App Store Connect product. Verify the installed app's embedded profile before claiming a live purchase pass.

Apple references: [Sandbox product availability and explicit App IDs](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox), [IAP and entitlements](https://developer.apple.com/library/archive/technotes/tn2415/), and [TestFlight purchase testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/).

## Local StoreKit testing

`PianoFlow.storekit` is a **local test fixture**, referenced by the shared `Piano` scheme's Debug Run action. Its US `$9.99` price is test data and does not set the App Store price. The file is kept outside the app target's resources, so it is not shipped in release builds.

1. Open `Piano.xcodeproj`, choose the `Piano` scheme and a simulator, then Run. Confirm the scheme's Run → Options → StoreKit Configuration points to `PianoFlow.storekit`.
2. In Settings, open PianoFlow Premium. Check that the StoreKit price loads, buy Premium, and verify ads disappear, both sounds unlock, and recording Tools enables speed/loop/section controls, trimmed copies, and WAV export. Relaunch and verify the entitlement persists. Tap Restore Purchases to exercise the explicit sync flow.
3. In Xcode's StoreKit transaction manager, refund or delete the transaction and verify the app returns to Concert, normal-speed full replay, M4A export, and free ad behavior. Existing saved takes must remain available. Use StoreKit Testing's Ask to Buy and interrupted-purchase options for pending and cancellation behavior.
4. For live Sandbox testing through Xcode, set Run → Options → StoreKit Configuration to **None** and use the owning team's explicit development profile. TestFlight uses the uploaded App Store package. Local StoreKit transactions are separate from Sandbox and production transactions.

Automated StoreKit cases are implemented in the `PianoStoreKitTests` target. The shared `PianoStoreKit.xctestplan` activates the fixture before the app host launches; pass the test plan explicitly in command-line runs. The plan also sets `PIANOFLOW_STOREKIT_TESTS=1`: in Debug simulator builds, this defers the optional app-initializer transaction listener until normal preparation so the test session can attach its catalog first. Release builds start observing at launch. `prepare()` waits for listener startup even when an earlier entitlement refresh has already completed.

```sh
xcodebuild test -project Piano.xcodeproj -scheme Piano -testPlan PianoStoreKit \
  -destination 'platform=iOS Simulator,name=<iOS 27 simulator>' \
  -parallel-testing-enabled NO
```

The seven cases cover purchase and refund, restore, Ask to Buy approval, automatic transaction updates after an early entitlement refresh, an injected purchase failure, concurrent product loading/purchase protection, and verified purchases/refunds unlocking/relocking advanced recording tools. StoreKit test sessions share one environment, so keep these tests serial. Also cancel the purchase sheet manually to exercise StoreKit's `.userCancelled` result. If an iOS 26.5 simulator reports `SKInternalErrorDomain Code=3` from `SKTestSession`, use a newer simulator runtime; [Apple acknowledged this StoreKit testing issue](https://developer.apple.com/forums/thread/826971). All seven cases passed on an iPad Pro simulator running iOS 27.0 with Xcode 27.1 on 27 October 2026.

Apple testing reference: [Set up StoreKit Testing in Xcode](https://developer.apple.com/documentation/Xcode/setting-up-storekit-testing-in-xcode).
