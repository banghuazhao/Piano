# PianoFlow store assets

Release 1.2, build 7. These are local, reviewable upload assets; no App Store Connect metadata or live listing has been changed.

## Upload map

Choose the `en-US` screenshots in filename order. Each card uses a real, uncropped app capture, a short headline, and one supporting sentence. Do not upload the `Sources` files as additional duplicate cards.

| Folder | App Store Connect placement | Output size |
| --- | --- | --- |
| `en-US/iPhone` | iPhone Dynamic Island, medium | 2622 × 1206 |
| `en-US/iPad-13` | iPad 13-inch | 2064 × 2752 |
| `en-US/iPhone-Duo-Outer` | iPhone Duo outer display | 2034 × 1398 |
| `en-US/iPhone-Duo-Inner` | iPhone Duo inner display | 2853 × 2007; portrait 2007 × 2853 |
| `en-US/Creatives/piano-header.png` | Product Page Information → Header and Search Results → Header | 3840 × 1646 |
| `en-US/Creatives/piano-search-results.png` | Product Page Information → Header and Search Results → Search Results | 3840 × 2560 |
| `en-US/Creatives/piano-universal.png` | Alternative: one universal image for both creative placements | 5244 × 2950 |

PNG exports are losslessly compressed, opaque RGB. Header and Search Results artwork has a central piano focal point, without embedded pricing, badges, awards, or text that needs localization. Preview the crops in App Store Connect before submitting. Use either the dedicated Header/Search Results pair or the universal alternative.

`Listing-en-US.json` contains proposed English listing copy. Review the name, subtitle, keywords, description, promotional text, and What's New before copying them into the next app version. Keep existing support and privacy URLs. No price or production purchase metadata is changed by these files.

## Regenerate

From the repository root on macOS:

```sh
swift Scripts/render-store-assets.swift StoreAssets/manifest.json
```

The manifest keeps the headline, source capture, native output size, and placement together. Recapture after any visible UI change, then rerun the renderer. Sources are native Simulator captures of the production interface; no UI was drawn or altered inside the captures.

For fresh captures, create dedicated simulators for iPhone 17, iPad Pro 13-inch, and iPhone Duo. Build the shared `Piano` scheme with Xcode 27.1. Use standard text size, dark appearance, a clean local library, and a consistent 9:41 status bar. Use Device Hub to select folded/expanded Duo state and orientation; use `simctl io <device> enumerate` to identify the active display before capture. The inner and outer screens have separate display IDs. Do not resize one device's screenshot to stand in for another.

Example lifecycle and capture commands (substitute your own simulator ID and app build):

```sh
xcrun simctl install <device-id> <path-to-Piano.app>
xcrun simctl launch <device-id> com.appsbay.PianoFlow
xcrun simctl status_bar <device-id> override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl io <device-id> screenshot --display=<active-display-id> <capture.png>
```

## Verification

- Release iOS device build and Debug simulator build, deployment target iOS 17.6.
- Five local StoreKit cases pass using `PianoStoreKit.xctestplan` on iOS 27.
- Feature checks include malformed MIDI, 40,000-note scores, recording recovery, keyboard geometry, and real WAV/M4A rendering.
- Duo outer/inner layouts, live folding during guided practice, settings navigation, and portrait music stand checked in the iOS 27.1 Simulator.
- Maximum Dynamic Type and increased contrast checked separately from the store captures.

Before public release, complete a signed archive and TestFlight checks against the actual App Store Connect product, including purchase-sheet cancellation and real USB/Bluetooth MIDI hardware. Simulator verification cannot establish hardware latency or rule out all crashes.

## Apple references

Sizes and placement requirements checked 26 October 2026:

- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
- [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
- [Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
