# Simplify Release, Settings, and Cursor Behavior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the prebuilt zip from GitHub Release, clean stale settings/menu items, and eliminate all cursor-moving code so edge gestures never touch the mouse.

**Architecture:** Remove dead cursor-freeze infrastructure from SystemControl, strip stale fields from AppSettings and update all dependents (ActionDispatcher, GestureRecognizer, checks), simplify SettingsView and MenuBarController UI, clean localized strings, update README, and delete the release binary asset.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit/SwiftUI, XCTest, SlidrFreeCoreChecks, gh CLI.

## Global Constraints

- macOS target remains macOS 13 or newer.
- Do not change gesture recognition step logic, media-key posting, or physical trackpad monitor behavior.
- Do not add new features.
- GitHub Release v0.1.0 must end with no binary assets — source code only.
- No code path may call CGWarpMouseCursorPosition, CGAssociateMouseAndMouseCursorPosition, NSCursor.hide(), or NSCursor.unhide() after this plan.
- Each emitted gesture step maps to exactly one media-key press (delta +1.0 or -1.0).
- Existing saved settings files must not crash on decode after field removal (Codable ignores unknown keys).

---

## File Structure

- Modify `Sources/SlidrFreeApp/SystemControl.swift`: remove freezeCursor, unfreezeCursor, frozenPosition, cursor CG calls.
- Modify `Sources/SlidrFreeCore/AppSettings.swift`: remove cursorFreeze, fineControl, bottomQuarterOnly, sensitivity, normalStep, fineStep, continuousWindowSeconds; update defaults, validation, decode.
- Modify `Sources/SlidrFreeCore/ActionDispatcher.swift`: simplify signedDelta to fixed step.
- Modify `Sources/SlidrFreeCore/GestureRecognizer.swift`: remove bottomQuarterOnly filtering.
- Modify `Sources/SlidrFreeCoreChecks/main.swift`: update all stale assertions and tests.
- Modify `Sources/SlidrFreeApp/SettingsView.swift`: remove stale controls.
- Modify `Sources/SlidrFreeApp/MenuBarController.swift`: remove Permissions item and permissionManager.
- Modify `Sources/SlidrFreeApp/AppDelegate.swift`: update MenuBarController init call.
- Modify `Resources/en.lproj/Localizable.strings`: remove stale keys.
- Modify `Resources/zh-Hans.lproj/Localizable.strings`: remove stale keys.
- Modify `README.md` and `README.zh-CN.md`: update install instructions.

---

### Task 1: Remove Cursor-Freeze Code

**Files:**
- Modify: `Sources/SlidrFreeApp/SystemControl.swift`
- Modify: `Sources/SlidrFreeCore/AppSettings.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Consumes: existing `SystemControlling` protocol, `FeatureToggles.cursorFreeze`.
- Produces: `SystemControlling` without `freezeCursor`/`unfreezeCursor`; `FeatureToggles` without `cursorFreeze`.

- [ ] **Step 1: Update checks to remove cursorFreeze assertions**

In `Sources/SlidrFreeCoreChecks/main.swift`:

1. Delete line 73:
```swift
    try check(settings.features.cursorFreeze, "Cursor freeze should be enabled by default")
```

2. In `testSettingsDecodeMigratesMissingPhysicalStepFields`, delete the `"cursorFreeze": true` line (line 109) from the legacy JSON features block.

- [ ] **Step 2: Run checks to verify RED**

Run:
```bash
swift run SlidrFreeCoreChecks
```
Expected: compile failure because `FeatureToggles.cursorFreeze` still exists but test references removed — actually this will still compile. The real RED is after Step 3 removes the field. Skip to Step 3.

- [ ] **Step 3: Remove cursorFreeze from AppSettings**

In `Sources/SlidrFreeCore/AppSettings.swift`:

1. Delete `public var cursorFreeze: Bool` from `FeatureToggles` (line 11).
2. Delete `cursorFreeze: true` from the `FeatureToggles(...)` default init (line 85).

- [ ] **Step 4: Remove freezeCursor/unfreezeCursor from SystemControl**

In `Sources/SlidrFreeApp/SystemControl.swift`:

1. Delete these two lines from `SystemControlling` protocol:
```swift
    func freezeCursor(at point: CGPoint)
    func unfreezeCursor()
```

2. Delete `private var frozenPosition: CGPoint?` from `SystemControl` class (line 33).

3. Delete the entire `freezeCursor(at:)` method (lines 86-93):
```swift
    func freezeCursor(at point: CGPoint) {
        frozenPosition = point
        CGAssociateMouseAndMouseCursorPosition(Int32(0))
        CGWarpMouseCursorPosition(point)
        DispatchQueue.main.async {
            NSCursor.hide()
        }
    }
```

4. Delete the entire `unfreezeCursor()` method (lines 95-101):
```swift
    func unfreezeCursor() {
        CGAssociateMouseAndMouseCursorPosition(Int32(1))
        DispatchQueue.main.async {
            NSCursor.unhide()
        }
        frozenPosition = nil
    }
```

- [ ] **Step 5: Run checks and tests to verify GREEN**

Run:
```bash
swift run SlidrFreeCoreChecks && swift test && swift build
```
Expected: all pass, no compile errors.

- [ ] **Step 6: Verify no cursor code remains**

Run:
```bash
rg 'freezeCursor|unfreezeCursor|cursorFreeze|CGWarpMouseCursorPosition|CGAssociateMouseAndMouseCursorPosition|NSCursor\.hide|NSCursor\.unhide' Sources/
```
Expected: no matches in Sources/.

- [ ] **Step 7: Commit Task 1**

```bash
git add Sources/SlidrFreeApp/SystemControl.swift Sources/SlidrFreeCore/AppSettings.swift Sources/SlidrFreeCoreChecks/main.swift
git commit -m "refactor: remove cursor freeze code"
```

---

### Task 2: Remove Stale Gesture and Feature Fields

**Files:**
- Modify: `Sources/SlidrFreeCore/AppSettings.swift`
- Modify: `Sources/SlidrFreeCore/ActionDispatcher.swift`
- Modify: `Sources/SlidrFreeCore/GestureRecognizer.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Consumes: existing `GestureSettings` and `FeatureToggles` with stale fields.
- Produces: `GestureSettings` with only `edgeWidthPercent`, `typingCooldownSeconds`, `physicalStepDistance`, `physicalStepIntervalSeconds`; `FeatureToggles` with only `volumeEdgeGesture`, `brightnessEdgeGesture`, `middleClick`, `swapSides`, `smartTypingDetection`; `ActionDispatcher.signedDelta` returns `sign * magnitude`.

- [ ] **Step 1: Update checks to expect new defaults and simplified dispatch**

In `Sources/SlidrFreeCoreChecks/main.swift`:

1. In `testDefaultSettingsEnableAllFirstVersionFeaturesIndividually()`, delete these lines:
```swift
    try check(settings.features.fineControl, "Fine control should be enabled by default")
    try check(!settings.features.bottomQuarterOnly, "Bottom quarter only should be disabled by default")
```

2. In `testValidationClampsGestureSettings()`, delete these lines:
```swift
    settings.gesture.sensitivity = -2.0
```
and:
```swift
    try checkEqual(validated.gesture.sensitivity, 0.10, accuracy: 0.0001, "Sensitivity should clamp")
```

3. In `testSettingsDecodeMigratesMissingPhysicalStepFields()`, delete from the legacy JSON features block:
```swift
        "fineControl": false,
        "bottomQuarterOnly": true,
```
and from the legacy JSON gesture block:
```swift
        "sensitivity": 1.5,
        "normalStep": 2.0,
        "fineStep": 0.5,
        "continuousWindowSeconds": 0.25
```

4. In `testGestureRecognition()`, delete the entire bottomQuarterSettings block (lines 173-187):
```swift
    var bottomQuarterSettings = AppSettings.default
    bottomQuarterSettings.features.bottomQuarterOnly = true
    recognizer = GestureRecognizer(settings: bottomQuarterSettings)
    ...
        "Bottom-quarter filtering should allow lower physical touches"
    )
```

5. Also delete the bottomQuarter re-entry block (lines 269-285):
```swift
    recognizer = GestureRecognizer(settings: bottomQuarterSettings)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 10, x: 0.05, y: 0.76)], timestamp: 62.0))
    ...
        "Movement after bottom-quarter re-entry baseline should emit"
    )
```

6. In `testActionDispatcher()`, replace the entire function body with:
```swift
private func testActionDispatcher() throws {
    let dispatcher = ActionDispatcher(settings: .default)
    try checkEqual(
        dispatcher.actions(for: .brightness(direction: .increase, magnitude: 1.0)),
        [.adjustBrightness(delta: 1.0)],
        "Brightness step should dispatch delta 1.0"
    )
    try checkEqual(
        dispatcher.actions(for: .volume(direction: .decrease, magnitude: 1.0)),
        [.adjustVolume(delta: -1.0)],
        "Volume step should dispatch delta -1.0"
    )
    try checkEqual(
        dispatcher.actions(for: .middleClick(x: 250, y: 125)),
        [.middleClick(x: 250, y: 125)],
        "Middle click should dispatch"
    )
}
```

- [ ] **Step 2: Run checks to verify RED**

Run:
```bash
swift run SlidrFreeCoreChecks
```
Expected: compile failure — `settings.features.fineControl`, `settings.gesture.sensitivity`, etc. still exist but test code removed; or `bottomQuarterOnly` still referenced in GestureRecognizer. The key RED signal is that `testActionDispatcher` expects `delta: 1.0` but current `signedDelta` returns `0.35`.

- [ ] **Step 3: Remove stale fields from AppSettings**

In `Sources/SlidrFreeCore/AppSettings.swift`, change `FeatureToggles` to:
```swift
public struct FeatureToggles: Codable, Equatable, Sendable {
    public var volumeEdgeGesture: Bool
    public var brightnessEdgeGesture: Bool
    public var middleClick: Bool
    public var swapSides: Bool
    public var smartTypingDetection: Bool
}
```

Change `GestureSettings` to:
```swift
public struct GestureSettings: Codable, Equatable, Sendable {
    public var edgeWidthPercent: Double
    public var typingCooldownSeconds: Double
    public var physicalStepDistance: Double
    public var physicalStepIntervalSeconds: Double

    public init(
        edgeWidthPercent: Double,
        typingCooldownSeconds: Double,
        physicalStepDistance: Double,
        physicalStepIntervalSeconds: Double
    ) {
        self.edgeWidthPercent = edgeWidthPercent
        self.typingCooldownSeconds = typingCooldownSeconds
        self.physicalStepDistance = physicalStepDistance
        self.physicalStepIntervalSeconds = physicalStepIntervalSeconds
    }
}
```

Update the custom `CodingKeys` and `init(from:)` to only include remaining fields, using `decodeIfPresent` for `physicalStepDistance` and `physicalStepIntervalSeconds` so old settings files without them still decode:

```swift
    private enum CodingKeys: String, CodingKey {
        case edgeWidthPercent
        case typingCooldownSeconds
        case physicalStepDistance
        case physicalStepIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.edgeWidthPercent = try container.decode(Double.self, forKey: .edgeWidthPercent)
        self.typingCooldownSeconds = try container.decode(Double.self, forKey: .typingCooldownSeconds)
        self.physicalStepDistance = try container.decodeIfPresent(Double.self, forKey: .physicalStepDistance) ?? AppSettings.default.gesture.physicalStepDistance
        self.physicalStepIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .physicalStepIntervalSeconds) ?? AppSettings.default.gesture.physicalStepIntervalSeconds
    }
```

Update `AppSettings.default` to:
```swift
    public static let `default` = AppSettings(
        isAppEnabled: true,
        launchAtLogin: false,
        features: FeatureToggles(
            volumeEdgeGesture: true,
            brightnessEdgeGesture: true,
            middleClick: true,
            swapSides: false,
            smartTypingDetection: true
        ),
        gesture: GestureSettings(
            edgeWidthPercent: 0.10,
            typingCooldownSeconds: 1.0,
            physicalStepDistance: 0.10,
            physicalStepIntervalSeconds: 0.08
        )
    )
```

Update `validated()` to:
```swift
    public func validated() -> AppSettings {
        var copy = self
        copy.gesture.edgeWidthPercent = min(max(copy.gesture.edgeWidthPercent, 0.04), 0.20)
        copy.gesture.typingCooldownSeconds = min(max(copy.gesture.typingCooldownSeconds, 0.0), 2.0)
        copy.gesture.physicalStepDistance = min(max(copy.gesture.physicalStepDistance, 0.02), 0.50)
        copy.gesture.physicalStepIntervalSeconds = min(max(copy.gesture.physicalStepIntervalSeconds, 0.0), 0.50)
        return copy
    }
```

- [ ] **Step 4: Simplify ActionDispatcher.signedDelta**

In `Sources/SlidrFreeCore/ActionDispatcher.swift`, replace the `signedDelta` method with:
```swift
    private func signedDelta(direction: GestureDirection, magnitude: Double) -> Double {
        let sign = direction == .increase ? 1.0 : -1.0
        return sign * magnitude
    }
```

- [ ] **Step 5: Remove bottomQuarterOnly from GestureRecognizer**

In `Sources/SlidrFreeCore/GestureRecognizer.swift`, delete these lines (52-55):
```swift
            guard !settings.features.bottomQuarterOnly || current.y >= 0.75 else {
                resetPhysicalContinuity()
                return nil
            }
```

- [ ] **Step 6: Run checks and tests to verify GREEN**

Run:
```bash
swift run SlidrFreeCoreChecks && swift test && swift build
```
Expected: all pass.

- [ ] **Step 7: Commit Task 2**

```bash
git add Sources/SlidrFreeCore/AppSettings.swift Sources/SlidrFreeCore/ActionDispatcher.swift Sources/SlidrFreeCore/GestureRecognizer.swift Sources/SlidrFreeCoreChecks/main.swift
git commit -m "refactor: remove stale gesture and feature fields"
```

---

### Task 3: Simplify SettingsView and MenuBarController

**Files:**
- Modify: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Sources/SlidrFreeApp/MenuBarController.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`

**Interfaces:**
- Consumes: simplified `AppSettings` from Task 2.
- Produces: SettingsView without stale controls; MenuBarController without Permissions item and without permissionManager dependency.

- [ ] **Step 1: Remove stale controls from SettingsView**

In `Sources/SlidrFreeApp/SettingsView.swift`:

1. In the `section_edge_gestures` Section, delete these lines:
```swift
                Toggle(NSLocalizedString("bottom_quarter_only", comment: ""), isOn: binding(\.features.bottomQuarterOnly))
                labeledSlider(NSLocalizedString("sensitivity", comment: ""), value: binding(\.gesture.sensitivity), range: 0.10...4.0)
                labeledSlider(NSLocalizedString("normal_step", comment: ""), value: binding(\.gesture.normalStep), range: 0.10...10.0)
                labeledSlider(NSLocalizedString("fine_step", comment: ""), value: binding(\.gesture.fineStep), range: 0.05...store.settings.gesture.normalStep)
```

2. In the `section_clicks` Section, delete:
```swift
                Toggle(NSLocalizedString("fine_control", comment: ""), isOn: binding(\.features.fineControl))
```

3. In the `section_safety` Section, delete:
```swift
                Toggle(NSLocalizedString("cursor_freeze", comment: ""), isOn: binding(\.features.cursorFreeze))
                labeledSlider(NSLocalizedString("continuous_window", comment: ""), value: binding(\.gesture.continuousWindowSeconds), range: 0.05...1.0, suffix: "s")
```

- [ ] **Step 2: Remove Permissions menu item from MenuBarController**

In `Sources/SlidrFreeApp/MenuBarController.swift`:

1. Delete `private let permissionManager: PermissionManager` (line 6).
2. Delete `permissionManager` from init parameters and body (line 10, 12).
3. Delete the Permissions menu item line:
```swift
        menu.addItem(NSMenuItem(title: NSLocalizedString("permissions", comment: ""), action: #selector(openPermissions), keyEquivalent: ""))
```
4. Delete the `openPermissions` method:
```swift
    @objc private func openPermissions() {
        permissionManager.openPrivacySettings()
    }
```

- [ ] **Step 3: Update AppDelegate to match new MenuBarController init**

In `Sources/SlidrFreeApp/AppDelegate.swift`, update the `MenuBarController(...)` call (lines 24-29) to remove `permissionManager:`:

```swift
        menuBarController = MenuBarController(
            settingsStore: settingsStore,
            showSettings: { [weak self] in self?.settingsWindowController?.show() },
            showDebug: { [weak self] in self?.debugWindowController?.show() }
        )
```

- [ ] **Step 4: Build and test**

Run:
```bash
swift build && swift test && swift run SlidrFreeCoreChecks
```
Expected: all pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/SlidrFreeApp/SettingsView.swift Sources/SlidrFreeApp/MenuBarController.swift Sources/SlidrFreeApp/AppDelegate.swift
git commit -m "refactor: simplify settings and menu UI"
```

---

### Task 4: Clean Up Localizable Strings

**Files:**
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Consumes: final list of UI keys from Task 3.
- Produces: localized strings without stale keys.

- [ ] **Step 1: Remove stale keys from English strings**

In `Resources/en.lproj/Localizable.strings`, delete these lines:
```
"permissions" = "Permissions…";
"bottom_quarter_only" = "Bottom quarter only";
"sensitivity" = "Sensitivity";
"normal_step" = "Normal step";
"fine_step" = "Fine step";
"fine_control" = "Fine control";
"cursor_freeze" = "Cursor freeze";
"continuous_window" = "Continuous window";
"open_privacy_settings" = "Open Privacy Settings";
```

- [ ] **Step 2: Remove stale keys from Chinese strings**

In `Resources/zh-Hans.lproj/Localizable.strings`, delete these lines:
```
"permissions" = "权限…";
"bottom_quarter_only" = "仅底部四分之一区域";
"sensitivity" = "灵敏度";
"normal_step" = "普通步进";
"fine_step" = "精细步进";
"fine_control" = "精细控制";
"cursor_freeze" = "光标冻结";
"continuous_window" = "连续窗口";
"open_privacy_settings" = "打开隐私设置";
```

- [ ] **Step 3: Build to verify no missing keys**

Run:
```bash
swift build
```
Expected: build succeeds.

- [ ] **Step 4: Commit Task 4**

```bash
git add Resources/en.lproj/Localizable.strings Resources/zh-Hans.lproj/Localizable.strings
git commit -m "refactor: remove stale localized strings"
```

---

### Task 5: Update README and Delete Release Asset

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- GitHub Release v0.1.0 asset deletion via gh CLI.

**Interfaces:**
- Consumes: final project state from Tasks 1-4.
- Produces: README pointing to source-only release; GitHub Release with no binary assets.

- [ ] **Step 1: Update README install instructions**

In `README.md`, find any sections that reference downloading a prebuilt zip or `Slidr-Free.app.zip` from releases. Replace those instructions with building from source:

```markdown
## Installation

Slidr-Free is distributed as source code only. Build it locally:

```bash
git clone https://github.com/YuriGao/slidr-free.git
cd slidr-free
swift build -c release
bash scripts/package-release.sh
```

Then drag `release/Slidr-Free.app` to your Applications folder.
```

Remove or replace any `xattr -cr` Gatekeeper workaround text since there is no longer a downloaded zip. If the app is built locally, quarantine does not apply.

- [ ] **Step 2: Update Chinese README similarly**

In `README.zh-CN.md`, make the equivalent changes:

```markdown
## 安装

Slidr-Free 仅以源代码形式发布。在本地构建：

```bash
git clone https://github.com/YuriGao/slidr-free.git
cd slidr-free
swift build -c release
bash scripts/package-release.sh
```

然后将 `release/Slidr-Free.app` 拖到「应用程序」文件夹。
```

- [ ] **Step 3: Commit README changes**

```bash
git add README.md README.zh-CN.md
git commit -m "docs: update install instructions for source-only release"
```

- [ ] **Step 4: Delete the release zip asset**

Run:
```bash
gh release delete-asset v0.1.0 "Slidr-Free.app.zip" --yes
```
Expected: asset deleted.

- [ ] **Step 5: Verify release has no binary assets**

Run:
```bash
gh release view v0.1.0 --json tagName,name,assets,url
```
Expected: `"assets"` is an empty array `[]`.

- [ ] **Step 6: Push all commits**

```bash
git push origin main
```
Expected: all commits pushed.

---

### Task 6: Final Verification

**Files:**
- No file changes unless verification fails.

- [ ] **Step 1: Run full verification**

Run:
```bash
swift test && swift build && swift run SlidrFreeCoreChecks
```
Expected: all pass.

- [ ] **Step 2: Verify no cursor code remains**

Run:
```bash
rg 'freezeCursor|unfreezeCursor|cursorFreeze|CGWarpMouseCursorPosition|CGAssociateMouseAndMouseCursorPosition|NSCursor\.hide|NSCursor\.unhide' Sources/
```
Expected: no matches.

- [ ] **Step 3: Verify no stale settings references remain**

Run:
```bash
rg 'fineControl|bottomQuarterOnly|sensitivity|normalStep|fineStep|continuousWindowSeconds|cursorFreeze' Sources/
```
Expected: no matches.

- [ ] **Step 4: Verify release is source-only**

Run:
```bash
gh release view v0.1.0 --json assets
```
Expected: `"assets": []`.
