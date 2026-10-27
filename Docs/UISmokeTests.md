# UI smoke tests

The `PianoUITests` target uses XCTest UI automation to exercise the app through its visible controls. The dedicated `PianoUISmoke` scheme and test plan keep these tests separate from the `Piano` scheme's StoreKit tests.

## Run on a chosen simulator

Use a dedicated simulator and pass its UDID explicitly. The runner does not pick a booted device, boot or erase a simulator, or change any other simulator. Xcode may launch the destination you choose to execute the tests.

```sh
Scripts/check-ui-smoke.sh SIMULATOR_UDID all
Scripts/check-ui-smoke.sh SIMULATOR_UDID regular
Scripts/check-ui-smoke.sh SIMULATOR_UDID largest-ax
```

`all` runs the `Regular` and `Largest AX` configurations serially on the same destination. `Largest AX` forwards `PIANOFLOW_UI_TEST_LARGE_TEXT=1` from the test runner to the app, applying SwiftUI `.dynamicTypeSize(.accessibility5)` at the root and presented screen entry points. This tests the app's layout; it does not change the simulator's system Text Size. The dedicated toolbar/settings and Premium paywall cases always use AX5, including in the `Regular` configuration. Select an iPhone, iPad, or iPhone Duo simulator with a runtime supported by the app; iPhone Duo needs iOS 27.1 or later.

Each test launches with `--uitesting` and a unique session UUID, using separate preferences and temporary recording/song libraries. The relaunch test reuses that UUID to check saved data. Ads and purchase preparation are skipped for these explicit Debug simulator launches. Release builds and physical devices use the normal app environment.

The smoke suite skips before launching the app if selected with a Release build or a physical device, where those isolation hooks are unavailable.

By default, each run stores DerivedData, its `.xcresult` bundle, and `xcodebuild.log` under a new temporary directory outside the repository. Set `PIANOFLOW_UI_SMOKE_OUTPUT_DIR` to choose another external result directory. If needed, set `PIANOFLOW_SPM_PACKAGES_DIR` to a Swift package cache; otherwise Xcode resolves the project's package dependencies in its normal way.

## What this proves

The assertions in [PianoSmokeTests.swift](../PianoUITests/PianoSmokeTests.swift) check:

- A real two-note recording survives relaunch and replay enters its playing state.
- A keyboard tap advances a guided exercise.
- Stop all sound saves an active take, clears sustain and pressed-key state, and leaves the same key ready for another recording.
- Practice progress and playable keys survive landscape rotations on displays that follow interface orientation requests.
- Practice progress and playable keys survive portrait resizing on iPad. This case skips on standard iPhones, where the app supports landscape, and on the open iPhone Duo inner display.
- The toolbar remains reachable and the Key labels setting can be changed at AX5.
- Locked recording tools open the matching Premium offer, and free full-take M4A export renders a shareable audio file.
- The Premium paywall supports AX5 text and its Done control remains reachable.

The plan runs the general flows in both text configurations. Failure reports retain a screenshot and accessibility tree in the result bundle.

The runner disables Xcode's optional verbose simulator diagnostics collection, which can stall after the tests finish. The suite's screenshot and accessibility-tree attachments are still retained. Collect a separate system diagnostic when investigating a simulator or OS issue.

A passing run does not verify audible playback, audio latency or sound quality, physical Bluetooth MIDI, App Store purchases, ad serving, or every accessibility setting. Those require their own checks. For system Text Size coverage, select the size in Xcode Device Hub before testing and review native controls and system dialogs as well.

Xcode 27.1's public `XCUIDevice` API has no fold or posture control. The open iPhone Duo inner display keeps posture-defined bounds when tests request a physical orientation, so the two orientation/resize cases skip there; the other four flows still run. See Apple's [iPhone Duo preparation guidance](https://developer.apple.com/iphone-duo/prepare/). On iPhone Duo, manually fold, unfold, and rotate in Device Hub while checking piano keys, controls, score, and playback continuity. Review the outer display in supported orientations and the inner display in its available poses before release.

## Validation on 27 October 2026

The original six core flows were checked before adding the two Premium cases:

| Simulator | Configuration | Result |
| --- | --- | --- |
| iPhone 17, iOS 26.5 | Largest AX | 5 applicable cases passed; portrait case skipped |
| iPad Pro 13-inch (M5), iOS 27.0 | Largest AX | All 6 cases passed |
| iPhone Duo inner display, iOS 27.1 | Regular | 4 cases passed; 2 posture cases skipped |

The iPhone AX results combine the full run with focused reruns after correcting the scrolling helper. Feature checks also passed, including MIDI reset, failed-save retention, retry after storage recovery, free/Premium recording gates, and WAV/M4A export.

Both Premium cases additionally passed on iPhone 17 with iOS 26.5. The recording case checks that studio and WAV offers show their matching headline, WAV remains locked for a free user, and normal-speed Concert M4A export produces a shareable file. The AX5 paywall case checks horizontal text bounds, scrolls through all benefits and the bottom free-features disclosure, and retains full-screen and scroll-area screenshots for visual review. The app-only screenshot from XCTest can contain an incorrect landscape crop on this runtime; the full-screen capture and accessibility geometry were correct.

The final unsigned Release device build and feature checks passed. Real local StoreKit purchase, restore, pending, and refund behavior are covered separately by the serial StoreKit suite described in [PremiumSetup.md](PremiumSetup.md); production Sandbox/TestFlight checks remain part of release setup.
