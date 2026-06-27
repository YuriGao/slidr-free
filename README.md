# Slidr Free

English | [简体中文](README.zh-CN.md)

Slidr Free is an open-source macOS utility for edge gestures, middle click, fine control, smart typing detection, and cursor freeze workflows.

This project is independent and non-affiliated with any similarly named commercial products or vendors.

## Requirements

- macOS 13 or later
- Swift 5.9 or later

## Features

- **Volume edge gesture** — Slide at screen edge to adjust volume.
- **Brightness edge gesture** — Slide at screen edge to adjust brightness.
- **Middle click** — Trigger middle click via gesture or keyboard shortcut.
- **Fine control** — Hold a modifier key for slower, more precise adjustments.
- **Side swapping option** — Swap left and right edge gesture zones.
- **Bottom-quarter-only option** — Restrict edge gesture activation to the bottom quarter of the screen edges.
- **Smart typing detection** — Automatically suppress gestures while typing to avoid interference.
- **Cursor freeze** — Hold a modifier key to freeze the cursor during gesture input.

## Toggles

All features can be enabled or disabled individually from the menu bar settings panel.

## Permissions

Slidr Free requires the following permissions:

- **Accessibility** — Required to listen for global input events (edge gestures, middle click, cursor freeze). macOS will prompt for this permission on first launch. Grant it in **System Settings → Privacy & Security → Accessibility**.
- **Input Monitoring** — Required on macOS 14+ to capture keyboard and mouse events. Grant it in **System Settings → Privacy & Security → Input Monitoring**.

The app will display a permissions guide on first launch if either permission is missing.

## Unsigned build warning

Development builds are unsigned. macOS may require you to explicitly allow the app in **Privacy & Security** settings before running it. To open an unsigned build, right-click the app and select **Open**, then confirm in the dialog.

## Build, test, and package

```bash
# Build
swift build

# Run core checks
swift run SlidrFreeCoreChecks

# Create a release bundle
bash scripts/package-release.sh
```

The packaging script produces `release/Slidr-Free.app.zip` containing a self-contained `.app` bundle with `LSUIElement=true` (no Dock icon or menu bar).

## Roadmap

- [ ] External display brightness control
- [ ] Per-application gesture profiles
- [ ] Custom gesture zones and actions
- [ ] Preferences window with advanced options

## Known limitations

- **External display brightness** — v0.1.0 controls brightness on the built-in display only. External display brightness support is planned for a future release.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
