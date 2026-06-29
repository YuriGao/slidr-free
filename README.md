# Slidr Free

English | [简体中文](README.zh-CN.md)

Slidr Free is an open-source macOS utility for physical trackpad edge gestures.

This project is independent and non-affiliated with any similarly named commercial products or vendors.

## Requirements

- macOS 13 or later
- Swift 5.9 or later

## Features

- **Left and right edge gestures** — Slide vertically along the physical trackpad left or right edge to adjust brightness and volume. By default, the left edge controls brightness and the right edge controls volume.
- **Side swapping option** — Swap the left and right edge actions from the settings panel.
- **Top-edge browser tab gesture** — Slide horizontally along the physical trackpad top edge to switch Safari, Google Chrome, and Microsoft Edge tabs, with haptic feedback for each switch.

## Experimental physical trackpad support

Physical trackpad edge gestures are experimental. Slidr Free reads physical touch frames through Apple's private `MultitouchSupport` framework because macOS does not provide a public API for per-finger physical trackpad coordinates.

- There is **no public API fallback** and no screen-edge cursor fallback. If `MultitouchSupport` is unavailable, blocked, or changes in a future macOS release, physical trackpad edge gestures are disabled instead of guessing from pointer position.
- Use the menu bar **Debug…** panel to inspect whether the physical trackpad monitor is running, the last physical touch frame, action results, and failure messages.
- Failure modes include missing or changed private symbols, unsupported hardware, permission or sandbox restrictions, no touch frames reported, and macOS updates that alter private API behavior. These failures should be reported in Debug and should not crash the app.

## Settings

The app provides separate toggles for volume edge gestures, brightness edge gestures, and top-edge browser tab switching. You can also swap the left and right edge actions and adjust the physical edge width.

## Permissions

Slidr Free requires the following permissions:

- **Accessibility** — Required to listen for global input events used by the trackpad edge gestures. macOS will prompt for this permission on first launch. Grant it in **System Settings → Privacy & Security → Accessibility**.

The app will display a permissions guide on first launch if this permission is missing.

## Installation

Slidr-Free is distributed as source code only. Build it locally:

```bash
git clone https://github.com/YuriGao/slidr-free.git
cd slidr-free
swift build -c release
bash scripts/package-release.sh
```

Then drag `release/Slidr-Free.app` to your Applications folder.

## Build, test, and package

```bash
# Build
swift build

# Run core checks
swift run SlidrFreeCoreChecks

# Create a release bundle
bash scripts/package-release.sh
```

The packaging script produces `release/Slidr-Free.app` containing a self-contained `.app` bundle with `LSUIElement=true` (no Dock icon or menu bar).

## Known limitations

- **Private MultitouchSupport API** — Physical trackpad edge gestures depend on an undocumented Apple framework and may stop working on some devices or macOS releases. Check **Debug…** for diagnostics.
- **Browser tab switching scope** — Top-edge tab switching only runs when Safari, Google Chrome, or Microsoft Edge is the frontmost app.

## Support

Slidr Free is open source and free to use. If it helps you, you can support the project via Alipay:

<img src="docs/assets/alipay-qr.jpg" alt="Alipay donation QR code" width="220">

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
