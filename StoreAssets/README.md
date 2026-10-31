# PianoFlow store assets

Release 1.2 store assets, refreshed on 28 October 2026. All nine screenshot cards and both dedicated creative images are uploaded, processed, placed, and verified in their intended order. [The upload snapshot](AppStoreConnect-sync-2026-10-28.json) records their IDs, checksums, dimensions, and states before submission. **Version 1.2 build 10 and PianoFlow Premium are Waiting for Review after the 29 October ATT correction.** [The current submission receipt](ReleaseSubmission-2026-10-29.json) records the resubmission; [the 28 October receipt](ReleaseSubmission-2026-10-28.json) is historical. Release remains manual; the live listing has not changed.

## Upload map

The target set has **nine screenshot cards**: two medium iPhone, one large iPhone marketing card, one iPad, and five iPhone Duo cards (three inner, two outer). It also has two dedicated creative images for Header and Search Results; the universal creative is an unused alternative. Choose the `en-US` screenshots in filename order. Each card frames an authentic app capture with a short headline and supporting sentence. Do not upload the `Sources` files as additional duplicate cards.

| Folder | App Store Connect placement | Output size |
| --- | --- | --- |
| `en-US/iPhone` | iPhone Dynamic Island, medium; two cards | 2622 × 1206 |
| `en-US/iPhone-Large` | iPhone Dynamic Island, large; one marketing card framed from an iPhone 17 capture | 2868 × 1320 |
| `en-US/iPad-13` | iPad 13-inch | 2064 × 2752 |
| `en-US/iPhone-Duo-Outer` | iPhone Duo outer display; two cards | 2034 × 1398 |
| `en-US/iPhone-Duo-Inner` | iPhone Duo inner display; three cards | 2853 × 2007; portrait 2007 × 2853 |
| `en-US/Creatives/piano-header.png` | Product Page Information → Header and Search Results → Header | 3840 × 1646 |
| `en-US/Creatives/piano-search-results.png` | Product Page Information → Header and Search Results → Search Results | 3840 × 2560 |
| `en-US/Creatives/piano-universal.png` | Unused alternative: one universal image for both creative placements | 5244 × 2950 |

PNG exports are losslessly compressed, opaque RGB. Header and Search Results artwork has a central piano focal point, without embedded pricing, badges, awards, or text that needs localization. Preview the crops in App Store Connect before submitting. Use either the dedicated Header/Search Results pair or the universal alternative.

`Listing-en-US.json` records the English listing copy saved to the new 1.2 version. The existing support, marketing, and privacy pages were verified and their HTTPS URLs saved. These assets do not set the Premium price or change the in-app purchase record.

`Sources/premium-review.png` is the separate IAP review screenshot of the actual Premium benefits screen on iPad Simulator. It is not a public marketing card and contains no production-price or completed-purchase claim. The focused capture test passed; live Sandbox purchase/restore and hardware checks remain separate.

## Regenerate

From the repository root on macOS:

```sh
swift Scripts/render-store-assets.swift StoreAssets/manifest.json
```

To refresh only the contact sheet while preserving the compressed upload files, run `swift Scripts/render-store-assets.swift --preview-only StoreAssets/manifest.json`.

The manifest keeps the headline, source capture, output canvas size, and placement together. Recapture after a visible UI change, then rerun the renderer. The iPhone instrument source is a native iPhone 17 build 8 capture in the idle state. The iPhone recording source is a verified build 8 UI-test capture with active recording; its EXIF orientation was normalized losslessly. The five Duo sources and one iPad source are native build 7 captures of screens whose relevant UI did not change in build 8; they were retained after CoreSimulator became unavailable. The source captures do not contain drawn replacement UI.

The `iPhone-Large` output is a **2868 × 1320 marketing canvas** framing the genuine iPhone 17 instrument capture. It is not a native iPhone 17 Pro Max capture and should not be described as one. The medium iPhone, iPad, and Duo sources are native to their stated devices and displays.

For fresh captures, create dedicated simulators for iPhone 17, iPad Pro 13-inch, and iPhone Duo. Build the shared `Piano` scheme with Xcode 27.1. Use standard text size, dark appearance, a clean local library, and a consistent 9:41 status bar. Use Device Hub to select folded/expanded Duo state and orientation; use `simctl io <device> enumerate` to identify the active display before capture. The inner and outer screens have separate display IDs. Do not resize one device's screenshot to stand in for another native device capture. A marketing card may frame an authentic app capture at the required canvas size without claiming it came from different hardware.

Example lifecycle and capture commands (substitute your own simulator ID and app build):

```sh
xcrun simctl install <device-id> <path-to-Piano.app>
xcrun simctl launch <device-id> com.appsbay.PianoFlow
xcrun simctl status_bar <device-id> override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl io <device-id> screenshot --display=<active-display-id> <capture.png>
```

## Verification

- Apple accepted all 11 asset specifications. The saved placement order was read back through the App Asset Library API: medium iPhone 2, large iPhone 1, iPad 1, Duo 5, Header 1, Search Results 1. Older inherited placements were removed only from the 1.2 draft; their approved library images remain available.
- Header and Search Results were reviewed in Apple's device previews on iPhone and iPad. Header framing was also reviewed on Duo outer and inner displays. Preview captures are retained in ignored `build/releases/PianoFlow-1.2-StoreListing-20261028/`. Preview placeholders for icons and ratings do not establish a problem with the binary; no build is selected on this draft yet.
- Every uploaded PNG is opaque RGB and losslessly compressed; pixel equality was checked during compression. A stalled, unplaced Duo upload was preserved and retried with a fresh reservation. Its replacement processed successfully.

- Release iOS device build and Debug simulator build, deployment target iOS 17.6.
- Seven local StoreKit cases pass using `PianoStoreKit.xctestplan` on iOS 27.
- Feature checks include malformed MIDI, 40,000-note scores, recording recovery, keyboard geometry, and real WAV/M4A rendering.
- Duo outer/inner layouts, live folding during guided practice, settings navigation, and portrait music stand checked in the iOS 27.1 Simulator.
- Maximum Dynamic Type and increased contrast checked separately from the store captures.

The signed build 8 archive and App Store export passed the release checks; the upload succeeded. Before public release, complete TestFlight checks against the actual App Store Connect product, including purchase-sheet cancellation, and test real USB/Bluetooth MIDI hardware. Simulator verification cannot establish hardware latency or rule out all crashes.

## Apple references

Sizes and placement requirements checked 28 October 2026:

- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
- [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
- [Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
