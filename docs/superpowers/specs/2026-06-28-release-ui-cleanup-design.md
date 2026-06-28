# Release Source-Only, Settings Cleanup, and No-Cursor-Move Design

## Problem

After the media-key step gesture work, three cleanup issues remain:

1. The GitHub Release `v0.1.0` ships a prebuilt `Slidr-Free.app.zip` asset. The project should be source-only; GitHub already auto-generates source code archives for every release.
2. The settings window still exposes outdated continuous-control options (`Sensitivity`, `Normal step`, `Fine step`, `Fine control`, `Continuous window`, `Cursor freeze`, `Bottom quarter only`) that no longer match the discrete step-based gesture model and mislead users.
3. The menu bar dropdown includes a `Permissions…` item, but permissions are already surfaced in the settings window and Debug panel, so the menu entry is redundant.
4. The app defines a `freezeCursor` / `unfreezeCursor` path that warps the cursor (`CGWarpMouseCursorPosition`) and hides it, but it is never called. The user explicitly requires that triggering left/right edge gestures must not move the mouse. The dead cursor-freeze infrastructure should be removed to guarantee no cursor movement path exists.

## Goals

- Make the GitHub Release source-only by removing the binary zip asset and not uploading new zips going forward.
- Simplify the settings window to only the options that affect current behavior.
- Remove the `Permissions…` item from the menu bar dropdown.
- Guarantee edge gestures never move, warp, or hide the cursor by removing all cursor-freeze code.

## Non-Goals

- Do not change gesture recognition or media-key posting behavior.
- Do not remove the Debug panel or Debug menu item.
- Do not remove the permissions section from the settings window; it remains useful for first-run setup.
- Do not change login-item handling or permission checks.
- Do not add new features.

## Chosen Approach

### Release: Source-Only

- Delete the existing `Slidr-Free.app.zip` asset from the `v0.1.0` GitHub Release.
- Stop uploading binary assets in future releases. The release will rely on GitHub's auto-generated `Source code (zip)` and `Source code (tar.gz)`.
- No code change required for this; it is a release-asset and process change.
- README may keep build instructions so users can build from source.

### Settings Window Cleanup

Remove these toggles/sliders from `SettingsView.swift` and their localization keys:

| Removed setting | Reason |
|-----------------|--------|
| `sensitivity` | Step gestures use fixed `magnitude: 1.0`; sensitivity no longer multiplies per-frame output. |
| `normal_step` | Step model no longer uses continuous step scaling. |
| `fine_step` | Same; fine step is unused in step emission. |
| `fine_control` | Toggle has no effect on discrete media-key steps. |
| `continuous_window` | Unused in current recognizer. |
| `cursor_freeze` | Dead feature; removed entirely. |
| `bottom_quarter_only` | Edge gestures already require the physical trackpad edge; bottom-quarter filter is unnecessary complexity. |

Keep these settings:

- Enable app
- Launch at login
- Volume edge gesture toggle
- Brightness edge gesture toggle
- Swap sides toggle
- Edge width slider
- Middle click toggle
- Smart typing detection toggle
- Typing cooldown slider
- Permissions status section

### Menu Bar Dropdown Cleanup

Remove the `Permissions…` menu item from `MenuBarController.refresh()`. The remaining items are:

- Enable/Disable app
- separator
- Settings…
- Debug…
- separator
- Quit

### No Cursor Movement

Remove all cursor-freeze infrastructure:

- Remove `freezeCursor(at:)` and `unfreezeCursor()` from `SystemControlling` protocol and `SystemControl`.
- Remove `frozenPosition`, `CGWarpMouseCursorPosition`, `CGAssociateMouseAndMouseCursorPosition`, and `NSCursor.hide()/unhide()` calls from `SystemControl`.
- Remove `cursorFreeze` from `FeatureToggles`, defaults, validation, settings UI, localization, and core checks.

This guarantees no code path in the app warps or hides the cursor during edge gestures.

## Components

### `Sources/SlidrFreeApp/SettingsView.swift`
Remove the seven outdated controls. Keep the rest of the form intact.

### `Sources/SlidrFreeApp/MenuBarController.swift`
Remove the `Permissions…` menu item and its `openPermissions` action. Remove the `permissionManager` dependency from `MenuBarController` if no longer used.

### `Sources/SlidrFreeApp/SystemControl.swift`
Remove `freezeCursor`, `unfreezeCursor`, `frozenPosition`, and all CG cursor calls.

### `Sources/SlidrFreeCore/AppSettings.swift`
Remove `cursorFreeze` from `FeatureToggles`. Remove `sensitivity`, `normalStep`, `fineStep`, `continuousWindowSeconds` from `GestureSettings` if they are no longer referenced by active code. Keep backward-compatible decoding defaults for removed fields so existing saved settings still decode.

### `Sources/SlidrFreeCore/ActionDispatcher.swift`
Remove `fineControl` branch and `sensitivity`/`step` multiplication if the step model now uses a fixed delta of `1.0`. Each emitted action should use a fixed `magnitude`-independent delta so one media-key press is posted per step.

### `Sources/SlidrFreeCore/GestureRecognizer.swift`
Remove `bottomQuarterOnly` filtering logic.

### `Sources/SlidrFreeApp/AppDelegate.swift`
Remove `permissionManager` from `MenuBarController` initialization if no longer needed there.

### `Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings`
Remove localization keys for removed settings and the `permissions` menu item.

### `Sources/SlidrFreeCoreChecks/main.swift`
Update default-settings checks and validation checks to reflect removed fields. Update migration test to cover removed fields.

## Backward Compatibility

Existing saved `SlidrFree.settings.v1` files may contain the removed keys. The `Codable` decoder must ignore unknown keys gracefully. Swift's synthesized `Codable` ignores unknown keys by default, so removing fields from the struct is safe for decoding. For `cursorFreeze` and other removed `FeatureToggles`/`GestureSettings` fields, old values are simply ignored.

## Testing

- Update `SlidrFreeCoreChecks` to no longer assert removed defaults.
- Add a migration check that a settings JSON containing removed keys still decodes successfully.
- Verify `swift build`, `swift test`, and `swift run SlidrFreeCoreChecks` pass.
- Verify the release no longer has a binary asset after deletion.

## Acceptance Criteria

- GitHub Release `v0.1.0` has no `Slidr-Free.app.zip` asset; only auto-generated source archives remain.
- Settings window shows only the kept controls listed above.
- Menu bar dropdown has no `Permissions…` item.
- No `freezeCursor`, `unfreezeCursor`, `CGWarpMouseCursorPosition`, or `CGAssociateMouseAndMouseCursorPosition` references remain in the codebase.
- `swift build`, `swift test`, and `swift run SlidrFreeCoreChecks` pass.
- Existing saved settings with removed keys still decode without error.
