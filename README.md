# Slidr Free

English | [简体中文](README.zh-CN.md)

Slidr Free is an open-source macOS utility for edge gestures, middle click, fine control, smart typing detection, and cursor freeze workflows.

This project is independent and non-affiliated with any similarly named commercial products or vendors.

## Requirements

- macOS 13 or later
- Swift 5.9 or later

## Features

- **Physical trackpad volume edge gesture** — Slide along the physical trackpad edge to adjust volume.
- **Physical trackpad brightness edge gesture** — Slide along the physical trackpad edge to adjust brightness.
- **Middle click** — Trigger middle click via gesture or keyboard shortcut.
- **Side swapping option** — Swap left and right edge gesture zones.
- **Smart typing detection** — Automatically suppress gestures while typing to avoid interference.

## Experimental physical trackpad support

Physical trackpad edge gestures are experimental. Slidr Free reads physical touch frames through Apple's private `MultitouchSupport` framework because macOS does not provide a public API for per-finger physical trackpad coordinates.

- There is **no public API fallback** and no screen-edge cursor fallback. If `MultitouchSupport` is unavailable, blocked, or changes in a future macOS release, physical trackpad edge gestures are disabled instead of guessing from pointer position.
- Use the menu bar **Debug…** panel to inspect whether the physical trackpad monitor is running, the last physical touch frame, action results, and failure messages.
- Failure modes include missing or changed private symbols, unsupported hardware, permission or sandbox restrictions, no touch frames reported, and macOS updates that alter private API behavior. These failures should be reported in Debug and should not crash the app.

## Toggles

All features can be enabled or disabled individually from the menu bar settings panel. The edge gesture settings are specifically for physical trackpad edge gestures and include an experimental/private API warning.

## Permissions

Slidr Free requires the following permissions:

- **Accessibility** — Required to listen for global input events (edge gestures, middle click, cursor freeze). macOS will prompt for this permission on first launch. Grant it in **System Settings → Privacy & Security → Accessibility**.
- **Input Monitoring** — Required on macOS 14+ to capture keyboard and mouse events. Grant it in **System Settings → Privacy & Security → Input Monitoring**.

The app will display a permissions guide on first launch if either permission is missing.

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

## Roadmap

- [ ] External display brightness control
- [ ] Per-application gesture profiles
- [ ] Custom gesture zones and actions
- [ ] Preferences window with advanced options

## Known limitations

- **External display brightness** — v0.1.0 controls brightness on the built-in display only. External display brightness support is planned for a future release.
- **Private MultitouchSupport API** — Physical trackpad edge gestures depend on an undocumented Apple framework and may stop working on some devices or macOS releases. Check **Debug…** for diagnostics.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
