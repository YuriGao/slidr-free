# Top Edge Browser Tab Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add continuous top-edge trackpad gestures for switching Safari and Chrome tabs with haptic feedback.

**Architecture:** Extend the pure core recognizer with top-edge horizontal step accumulation and a browser-tab action. Keep browser detection and key-event posting in the app layer so the core remains testable and platform-neutral.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit, CoreGraphics, existing `SlidrFreeCoreChecks`, XCTest app tests.

---

## File Structure

- Modify `Sources/SlidrFreeCore/PhysicalTouch.swift` to add `.top` to `PhysicalEdgeHit`.
- Modify `Sources/SlidrFreeCore/AppSettings.swift` to add the tab-switch feature toggle and gesture tuning fields.
- Modify `Sources/SlidrFreeCore/GestureRecognizer.swift` to recognize top-edge horizontal tab switching.
- Modify `Sources/SlidrFreeCore/ActionDispatcher.swift` to map browser-tab gestures to system actions.
- Modify `Sources/SlidrFreeCoreChecks/main.swift` for RED/GREEN core checks.
- Create `Sources/SlidrFreeApp/BrowserTabKeyEventFactory.swift` for bracket shortcut events and browser bundle filtering.
- Modify `Sources/SlidrFreeApp/SystemControl.swift` to execute browser tab switching.
- Modify `Sources/SlidrFreeApp/AppDelegate.swift` to route the new action and trigger haptics on success.
- Modify `Sources/SlidrFreeApp/SettingsView.swift` and `Resources/*/Localizable.strings` to expose the toggle.
- Modify `Tests/SlidrFreeAppTests/MediaKeyEventFactoryTests.swift` or add a new test file for keyboard event factory checks.
- Modify `README.md` and `README.zh-CN.md` to describe the new feature.

## Task 1: Core Gesture RED Tests

**Files:**
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

- [ ] **Step 1: Add failing browser-tab gesture checks**

Add a helper overload for `[SystemAction]` if needed and add tests that expect:

```swift
private func testTopEdgeBrowserTabGestureRecognition() throws {
    var recognizer = GestureRecognizer(settings: .default)

    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 21, x: 0.30, y: 0.95)], timestamp: 70.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 21, x: 0.37, y: 0.95)], timestamp: 70.21)),
        .browserTab(direction: .next),
        "Top edge rightward movement should switch to next tab"
    )

    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 22, x: 0.70, y: 0.95)], timestamp: 71.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 22, x: 0.62, y: 0.95)], timestamp: 71.21)),
        .browserTab(direction: .previous),
        "Top edge leftward movement should switch to previous tab"
    )
}
```

- [ ] **Step 2: Verify RED**

Run: `swift run SlidrFreeCoreChecks`

Expected: compile failure because `.browserTab` and `BrowserTabDirection` do not exist.

## Task 2: Core Gesture GREEN Implementation

**Files:**
- Modify: `Sources/SlidrFreeCore/PhysicalTouch.swift`
- Modify: `Sources/SlidrFreeCore/AppSettings.swift`
- Modify: `Sources/SlidrFreeCore/GestureRecognizer.swift`
- Modify: `Sources/SlidrFreeCore/ActionDispatcher.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

- [ ] **Step 1: Add core types and settings**

Add `BrowserTabDirection { case next, previous }`, add
`RecognizedGesture.browserTab(direction:)`, add
`FeatureToggles.browserTabEdgeGesture`, and add gesture settings
`tabSwitchStepIntervalSeconds` and `horizontalDominanceRatio` with defaults.

- [ ] **Step 2: Implement top-edge detection**

Extend edge detection so `.top` is selected when `y >= 1 - edgeWidthPercent`.
Track a separate physical step state that accumulates `deltaX` and emits next
or previous steps while preserving leftover movement.

- [ ] **Step 3: Verify GREEN**

Run: `swift run SlidrFreeCoreChecks`

Expected: all checks pass.

## Task 3: App Action RED Tests

**Files:**
- Create: `Sources/SlidrFreeApp/BrowserTabKeyEventFactory.swift`
- Modify or create test: `Tests/SlidrFreeAppTests/BrowserTabKeyEventFactoryTests.swift`

- [ ] **Step 1: Add failing app tests**

Test that Safari and Chrome bundle ids are allowed, another bundle id is not,
and next/previous keyboard event generation returns key-down and key-up events.

- [ ] **Step 2: Verify RED**

Run: `swift test`

Expected: fail because the factory type or methods are missing.

## Task 4: App Action GREEN Implementation

**Files:**
- Create: `Sources/SlidrFreeApp/BrowserTabKeyEventFactory.swift`
- Modify: `Sources/SlidrFreeApp/SystemControl.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`

- [ ] **Step 1: Implement keyboard event factory**

Create a factory that maps `.next` to key code `30` with `.maskCommand` and
`.maskShift`, and `.previous` to key code `33` with the same modifiers. Return
down/up `CGEvent`s.

- [ ] **Step 2: Add browser filtering and execution**

Add `switchBrowserTab(direction:)` to `SystemControlling` and `SystemControl`.
Check the frontmost bundle id at execution time and return `.unsupported` for
non-browser apps.

- [ ] **Step 3: Route actions and haptics**

Handle `.switchBrowserTab` in `AppDelegate.execute(action:)`. Trigger haptics
only when the result is `.success`.

- [ ] **Step 4: Verify GREEN**

Run: `swift test` and `swift run SlidrFreeCoreChecks`.

Expected: app tests and core checks pass.

## Task 5: Settings, Docs, Package Verification

**Files:**
- Modify: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `README.md`
- Modify: `README.zh-CN.md`

- [ ] **Step 1: Add settings toggle and copy**

Add a toggle bound to `features.browserTabEdgeGesture` and localized labels.

- [ ] **Step 2: Update README files**

Document the top-edge browser tab gesture and browser scope.

- [ ] **Step 3: Full verification**

Run:

```bash
swift run SlidrFreeCoreChecks
swift build
bash scripts/package-release.sh
codesign --verify --verbose=2 release/Slidr-Free.app
```

Expected: all commands exit 0.

- [ ] **Step 4: Install verified app**

Replace `~/Applications/Slidr-Free.app` with the newly built app and restart it.
