# AGENTS.md

Slidr Free is an open-source macOS menu bar utility (LSUIElement accessory app, no Dock icon) for physical trackpad gestures: left/right edge slides adjust brightness/volume, top edge slides switch browser tabs, corner double-taps launch/toggle bound apps, and an optional middle-click beta uses exactly 2, 3, or 4 fingers. Swift Package Manager project, macOS 13+, Swift 5.9+, **no external package dependencies**.

## Layout

- `Sources/SlidrFreeCore/` — pure logic library: `AppSettings` (JSON-codable model + `validated()` clamping + legacy migration), `GestureRecognizer`, `MiddleClickRecognizer`, `CornerDoubleTapRecognizer`, `ActionDispatcher`. Must stay free of AppKit and private API.
- `Sources/SlidrFreeApp/` — AppKit/SwiftUI executable: `PhysicalTrackpadMonitor` (private `MultitouchSupport` bridge), `MouseButtonEventTap`, `InputPipelineStatus` (coordinator/lifecycle), `SystemControl` (volume/brightness/tab/app actions), `SettingsView`, `MenuBarController`, `AppDelegate`.
- `Sources/SlidrFreeCoreChecks/` — standalone executable smoke checks (fast, no XCTest harness).
- `Tests/SlidrFreeCoreTests/`, `Tests/SlidrFreeAppTests/` — XCTest suites (`@testable import`, plus plain `import SlidrFreeCore`).
- `Resources/en.lproj/Localizable.strings`, `Resources/zh-Hans.lproj/Localizable.strings` — UI strings; both languages required.
- `scripts/` — `package-release.sh`, `verify-release.sh`, `test-verify-release-signature.sh`, `generate-menubar-icon.py`.
- `docs/` — `middle-click-provenance.md` (licensing boundary, read before touching middle-click), `qa/v0.4-release-acceptance.md`, `superpowers/specs/` and `plans/` (per-feature design history).

## Commands

```bash
swift run SlidrFreeCoreChecks   # fast core behavior checks (run before swift test)
swift test                      # full XCTest suite
swift build                     # debug build
bash scripts/package-release.sh # release build + app bundle + ad-hoc sign + zip into gitignored release/
bash scripts/verify-release.sh  # verifies bundle id, version, license, ad-hoc signature
bash scripts/test-verify-release-signature.sh
```

CI (`.github/workflows/ci.yml`) runs all of the above on macOS. There is no SwiftLint/SwiftFormat config; match surrounding style. When manually launching the app for testing, quit it afterward and confirm with `pgrep -fl SlidrFreeApp` (acceptance rule: no lingering menu bar instances).

## Architecture rules

- Data flow: `PhysicalTrackpadMonitor` → `NormalizedInputEvent` → core `GestureRecognizer` → `RecognizedGesture` → core `ActionDispatcher` → `SystemAction` → `SystemControl` (AppKit side). Keep recognizers pure and deterministic (inject timestamps/touches; no clocks or UI).
- Touch coordinates are normalized 0–1: left edge ≈ x 0, right edge ≈ x 1, top edge ≈ y 1.
- All private `MultitouchSupport` API surface is confined to `Sources/SlidrFreeApp/PhysicalTrackpadMonitor.swift` — never import or reference it elsewhere.
- The app must fail closed and degrade gracefully: missing private symbols, unavailable device, lost Accessibility permission, or absent touch frames must never crash or emit guessed actions.
- Settings persist as JSON under the `SlidrFree.settings.v1` UserDefaults key. Always route new settings through `AppSettings.validated()` (clamps ranges) and provide decode-time defaults/migration: legacy v0.2/v0.3 payloads and missing fields must decode, not throw. Add a migration test when you touch the model.
- Localized strings use `NSLocalizedString` with snake_case keys; add every new key to **both** `en.lproj` and `zh-Hans.lproj` (CI lints both).

## Hard constraints and gotchas

- `docs/middle-click-provenance.md` documents a GPL-3.0 (MiddleClick) provenance boundary: do not copy, translate, or adapt upstream MiddleClick source/resources; it is a behavior-level reimplementation only. Read it before changing middle-click code.
- Release version `0.4.0` / build `4000` is duplicated in `scripts/package-release.sh` and `scripts/verify-release.sh` (defaults, overridable via `APP_VERSION`/`BUILD_NUMBER`). Keep them in sync; bundles must stay ad-hoc signed (`com.slidr.free`), never Developer ID, for this repo's flow.
- Ad-hoc rebuilds invalidate macOS Accessibility (TCC) grants; expect stale-permission reports and document the remove/re-add recovery when relevant (see README).
- Tests must not require live Accessibility/TCC permissions or physical hardware — keep it that way so CI stays green.
- `README.md` and `README.zh-CN.md` are kept in sync; update both when user-facing behavior changes. `AGENTS.md` is the only agent instruction file; `docs/superpowers/` is historical design material, not current guidance.
- `--show-settings` command-line argument opens the settings window on launch (handy for manual UI testing).
