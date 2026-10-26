# PianoFlow Premium release setup

PianoFlow Premium is a **one-time, non-consumable** in-app purchase. The app grants it only from a verified StoreKit transaction. It removes ads and unlocks Warm Studio and Bright Hall sound profiles; Concert remains free.

## App Store Connect

1. In the `com.appsbay.PianoFlow` app, create a **Non-Consumable** in-app purchase with the exact product ID `com.appsbay.PianoFlow.premium` and reference name “PianoFlow Premium.” Product IDs cannot be reused after creation.
2. Set the production price, availability, display name, description, and required review screenshot in App Store Connect. Check each supported localization. The paywall reads the localized price from StoreKit; it has no hard-coded production price.
3. Verify the Paid Apps agreement, tax, and banking information are active. For the app's first in-app purchase, submit the product for review with the new app version. In App Review notes, state that Settings → PianoFlow Premium opens the paywall and that purchase removes ads and unlocks two sound profiles.
4. Test with Sandbox or TestFlight against the App Store Connect product before release. Confirm purchase, relaunch, restore on a fresh install, pending Ask to Buy, cancellation, and a refunded/revoked entitlement. Check that Premium users never see banners or app-open ads, and that free users are offered the privacy controls where required.

Apple setup: [create a non-consumable purchase](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases), [complete purchase metadata](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/view-and-edit-in-app-purchase-information), and [submit the first purchase with an app version](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

## Local StoreKit testing

`PianoFlow.storekit` is a **local test fixture**, referenced by the shared `Piano` scheme's Debug Run action. Its US `$9.99` price is test data and does not set the App Store price. The file is kept outside the app target's resources, so it is not shipped in release builds.

1. Open `Piano.xcodeproj`, choose the `Piano` scheme and a simulator, then Run. Confirm the scheme's Run → Options → StoreKit Configuration points to `PianoFlow.storekit`.
2. In Settings, open PianoFlow Premium. Check that the StoreKit price loads, buy Premium, and verify ads disappear and the two profiles unlock. Relaunch and verify the entitlement persists. Tap Restore Purchases to exercise the explicit sync flow.
3. In Xcode's StoreKit transaction manager, refund or delete the transaction and verify the app returns to Concert and free ad behavior. Use StoreKit Testing's Ask to Buy and interrupted-purchase options for pending and cancellation behavior.
4. Before Sandbox or TestFlight testing, set Run → Options → StoreKit Configuration to **None**. Local StoreKit transactions are separate from Sandbox and production transactions.

Automated StoreKit cases are implemented in the `PianoStoreKitTests` target. The shared `PianoStoreKit.xctestplan` activates the fixture before the app host launches; pass the test plan explicitly in command-line runs:

```sh
xcodebuild test -project Piano.xcodeproj -scheme Piano -testPlan PianoStoreKit \
  -destination 'platform=iOS Simulator,name=<iOS 27 simulator>' \
  -parallel-testing-enabled NO
```

The five cases cover purchase and refund, restore, Ask to Buy approval, transaction updates after an early entitlement refresh, and an injected purchase failure. StoreKit test sessions share one environment, so keep these tests serial. Also cancel the purchase sheet manually to exercise StoreKit's `.userCancelled` result. If an iOS 26.5 simulator reports `SKInternalErrorDomain Code=3` from `SKTestSession`, use a newer simulator runtime; [Apple acknowledged this StoreKit testing issue](https://developer.apple.com/forums/thread/826971). All five cases passed on an iOS 27 simulator with Xcode 27.1 on 26 October 2026.

Apple testing reference: [Set up StoreKit Testing in Xcode](https://developer.apple.com/documentation/Xcode/setting-up-storekit-testing-in-xcode).
