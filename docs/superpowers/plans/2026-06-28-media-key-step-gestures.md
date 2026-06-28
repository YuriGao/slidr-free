# Media-Key Step Gestures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make brightness work via system media keys and make physical edge gestures emit discrete key-like steps instead of per-frame actions.

**Architecture:** Extend the existing media-key event factory to support brightness keys, then route `SystemControl.adjustBrightness(delta:)` through the same HID media-key posting path as volume. Update `GestureRecognizer` to accumulate physical touch movement and emit one `magnitude: 1.0` gesture only after a normalized step threshold and minimum interval are met.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit `NSEvent.otherEvent`, CoreGraphics HID event posting, existing `SlidrFreeCoreChecks`, XCTest for app-level media-key tests.

## Global Constraints

- macOS target remains macOS 13 or newer.
- Do not add a direct brightness slider or precision brightness percentage control.
- Do not introduce `DisplayServices.framework` in this iteration.
- Do not restore scroll-wheel screen-edge gestures.
- Do not change the physical trackpad private API monitor design.
- Brightness media-key event values must use key type `2` for brightness up and `3` for brightness down.
- Gesture defaults: `stepDistance` is `0.10` normalized trackpad height and `minStepIntervalSeconds` is `0.08` seconds.
- Each emitted physical edge step uses `magnitude: 1.0`.

---

## File Structure

- Modify `Sources/SlidrFreeApp/MediaKeyEventFactory.swift`: add brightness media-key cases and key type mapping.
- Modify `Tests/SlidrFreeAppTests/MediaKeyEventFactoryTests.swift`: add brightness up/down event construction tests.
- Modify `Sources/SlidrFreeApp/SystemControl.swift`: route brightness through media-key posting and remove normal dependence on `IODisplayConnect`.
- Modify `Sources/SlidrFreeCore/AppSettings.swift`: add `physicalStepDistance` and `physicalStepIntervalSeconds` to `GestureSettings`, with defaults and validation clamps.
- Modify `Sources/SlidrFreeCore/GestureRecognizer.swift`: add active-step accumulator state and emit discrete physical gesture steps.
- Modify `Sources/SlidrFreeCoreChecks/main.swift`: update existing gesture/action expectations and add regression checks for threshold, throttle, and reset behavior.

---

### Task 1: Add Brightness Media-Key Events

**Files:**
- Modify: `Sources/SlidrFreeApp/MediaKeyEventFactory.swift`
- Modify: `Tests/SlidrFreeAppTests/MediaKeyEventFactoryTests.swift`

**Interfaces:**
- Consumes: existing `enum MediaKey` and `MediaKeyEventFactory.events(for:) -> [NSEvent]?`.
- Produces: `MediaKey.brightnessUp`, `MediaKey.brightnessDown`, and event data values `0x0002_0A00`, `0x0002_0B00`, `0x0003_0A00`, `0x0003_0B00`.

- [ ] **Step 1: Write the failing brightness media-key tests**

Append these tests to `Tests/SlidrFreeAppTests/MediaKeyEventFactoryTests.swift` inside `MediaKeyEventFactoryTests`:

```swift
    func testBrightnessUpUsesSystemDefinedAuxControlMediaKeyEvents() throws {
        let events = try XCTUnwrap(MediaKeyEventFactory.events(for: .brightnessUp))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.systemDefined, .systemDefined])
        XCTAssertEqual(events.map(\.subtype.rawValue), [8, 8])
        XCTAssertEqual(events.map(\.data1), [0x0002_0A00, 0x0002_0B00])
        XCTAssertEqual(events.map(\.data2), [-1, -1])
        XCTAssertEqual(events.map { $0.cgEvent != nil }, [true, true])
    }

    func testBrightnessDownUsesSystemDefinedAuxControlMediaKeyEvents() throws {
        let events = try XCTUnwrap(MediaKeyEventFactory.events(for: .brightnessDown))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.systemDefined, .systemDefined])
        XCTAssertEqual(events.map(\.subtype.rawValue), [8, 8])
        XCTAssertEqual(events.map(\.data1), [0x0003_0A00, 0x0003_0B00])
        XCTAssertEqual(events.map(\.data2), [-1, -1])
        XCTAssertEqual(events.map { $0.cgEvent != nil }, [true, true])
    }
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter MediaKeyEventFactoryTests
```

Expected: compile failure mentioning `type 'MediaKey' has no member 'brightnessUp'` or `brightnessDown`.

- [ ] **Step 3: Implement the minimal media-key cases**

Update `Sources/SlidrFreeApp/MediaKeyEventFactory.swift` so `MediaKey` is:

```swift
enum MediaKey {
    case volumeUp
    case volumeDown
    case brightnessUp
    case brightnessDown

    fileprivate var nxKeyType: Int32 {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        }
    }
}
```

Leave `MediaKeyEventFactory` unchanged.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
swift test --filter MediaKeyEventFactoryTests
```

Expected: all 4 `MediaKeyEventFactoryTests` pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/SlidrFreeApp/MediaKeyEventFactory.swift Tests/SlidrFreeAppTests/MediaKeyEventFactoryTests.swift
git commit -m "feat: add brightness media key events"
```

---

### Task 2: Route Brightness Through Media-Key Posting

**Files:**
- Modify: `Sources/SlidrFreeApp/SystemControl.swift`

**Interfaces:**
- Consumes: `MediaKey.brightnessUp`, `MediaKey.brightnessDown`, existing `postMediaKey(_:) -> Bool`.
- Produces: `SystemControl.adjustBrightness(delta:) -> SystemActionResult` that posts brightness media keys and no longer returns `failed("No built-in display service")` during normal execution.

- [ ] **Step 1: Write the failing expectation as a temporary focused test by inspection**

There is no safe automated test for HID posting without refactoring `SystemControl`. Use the existing app-level tests from Task 1 as the automated event-construction guard, then make this one mechanical routing change only. Before editing, confirm the old failing string exists:

```bash
rg 'No built-in display service|IODisplayGetFloatParameter|IODisplaySetFloatParameter' Sources/SlidrFreeApp/SystemControl.swift
```

Expected: matches in `adjustBrightness(delta:)`.

- [ ] **Step 2: Replace `adjustBrightness(delta:)` with media-key routing**

In `Sources/SlidrFreeApp/SystemControl.swift`, replace the entire current `adjustBrightness(delta:)` method with:

```swift
    func adjustBrightness(delta: Double) -> SystemActionResult {
        let isUp = delta > 0
        guard postMediaKey(isUp ? .brightnessUp : .brightnessDown) else {
            let message = "Failed to create media key events"
            logWarning(message)
            _ = showFeedback(kind: isUp ? .brightnessUp : .brightnessDown, message: message)
            return .failed(message)
        }
        _ = showFeedback(kind: isUp ? .brightnessUp : .brightnessDown, message: nil)
        return .success
    }
```

- [ ] **Step 3: Remove unused IOKit brightness helper code**

In `Sources/SlidrFreeApp/SystemControl.swift`:

1. Remove `import IOKit` if the compiler reports it is unused and no other code in the file needs it.
2. Delete this helper method entirely:

```swift
    private func displayService() -> io_service_t? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
        return service != 0 ? service : nil
    }
```

- [ ] **Step 4: Verify the old failure path is gone**

Run:

```bash
rg 'No built-in display service|IODisplayGetFloatParameter|IODisplaySetFloatParameter|IODisplayConnect' Sources/SlidrFreeApp/SystemControl.swift
```

Expected: no matches.

- [ ] **Step 5: Build and test**

Run:

```bash
swift test && swift build
```

Expected: tests pass and build succeeds.

- [ ] **Step 6: Commit Task 2**

```bash
git add Sources/SlidrFreeApp/SystemControl.swift
git commit -m "fix: post brightness media keys"
```

---

### Task 3: Add Step Gesture Settings

**Files:**
- Modify: `Sources/SlidrFreeCore/AppSettings.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Consumes: existing `GestureSettings` Codable struct.
- Produces: `GestureSettings.physicalStepDistance: Double` and `GestureSettings.physicalStepIntervalSeconds: Double`.

- [ ] **Step 1: Write failing default and clamp checks**

In `Sources/SlidrFreeCoreChecks/main.swift`, update `testDefaultSettingsEnableAllFirstVersionFeaturesIndividually()` by adding after the existing gesture/default checks:

```swift
    try checkEqual(settings.gesture.physicalStepDistance, 0.10, accuracy: 0.0001, "Physical step distance should default to 0.10")
    try checkEqual(settings.gesture.physicalStepIntervalSeconds, 0.08, accuracy: 0.0001, "Physical step interval should default to 0.08s")
```

Update `testValidationClampsGestureSettings()` by adding before `let validated = settings.validated()`:

```swift
    settings.gesture.physicalStepDistance = 2.0
    settings.gesture.physicalStepIntervalSeconds = -1.0
```

Then add after the existing clamp assertions:

```swift
    try checkEqual(validated.gesture.physicalStepDistance, 0.50, accuracy: 0.0001, "Physical step distance should clamp")
    try checkEqual(validated.gesture.physicalStepIntervalSeconds, 0.0, accuracy: 0.0001, "Physical step interval should clamp")
```

- [ ] **Step 2: Run checks and verify RED**

Run:

```bash
swift run SlidrFreeCoreChecks
```

Expected: compile failure mentioning `GestureSettings` has no member `physicalStepDistance` or `physicalStepIntervalSeconds`.

- [ ] **Step 3: Add settings fields, defaults, and clamps**

In `Sources/SlidrFreeCore/AppSettings.swift`, change `GestureSettings` to include:

```swift
    public var physicalStepDistance: Double
    public var physicalStepIntervalSeconds: Double
```

Place them after `continuousWindowSeconds`.

In `AppSettings.default`, change the `gesture: GestureSettings(...)` call to include:

```swift
            continuousWindowSeconds: 0.35,
            physicalStepDistance: 0.10,
            physicalStepIntervalSeconds: 0.08
```

In `validated()`, add:

```swift
        copy.gesture.physicalStepDistance = min(max(copy.gesture.physicalStepDistance, 0.02), 0.50)
        copy.gesture.physicalStepIntervalSeconds = min(max(copy.gesture.physicalStepIntervalSeconds, 0.0), 0.50)
```

- [ ] **Step 4: Run checks and verify GREEN**

Run:

```bash
swift run SlidrFreeCoreChecks
```

Expected: all SlidrFreeCore checks pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/SlidrFreeCore/AppSettings.swift Sources/SlidrFreeCoreChecks/main.swift
git commit -m "feat: add physical step gesture settings"
```

---

### Task 4: Implement Physical Step Accumulation

**Files:**
- Modify: `Sources/SlidrFreeCore/GestureRecognizer.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Consumes: `settings.gesture.physicalStepDistance`, `settings.gesture.physicalStepIntervalSeconds`.
- Produces: step-based `GestureRecognizer.process(.physicalTouchFrame(...)) -> RecognizedGesture?` with `magnitude: 1.0` only when threshold and interval allow.

- [ ] **Step 1: Update expected existing gesture checks to the new step model**

In `Sources/SlidrFreeCoreChecks/main.swift`, update the first brightness test around lines 100-104 to expect a single key-like step:

```swift
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.30, pressure: 0.5, state: 4)], timestamp: 10.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.41, pressure: 0.5, state: 4)], timestamp: 10.1)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Physical left edge brightness increase should emit one step"
    )
```

Keep the existing right-edge volume and swapped-side checks as `magnitude: 1.0`, but ensure their movements cross at least `0.10` normalized height.

- [ ] **Step 2: Add explicit threshold/throttle/reset regression checks**

Append this block inside `testGestureRecognition()` before the disabled-app test:

```swift
    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.20)], timestamp: 60.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.25)], timestamp: 60.1)),
        nil,
        "Physical movement below step threshold should not emit"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.31)], timestamp: 60.2)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Crossing physical step threshold should emit one brightness step"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.42)], timestamp: 60.23)),
        nil,
        "Physical step interval should suppress immediate repeated steps"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.53)], timestamp: 60.32)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Physical movement after interval should emit another step"
    )

    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 8, x: 0.05, y: 0.20)], timestamp: 61.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 8, x: 0.30, y: 0.40)], timestamp: 61.1)),
        nil,
        "Leaving the physical edge should reset accumulated movement"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 9, x: 0.05, y: 0.60)], timestamp: 61.2)),
        nil,
        "Changing physical touch ID should reset accumulated movement"
    )
```

- [ ] **Step 3: Run checks and verify RED**

Run:

```bash
swift run SlidrFreeCoreChecks
```

Expected: at least one gesture-recognition failure because current recognizer emits per-frame gestures below threshold or ignores throttle.

- [ ] **Step 4: Add step accumulator state**

In `Sources/SlidrFreeCore/GestureRecognizer.swift`, add this private state after `previousPrimaryPhysicalTouch`:

```swift
    private var activePhysicalStep: PhysicalStepState?
```

Add this private struct near the bottom of the file before the final `}`:

```swift
private struct PhysicalStepState: Sendable {
    var touchID: Int
    var edge: PhysicalEdgeHit
    var accumulatedY: Double
    var lastEmitTimestamp: Double?
}
```

Update `init` to set:

```swift
        self.activePhysicalStep = nil
```

- [ ] **Step 5: Reset accumulator on non-continuous physical state**

In `GestureRecognizer.process(_:)`, whenever the physical path currently sets `previousPrimaryPhysicalTouch = nil` because there are no touches, also set:

```swift
                activePhysicalStep = nil
```

Whenever the touch is outside the edge or fails bottom-quarter filtering, set:

```swift
                resetPhysicalStepState()
```

Add this helper inside `GestureRecognizer`:

```swift
    private mutating func resetPhysicalStepState() {
        activePhysicalStep = nil
    }
```

- [ ] **Step 6: Replace per-frame magnitude emission with threshold logic**

In `GestureRecognizer.process(_:)`, replace lines that compute `magnitude = min(max(abs(deltaY) / 0.12, 0.25), 3.0)` and immediately return brightness/volume with logic equivalent to:

```swift
            let leftEdge = edgeHit == .left
            let rightEdge = edgeHit == .right
            let controlsBrightness = settings.features.swapSides ? rightEdge : leftEdge
            let controlsVolume = settings.features.swapSides ? leftEdge : rightEdge

            let recognizedKind: PhysicalStepKind?
            if controlsBrightness && settings.features.brightnessEdgeGesture {
                recognizedKind = .brightness
            } else if controlsVolume && settings.features.volumeEdgeGesture {
                recognizedKind = .volume
            } else {
                resetPhysicalStepState()
                return nil
            }

            guard let step = physicalStep(deltaY: deltaY, touchID: current.id, edge: edgeHit, timestamp: timestamp) else {
                return nil
            }

            switch recognizedKind {
            case .brightness:
                return .brightness(direction: step, magnitude: 1.0)
            case .volume:
                return .volume(direction: step, magnitude: 1.0)
            case .none:
                return nil
            }
```

Add this enum below `PhysicalStepState`:

```swift
private enum PhysicalStepKind: Sendable {
    case brightness
    case volume
}
```

Add this helper inside `GestureRecognizer`:

```swift
    private mutating func physicalStep(deltaY: Double, touchID: Int, edge: PhysicalEdgeHit, timestamp: Double) -> GestureDirection? {
        let stepDistance = settings.gesture.physicalStepDistance
        if activePhysicalStep?.touchID != touchID || activePhysicalStep?.edge != edge {
            activePhysicalStep = PhysicalStepState(touchID: touchID, edge: edge, accumulatedY: 0, lastEmitTimestamp: nil)
        }

        activePhysicalStep?.accumulatedY += deltaY
        guard let state = activePhysicalStep else { return nil }

        let direction: GestureDirection
        if state.accumulatedY >= stepDistance {
            direction = .increase
        } else if state.accumulatedY <= -stepDistance {
            direction = .decrease
        } else {
            return nil
        }

        if let lastEmitTimestamp = state.lastEmitTimestamp,
           timestamp - lastEmitTimestamp < settings.gesture.physicalStepIntervalSeconds {
            return nil
        }

        let consumed = direction == .increase ? stepDistance : -stepDistance
        activePhysicalStep?.accumulatedY -= consumed
        activePhysicalStep?.lastEmitTimestamp = timestamp
        return direction
    }
```

- [ ] **Step 7: Keep typing cooldown state fresh without accumulating actions**

In the smart-typing cooldown branch, keep `updatePreviousPrimaryPhysicalTouch(from: touches)` but also call:

```swift
                resetPhysicalStepState()
```

This prevents movement during typing cooldown from accumulating into a later action.

- [ ] **Step 8: Run checks and verify GREEN**

Run:

```bash
swift run SlidrFreeCoreChecks
```

Expected: all SlidrFreeCore checks pass.

- [ ] **Step 9: Run full Swift tests**

Run:

```bash
swift test
```

Expected: all XCTest tests pass.

- [ ] **Step 10: Commit Task 4**

```bash
git add Sources/SlidrFreeCore/GestureRecognizer.swift Sources/SlidrFreeCoreChecks/main.swift
git commit -m "fix: emit physical gestures as steps"
```

---

### Task 5: Final Verification and Release Packaging

**Files:**
- Modify only if needed after verification: `scripts/package-release.sh`
- Generated: `release/Slidr-Free.app`, `release/Slidr-Free.app.zip`

**Interfaces:**
- Consumes: committed implementation from Tasks 1-4.
- Produces: verified local release zip ready for GitHub upload.

- [ ] **Step 1: Ensure Slidr-Free is not running**

Run:

```bash
osascript -e 'tell application id "com.slidr.free" to quit' >/dev/null 2>&1 || true
pkill -x "SlidrFreeApp" >/dev/null 2>&1 || true
sleep 1
pgrep -fl "SlidrFreeApp|Slidr-Free" || true
```

Expected: no matching Slidr-Free process remains.

- [ ] **Step 2: Run full verification**

Run:

```bash
swift test && swift build && swift run SlidrFreeCoreChecks && bash "scripts/package-release.sh" && codesign --verify --verbose=2 "release/Slidr-Free.app"
```

Expected: all commands exit 0; package script reports `Done: release/Slidr-Free.app.zip`; codesign reports valid on disk and satisfies its Designated Requirement.

- [ ] **Step 3: Inspect app and zip timestamps**

Run:

```bash
stat -f '%Sm %N' -t '%Y-%m-%d %H:%M:%S' "release/Slidr-Free.app" "release/Slidr-Free.app/Contents/MacOS/SlidrFreeApp" "release/Slidr-Free.app.zip"
```

Expected: the executable and zip timestamps reflect the fresh build. If the outer `.app` timestamp is older, report that Finder may show the bundle directory timestamp while the executable and zip are fresh.

- [ ] **Step 4: Commit package-script change only if one was required**

If `scripts/package-release.sh` was changed during verification, run:

```bash
git add scripts/package-release.sh
git commit -m "fix: rebuild release bundle from scratch"
```

If no script change was made, skip this step.

- [ ] **Step 5: Upload release asset after user approval**

Run only after the user asks to update GitHub:

```bash
git push origin main
gh release upload v0.1.0 "release/Slidr-Free.app.zip" --clobber
gh release view v0.1.0 --json tagName,name,assets,url
```

Expected: `origin/main` contains the new commits and the release asset `Slidr-Free.app.zip` has a new `updatedAt` timestamp and digest.
