# Physical-device release checks

## Verified on 27 October 2026

Device: iPhone 16 Pro running iOS 26.7.1. Build: PianoFlow 1.2 (7), installed directly from the local development-signed **Release** archive. This was not a TestFlight installation.

| Check | Result |
| --- | --- |
| Provisioning and install | The archive's development profile authorized this device; installation succeeded. PianoFlow was not installed beforehand, so no existing PianoFlow data was replaced. |
| Launch and stability | The app launched normally and its process remained running during repeat checks. This confirms the observed launch period only. |
| Landscape layout | A device screenshot showed the toolbar, range controls, and piano keyboard visible without apparent clipping. |
| Installed icon | The device returned the 1024 × 1024 PianoFlow icon, not a placeholder; it rendered correctly. |

Evidence is retained in the ignored release directory: [`iPhone16Pro-launch.png`](../build/releases/PianoFlow-1.2-7-20261027/iPhone16Pro-launch.png) and [`iPhone16Pro-installed-icon.png`](../build/releases/PianoFlow-1.2-7-20261027/iPhone16Pro-installed-icon.png).

## Build 8 toolbar follow-up

The owner reported that build 7's ON toolbar buttons filled with color and their icons became hard to see on this iPhone. Build 8 uses neutral glass, colored glyphs, thin active outlines, and a status dot on More. A focused iPhone 17 simulator test passed in Regular and Largest AX, and the active controls looked legible in both retained captures: [Regular](../build/releases/PianoFlow-1.2-8-20261027/Toolbar-active-regular.png) and [Largest AX](../build/releases/PianoFlow-1.2-8-20261027/Toolbar-active-largest-text.png).

The development-signed Release build 8 was installed on the physical iPhone. A launch attempt was blocked while the phone was locked, so the build 8 ON appearance has not yet been checked on the device. This does not establish a build 8 app launch failure.

## Pending hands-on checks

- **Build 8 active controls:** Unlock and launch the app, then turn on recording, sustain, and metronome. Confirm each icon remains visible against its button, the active outline/status dot appears, and the controls return to their idle appearance when turned off.
- **Touch and playback:** Hear individual white and black keys, two-finger chords, and a glissando; confirm notes release cleanly and no sound sticks. Record a short performance, stop and save it, replay it, and check it again after relaunch.
- **Physical MIDI:** Connect the available MIDI controller, play notes and chords, test its sustain pedal, then disconnect it while notes or sustain are active. Confirm input is detected and no notes remain stuck after release or disconnect.
- **AirPods and audio routes:** Play through the phone speaker and AirPods, switch routes while the app is active, and check that playback resumes at the selected output without stuck notes or an unexpected interruption. Judge audible latency and sound quality by listening.
- **Live Premium:** On the separate TestFlight build with an explicit App ID, confirm the App Store Connect product and localized price load, complete a Sandbox purchase, verify Premium unlocks and ad removal, relaunch, and test Restore Purchases. Do not make a real-money purchase for this check.

The local development-signed Release checks do not establish that live App Store Connect/Sandbox purchases work. A separate build 8 with an explicit App ID was uploaded to App Store Connect and its processing completed. It has not been confirmed available to the TestFlight group or installed through TestFlight on this phone; purchase and restore results remain unverified. The simulator UI suite intentionally skips physical devices and its isolated test data hooks do not run in Release, so it was not used on this phone.
