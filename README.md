# Slidr Free

English | [简体中文](README.zh-CN.md)

Slidr Free is an open-source macOS menu bar utility for physical trackpad edge gestures and an optional three-finger middle-click beta.

This project is independent and non-affiliated with any similarly named commercial products or vendors.

## Requirements

- macOS 13 or later
- Swift 5.9 or later

## Features

- **Left and right edge gestures** — Slide vertically along the physical trackpad left or right edge to adjust brightness and volume. By default, the left edge controls brightness and the right edge controls volume.
- **Side swapping option** — Swap the left and right edge actions in Settings.
- **Top-edge browser tab gesture** — Slide horizontally along the physical trackpad top edge to switch Safari, Google Chrome, and Microsoft Edge tabs, with haptic feedback for each switch.
- **Three-finger middle click (beta)** — Use exactly three fingers to produce a middle click by Tap or physical Click.

## Three-finger middle-click beta

Middle click is **disabled by default**. Enable it from the menu bar item under **Settings… → Middle Click**. The gesture is fixed to exactly three fingers; finger count and movement/duration thresholds are not configurable in this beta.

- **Tap** emits one middle-button Down/Up pair after a qualifying three-finger placement is released. The separate **Enable three-finger Tap** preference is on by default, but it only takes effect while the main middle-click feature is enabled.
- **Physical Click** converts the matching left- or right-button Down/Dragged/Up stream to a balanced middle-button stream while a fresh three-finger chord is active. Tap and physical Click are mutually exclusive for one touch session.
- Settings reports the bounded runtime state of the touch monitor and physical-Click Event Tap. A degraded state passes ordinary mouse input through rather than guessing.

If macOS **three-finger drag** or **Look up & data detectors** uses the same gesture, disable or change that macOS gesture in Trackpad settings to avoid conflicts.

## Experimental physical trackpad support

Physical trackpad gestures use Apple's private `MultitouchSupport` framework because macOS does not provide a public API for per-finger physical trackpad coordinates.

- There is no public API or screen-edge cursor fallback. If the private framework is unavailable or changes, the touch pipeline is disabled and Settings shows its status.
- Slidr Free opens only the default physical touch device exposed by `MTDeviceCreateDefault`. It does not enumerate, classify, or route multiple devices, so the selected built-in or external trackpad source is not guaranteed.
- Physical Click conversion uses a global mouse Event Tap. macOS does not provide reliable source-device identity for those left/right mouse events. If another mouse is clicked while a qualifying three-finger chord is active, that event may be converted to a middle click.
- Private API behavior can change across hardware or macOS releases. Missing symbols, unavailable devices, permission loss, and absent touch frames should degrade without crashing the app.

## Settings and permissions

The menu bar **Settings…** window provides controls for edge gestures, middle click, launch at login, and runtime status.

Slidr Free requires **Accessibility** permission to listen to the global input stream used by physical gestures. Grant it in **System Settings → Privacy & Security → Accessibility**. After replacing or rebuilding the ad-hoc-signed app, macOS may retain a stale TCC entry; quit Slidr Free, remove and re-add the current app in Accessibility settings, then relaunch and refresh the status if needed.

## Build, test, and package

```bash
git clone https://github.com/YuriGao/slidr-free.git
cd slidr-free

swift run SlidrFreeCoreChecks
swift test
swift build
bash scripts/package-release.sh
bash scripts/verify-release.sh
```

Packaging produces `release/Slidr-Free.app` and `release/Slidr-Free.app.zip`. The verifier checks the bundle identifier, version `0.3.0` / build `3001`, bundled MIT license, archive license, and ad-hoc signature. The app uses `LSUIElement=true`, so it has no Dock icon and is controlled through its menu bar item. Ad-hoc signing is not Developer ID signing or notarization.

## Known limitations

- Middle click supports exactly three fingers on the default physical touch device only. Configurable finger counts, multi-device routing, and per-application exclusions are not included.
- The global mouse-source limitation described above means an external mouse click can be converted while the chord is active.
- Top-edge tab switching only runs when Safari, Google Chrome, or Microsoft Edge is frontmost.
- Automated tests do not require live Accessibility/TCC or physical hardware. Hardware behavior still needs the manual beta matrix described in the approved design.

## Rollback

The known-good baseline is tag `v0.2.0` at commit `eb93e18e9ba225502bac580ae98e006c1bf1aec5`. Before replacing an installed v0.2.0 app, preserve its archive, record that archive's SHA-256, and back up the `SlidrFree.settings.v1` preference payload. To roll back, quit Slidr Free, restore the v0.2.0 bundle, reset Accessibility only if macOS no longer recognizes it, relaunch, and verify both the displayed version and every existing edge gesture. Before a public release, rehearse the full v0.3 → v0.2 → v0.3 settings-compatibility path.

## Provenance

The middle-click beta is a behavior-level reimplementation under explicit licensing controls. See [Middle-click implementation provenance](docs/middle-click-provenance.md) for the fixed references, permitted and prohibited inputs, dependency inventory, and review roles.

## Support

Slidr Free is open source and free to use. If it helps you, you can support the project via Alipay:

<img src="docs/assets/alipay-qr.jpg" alt="Alipay donation QR code" width="220">

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE). The release bundle includes the same license at `Contents/Resources/LICENSE`.
