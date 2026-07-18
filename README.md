# Slidr Free

English | [简体中文](README.zh-CN.md)

Slidr Free is an open-source macOS menu bar utility for physical trackpad edge gestures and an optional configurable middle-click beta.

This project is independent and non-affiliated with any similarly named commercial products or vendors.

## Requirements

- macOS 13 or later
- Swift 5.9 or later

## Features

- **Left and right edge gestures** — Slide vertically along the physical trackpad left or right edge to adjust brightness and volume. By default, the left edge controls brightness and the right edge controls volume.
- **Direct edge assignments** — Choose Brightness, Volume, or None independently for each side; choose Browser Tabs or None for the top edge.
- **Independent trigger distances** — Configure the physical movement required per step separately for the left, right, and top edges; lower values are more sensitive.
- **Four-corner app shortcuts** — Bind a separate macOS app to each corner, then double-tap to open or activate it. While that app remains frontmost, later double taps toggle its focused window between minimized and restored.
- **Top-edge browser tab gesture** — Slide horizontally along the physical trackpad top edge to switch Safari, Google Chrome, and Microsoft Edge tabs, with haptic feedback for each switch.
- **Edge-origin gate** — Each contact must begin inside the configured edge width. Sliding into an edge from elsewhere is ignored until all touches lift.
- **Configurable middle click (beta)** — Use exactly 2, 3, or 4 fingers to produce a middle click by Tap or physical Click. The default is 4.
- **Guided setup and safe tests** — First run checks compatibility and permission, then verifies a gesture without dispatching a system action.
- **Unified health and diagnostics** — The menu bar and Overview share one actionable status; Diagnostics can preview a privacy-safe support summary before copying.

## Configurable middle-click beta

Middle click is **disabled by default**. Enable it from the menu bar item under **Settings… → Middle Click**, then select 2, 3, or 4 fingers. New and migrated settings default to exactly 4 fingers. Tap and physical Click share this selection; movement and duration thresholds remain fixed in this beta.

- **Tap** emits one middle-button Down/Up pair after a qualifying exact-count placement is released. The separate **Enable Tap** preference is on by default, but it only takes effect while the main middle-click feature is enabled.
- **Physical Click** converts the matching left- or right-button Down/Dragged/Up stream to a balanced middle-button stream while a fresh exact-count chord is active. Tap and physical Click are mutually exclusive for one touch session.
- Settings reports the bounded runtime state of the touch monitor and physical-Click Event Tap. A degraded state passes ordinary mouse input through rather than guessing.

Use 4 fingers when macOS **three-finger drag** is enabled. The 2-finger option may conflict with macOS secondary click and common two-finger gestures.

## Experimental physical trackpad support

Physical trackpad gestures use Apple's private `MultitouchSupport` framework because macOS does not provide a public API for per-finger physical trackpad coordinates.

- There is no public API or screen-edge cursor fallback. If the private framework is unavailable or changes, the touch pipeline is disabled and Settings shows its status.
- Slidr Free opens only the default physical touch device exposed by `MTDeviceCreateDefault`. It does not enumerate, classify, or route multiple devices, so the selected built-in or external trackpad source is not guaranteed.
- Physical Click conversion uses a global mouse Event Tap. macOS does not provide reliable source-device identity for those left/right mouse events. If another mouse is clicked while a qualifying middle-click chord is active, that event may be converted to a middle click.
- Private API behavior can change across hardware or macOS releases. Missing symbols, unavailable devices, permission loss, and absent touch frames should degrade without crashing the app.

## Settings and permissions

The menu bar **Settings…** window has Overview, Edge Gestures, Corner Shortcuts, Middle Click, and Diagnostics sections. New installs stay disabled until the setup assistant is completed; existing v0.3 edge behavior is migrated to direct assignments.

Corner shortcuts have their own configurable trigger ratio, movement limit, and double-tap interval, independent of Edge width. Movement tolerance defaults to 3% of the normalized trackpad span and can be adjusted from 1% to 10%. While a corner tap remains within that tolerance, edge output is deferred; exceeding it hands the accumulated movement to the edge gesture. The double-tap interval defaults to 0.75 seconds and can be adjusted from 0.30 to 1.20 seconds. Each tap must be a short one-finger tap and both taps must start in the same corner. Multi-touch, excessive movement, cross-corner taps, and timeouts do not perform a corner action. If the bound app is not frontmost, Slidr Free resolves it by bundle identifier first and uses the selected path only as a fallback. If that exact app is already frontmost, Slidr Free minimizes its focused window, or restores and raises it when it is already minimized.

Slidr Free requires **Accessibility** permission to listen to the global input stream used by physical gestures. Grant it in **System Settings → Privacy & Security → Accessibility**. After replacing or rebuilding the ad-hoc-signed app, macOS may retain a stale TCC entry; quit Slidr Free, remove and re-add the current app in Accessibility settings, then relaunch and refresh the status if needed.

## Build, test, and package

```bash
git clone https://github.com/YuriGao/slidr-free.git
cd slidr-free

swift run SlidrFreeCoreChecks
swift test
swift build
bash scripts/package-release.sh
```

Packaging produces `release/Slidr-Free.app` and `release/Slidr-Free.app.zip`, verifies version `0.4.0` / build `4000`, bundle identifier, license, archive contents, and an explicit ad-hoc signature. This repository does not currently publish a Developer ID-signed or Apple-notarized binary. The artifact is intended for local development and testing; users may need to approve macOS security prompts and re-add Accessibility permission after rebuilding. See [the lightweight v0.4 acceptance checklist](docs/qa/v0.4-release-acceptance.md).

## Known limitations

- Middle click supports exact 2–4-finger gestures on the default physical touch device only. Higher counts, “at least N” matching, multi-device routing, and per-application exclusions are not included.
- The global mouse-source limitation described above means an external mouse click can be converted while the chord is active.
- Top-edge tab switching only runs when Safari, Google Chrome, or Microsoft Edge is frontmost.
- Corner shortcuts accept local `.app` bundles only. They do not execute scripts, shell commands, or general automations; if an app is removed and cannot be resolved, or its frontmost window cannot be toggled, no fallback action runs.
- Automated tests do not require live Accessibility/TCC or physical hardware. Built-in and external trackpad checks on other Macs are welcome community validation, not a v0.4 release gate.

## Rollback

The known-good baseline is tag `v0.2.0` at commit `eb93e18e9ba225502bac580ae98e006c1bf1aec5`. Before replacing an installed v0.2.0 app, preserve its archive, record that archive's SHA-256, and back up the `SlidrFree.settings.v1` preference payload. To roll back, quit Slidr Free, restore the v0.2.0 bundle, reset Accessibility only if macOS no longer recognizes it, relaunch, and verify both the displayed version and every existing edge gesture.

## Provenance

The middle-click beta is a behavior-level reimplementation under explicit licensing controls. See [Middle-click implementation provenance](docs/middle-click-provenance.md) for the fixed references, permitted and prohibited inputs, dependency inventory, and review roles.

## Support

Slidr Free is open source and free to use. If it helps you, you can support the project via Alipay:

<img src="docs/assets/alipay-qr.jpg" alt="Alipay donation QR code" width="220">

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE). The release bundle includes the same license at `Contents/Resources/LICENSE`.
