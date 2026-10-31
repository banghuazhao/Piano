# Tracking permission and advertising privacy

## Build 11 correction

App Review flagged PianoFlow 1.2 (10) on 31 October 2026 under Guideline 5.1.1(iv). The reviewer was on an iPad Air 11-inch (M3) in a GDPR region. They tapped "Do not consent" on Google's GDPR form, and the app then showed Apple's ATT request anyway. Declining GDPR consent still lets UMP allow non-personalized ads (`canRequestAds` stays true), so the gate went on to request ATT.

Build 11 reads the user's GDPR choice from the IAB TCF v2 values that UMP stores in `UserDefaults` (`IABTCF_gdprApplies`, `IABTCF_PurposeConsents`). When GDPR applies and purposes 1, 3, or 4 (store/access device information, create a personalized-ads profile, use that profile) are not all granted, `RegionalTrackingConsent.allowsTracking` returns false. Then:

- ATT is never requested, in that flow or in later sessions. iOS leaves the status undetermined, so the advertising identifier stays unavailable.
- The gate still resolves, so non-personalized ads can load. Personalization is `.default` only when the regional choice allows tracking **and** ATT is authorized (`AdConsentGate.mayTrack`). Otherwise it is `.disabled`, even if ATT was authorized earlier.
- If the user later grants consent through Settings › Privacy › Privacy choices, the next preparation may then show ATT. If they withdraw consent, tracking stops immediately.

Outside GDPR regions no TCF values are stored, and the flow is unchanged: ATT is shown once on first launch.

Verified on 1 November 2026 on a fresh iPad Air 11-inch (M3) simulator (iOS 27.0), Debug build, Google's sample app ID, and a forced EEA geography (`PIANOFLOW_UMP_DEBUG_EEA=1`, compiled only in Debug and absent from the Release binary):

- "Do not consent" stored `IABTCF_PurposeConsents = 00000000000`. No ATT request was made, either then or after a relaunch. Non-personalized ad requests still reached Google.
- On a fresh install, "Consent" was followed by Apple's ATT dialog.

Captures are in the ignored `build/releases/PianoFlow-1.2-11-20261101/`.

## Build 10 correction

App Review rejected PianoFlow 1.2 (9) on 29 October 2026 under Guideline 5.1.2(i): the privacy label disclosed tracking, but the app used only Google User Messaging Platform (UMP) consent and did not request Apple's App Tracking Transparency (ATT) permission. Build 10 adds the missing permission flow. Deterministic checks, native ATT denial testing on an iPad simulator, signed archive checks, and App Store IPA inspection passed. Build 10 was uploaded, processed as VALID, selected for version 1.2, and resubmitted with Premium. The submission, app version, and Premium purchase are **Waiting for Review**; manual release is retained. They are not approved or released. See the [29 October submission report](../StoreAssets/ReleaseSubmission-2026-10-29.json).

`AdConsentGate` serializes preparation on the main actor. `AdPrivacyManager` supplies the real UMP, ATT, activation, and Premium dependencies:

1. Wait until Premium entitlement is determined and the app is active. Premium users skip ad preparation and ATT.
2. Attempt a UMP consent-information update once per session, then finish any required regional form. A failed form blocks preparation and can be retried. If the update fails, only consent that UMP itself reports as valid permits further preparation. See [Google's UMP guidance](https://developers.google.com/admob/ios/privacy).
3. Read the regional choice and the system ATT status. If the user declined tracking purposes on a GDPR form, skip ATT entirely (build 11). Otherwise, if ATT is undetermined, request permission after the regional form returns. UMP may already have presented ATT through an IDFA message; an existing decision is never requested again. The app must be active. An interrupted request that remains undetermined keeps ads blocked until a later eligible preparation. See [Apple's ATT request API](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/requesttrackingauthorization(completionhandler:)).
4. Start Google Mobile Ads only after the gate resolves and UMP permits requests. With ATT denied or restricted, set `publisherPrivacyPersonalizationState = .disabled` for non-personalized treatment. With authorization, use `.default`, allowing regional restrictions to continue applying. Publisher first-party ID is disabled in both cases. See [Google's privacy strategies](https://developers.google.com/admob/ios/privacy/strategies) and [Publisher Privacy Treatment](https://developers.google.com/admob/ios/targeting).

The same local pipeline runs in every country and region. UMP decides which regional forms are required from the AdMob account's published messages and the user's context. The code does not bypass ATT by country. Actual regional message delivery depends on the production AdMob configuration and requires separate verification.

Permission and entitlement are rechecked during preparation and ad requests. Foreground activation refreshes permission before asynchronous entitlement work. A changed ATT status or regional privacy choice invalidates the ad generation, so older app-open loads cannot be reused; banner views are recreated. Premium suppresses requests and cached app-open ads. Declining tracking does not lock piano features or require a purchase.

## Purpose text and privacy declarations

`Piano/Info.plist` contains this `NSUserTrackingUsageDescription`:

> Your permission lets our advertising partner use device and ad activity data across other companies’ apps and websites to personalize ads and measure their effectiveness.

The existing App Store tracking disclosures for Coarse Location, Advertising Data, and Device ID are retained. This correction adds permission enforcement; it does not establish a “no tracking” app. Google's SDK disclosure describes potential collection of IP-derived location, identifiers, advertising interactions, diagnostics, and performance data. [Google's data disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure) and bundled SDK manifests must be considered alongside the app's behavior. Apple requires privacy answers to include integrated partners' practices; see [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).

## Saved App Review notes

For build 11, the opening section of the notes was replaced with a 5.1.1(iv) explanation. It covers the regional difference (GDPR form only in the EEA, UK, and Switzerland) and how to review both paths. The text is retained in `build/releases/PianoFlow-1.2-11-20261101/review-notes-build11.txt`. The build 10 text below is historical.

The following explanation was saved and read back in App Store Connect for build 10, followed by the existing Premium and feature-testing instructions:

> Guideline 5.1.2(i) fix in version 1.2 (10):
>
> On first launch for a free user, after the current StoreKit entitlement check and any required Google regional consent form, PianoFlow requests Apple's App Tracking Transparency permission. The system dialog appears over the piano before Google Mobile Ads initializes or any ad request is made. There is no custom permission explainer or sign-in requirement. This same pipeline applies in every storefront; Google may show an additional regional privacy form first.
>
> If tracking is declined or restricted, the piano and free recording/practice features remain usable. Ad requests use Google's non-personalized publisher privacy treatment; publisher first-party ID is disabled. An unresolved or interrupted ATT request blocks ads and is retried on a later active session. Verified Premium users skip ad initialization and this ad-permission flow.
>
> To see the system dialog, use a fresh installation with Allow Apps to Request to Track enabled in iOS Settings > Privacy & Security > Tracking. iOS does not repeat an already answered dialog and does not show it when permission is restricted or system tracking requests are disabled. The app respects those states. Existing App Privacy tracking disclosures are retained for consented advertising.

## Verification status

The full `bash Scripts/check-features.sh` suite passed, including `Tests/AdConsentChecks.swift` against the actual `AdConsentGate` source. The consent checks cover ordering, concurrent callers, inactive/Premium deferral, UMP update and form errors, cached-consent fallback, resolved ATT states, interrupted requests, live permission withdrawal, and Premium changes during suspension. They use injected dependencies without contacting Google or changing system permission. All 13 archive-inspector fixtures also passed.

The opt-in `testNativeTrackingPermissionCanBeDeclined` passed 1/1 with zero failures in 88.6 seconds on a dedicated iPad 13 simulator running iOS 27.0. It launched the actual app without `--uitesting`, used the production UMP application configuration with Google test ad units, and did not bypass UMP. Apple's native ATT prompt appeared. After selecting “Ask App Not to Track,” the test played a key, saved a one-note recording, and relaunched without a second prompt. Captures are retained in ignored `build/releases/PianoFlow-1.2-10-20261029/ATT-native-iPad.png` and `ATT-denied-recording-iPad.png`. An iPhone 17 Pro Max native startup attempt stalled; that device has no passing native ATT result.

The final signed 1.2 (10) device archive passed inspection. Its exported App Store IPA passed the explicit App ID and distribution-signing inspection. The build reported only the non-actionable App Intents metadata warning; no App Intents framework is used. Upload succeeded and App Store Connect processing completed as VALID for build `6f5c2ed6-7a5c-4b0d-a6a4-db4dfe577687`. The previously owner-confirmed export-compliance answer was saved, and the build and updated review notes were selected for version 1.2.

The upload repeated the known `E6968P466E` → `F694X76A5X` App ID prefix warning and missing Google Mobile Ads/User Messaging Platform dSYM warnings. The app's own dSYM and distribution signature passed inspection. These warnings did not prevent upload; see [release setup](ReleaseSetup.md) for their limits and pending in-place device-update verification.

The rejected app item was resolved to Ready for Review while the existing Premium item was preserved. Submission `d489d83c-73dc-47e1-8a49-b02f763e8663` was resubmitted successfully. API readback confirmed **Waiting for Review** for the submission, version 1.2, and the Premium parent product, with **manual** app release. The review item states remain Ready for Review inside that waiting submission. This is a submission receipt, not approval or release. Delivery of every production regional privacy message, hardware behavior, and live Sandbox purchase/restore remain separate checks.

## Opt-in native permission test

Normal smoke runs skip the native ATT test unless the test runner environment explicitly sets `PIANOFLOW_ATT_LIVE_TESTS=1`. The usual `--uitesting` flows remain isolated and skip advertising. Run only `PianoUITests/PianoSmokeTests/testNativeTrackingPermissionCanBeDeclined` on an explicitly prepared disposable simulator with no existing ATT decision. This test launches without the isolated-storage flag and saves an ordinary test recording, so do not run it against a personal device or a simulator containing wanted app data.

Use the app's production UMP application configuration and Google test ad units in the local Debug test build. Keep that override out of committed production configuration. Enable the simulator's normal “Allow Apps to Request to Track” setting as needed through Settings. Do not grant ATT through `simctl`, edit the TCC database, or replace the native request with a test-only permission answer; those approaches would invalidate prompt evidence. A regional UMP form may require additional interaction, and prior decisions or system restrictions can prevent the prompt, so confirm the prepared test environment before interpreting a failure.
