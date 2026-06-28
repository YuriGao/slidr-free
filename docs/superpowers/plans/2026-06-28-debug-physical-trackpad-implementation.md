# Debug Physical Trackpad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Debug panel, action execution diagnostics, and experimental physical trackpad edge gesture detection through macOS private MultitouchSupport, while disabling the current screen-edge scroll gesture path.

**Architecture:** Keep pure gesture recognition in `SlidrFreeCore`. Add app-layer debug state and a private-API `PhysicalTrackpadMonitor` that translates raw MultitouchSupport touch frames into `NormalizedInputEvent.physicalTouchFrame`. Route recognizer output and system action results into a shared `DebugState` rendered by a SwiftUI debug window.

**Tech Stack:** Swift 5.9+, SwiftPM, AppKit, SwiftUI, CoreGraphics, ApplicationServices, ServiceManagement, Darwin `dlopen`/`dlsym`, private MultitouchSupport runtime loading, executable `SlidrFreeCoreChecks`.

## Global Constraints

- Target platform: macOS 13+.
- Implementation: Swift + AppKit/SwiftUI native macOS menu bar application.
- Distribution: source code + unsigned Release package.
- License: MIT.
- Clean-room rule: do not copy third-party product names, icons, screenshots, copy, visual style, source code, binaries, or private implementation details.
- Physical trackpad edge detection depends on macOS private MultitouchSupport API and must be marked experimental.
- Public API screen-edge scroll detection must not remain a formal gesture path.
- If MultitouchSupport is unavailable, physical edge gestures are unavailable; do not silently fall back to mouse/screen-edge scroll gestures.
- The app must not crash when the private framework or trackpad device is unavailable.

---

## File Structure

- `Sources/SlidrFreeCore/PhysicalTouch.swift` — pure `PhysicalTouch` value type and `PhysicalEdgeHit` enum.
- `Sources/SlidrFreeCore/InputEvent.swift` — add `.physicalTouchFrame(touches:timestamp:)`.
- `Sources/SlidrFreeCore/GestureRecognizer.swift` — process physical touch frames; stop recognizing screen-position scroll edge gestures.
- `Sources/SlidrFreeCore/ActionDispatcher.swift` — keep gesture-to-action mapping stable.
- `Sources/SlidrFreeApp/DebugState.swift` — observable debug state and bounded 50-line log.
- `Sources/SlidrFreeApp/DebugWindowController.swift` — AppKit window hosting `DebugView`.
- `Sources/SlidrFreeApp/DebugView.swift` — read-only SwiftUI diagnostics UI.
- `Sources/SlidrFreeApp/PhysicalTrackpadMonitor.swift` — private MultitouchSupport dynamic loader and frame callback bridge.
- `Sources/SlidrFreeApp/SystemControl.swift` — return `SystemActionResult` from action methods and record failure details.
- `Sources/SlidrFreeApp/AppDelegate.swift` — wire physical monitor, debug state, recognizer, dispatcher, and action results.
- `Sources/SlidrFreeApp/MenuBarController.swift` — add `Debug…` menu item.
- `Sources/SlidrFreeApp/SettingsView.swift` — rename edge gesture wording to physical trackpad edge gestures and add experimental warning.
- `Resources/*/Localizable.strings` — add localized Debug and experimental/private API strings.
- `Sources/SlidrFreeCoreChecks/main.swift` — add checks for physical touch frame recognition and action result model.
- `README.md`, `README.zh-CN.md` — document private API risk, Debug panel, and no public API fallback.

---

### Task 1: Pure physical touch model and recognizer checks

**Files:**
- Create: `Sources/SlidrFreeCore/PhysicalTouch.swift`
- Modify: `Sources/SlidrFreeCore/InputEvent.swift`
- Modify: `Sources/SlidrFreeCore/GestureRecognizer.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Produces: `PhysicalTouch`, `PhysicalEdgeHit`, `NormalizedInputEvent.physicalTouchFrame(touches:timestamp:)`.
- Consumes: `AppSettings.gesture.edgeWidthPercent`, `FeatureToggles.swapSides`, `bottomQuarterOnly`, `smartTypingDetection`.

- [ ] **Step 1: Add failing executable checks**

Extend `Sources/SlidrFreeCoreChecks/main.swift` with checks that call:

```swift
var recognizer = GestureRecognizer(settings: .default)
_ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.30, pressure: 0.5, state: 4)], timestamp: 10.0))
let gesture = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.55, pressure: 0.5, state: 4)], timestamp: 10.1))
check(gesture == .brightness(direction: .increase, magnitude: 1.0), "physical left edge brightness increase")
```

Also add checks for right-edge volume, swap sides, bottom-quarter filtering, and no screen-edge scroll gesture recognition.

- [ ] **Step 2: Verify failing check**

Run: `swift run SlidrFreeCoreChecks`

Expected: compile failure because `PhysicalTouch` and `.physicalTouchFrame` do not exist.

- [ ] **Step 3: Implement pure model and recognizer**

Create `PhysicalTouch` as:

```swift
public struct PhysicalTouch: Equatable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let pressure: Double?
    public let state: Int?
    public init(id: Int, x: Double, y: Double, pressure: Double? = nil, state: Int? = nil) { ... }
}
```

Add `.physicalTouchFrame(touches:[PhysicalTouch], timestamp: Double)` to `NormalizedInputEvent` and equality.

Modify `GestureRecognizer`:

- `scroll` events only update typing cooldown if needed and return nil for edge gestures.
- Physical frames select the first touch as the primary touch.
- Store previous primary physical touch by id.
- Edge hit uses normalized x, not screen coordinates.
- Direction uses `current.y - previous.y`.
- Magnitude uses `min(max(abs(deltaY) / 0.12, 0.25), 3.0)`.

- [ ] **Step 4: Verify and commit**

Run:

```bash
swift run SlidrFreeCoreChecks
swift build
git add Sources/SlidrFreeCore Sources/SlidrFreeCoreChecks
git commit -m "feat: add physical touch gesture recognition"
```

Expected: checks and build PASS.

---

### Task 2: Debug state and Debug window UI

**Files:**
- Create: `Sources/SlidrFreeApp/DebugState.swift`
- Create: `Sources/SlidrFreeApp/DebugView.swift`
- Create: `Sources/SlidrFreeApp/DebugWindowController.swift`
- Modify: `Sources/SlidrFreeApp/MenuBarController.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Produces: `DebugState`, `DebugState.log(_:)`, `DebugWindowController.show()`, menu item `Debug…`.

- [ ] **Step 1: Add `DebugState`**

Create an `ObservableObject` with `@Published` properties: `accessibility`, `inputMonitoring`, `multitouchStatus`, `deviceStatus`, `monitorStatus`, `lastTouchCount`, `lastTouchDescription`, `lastEdgeHit`, `lastGesture`, `lastAction`, `lastActionResult`, `logs`. `log(_:)` appends timestamped lines and keeps at most 50.

- [ ] **Step 2: Add `DebugView` and window controller**

Create a read-only SwiftUI `Form` with rows for all DebugState fields and a scrollable log list plus `Clear Logs`.

- [ ] **Step 3: Add menu item**

Modify `MenuBarController` initializer to accept `showDebug: @escaping () -> Void`, add `Debug…` menu item below `Settings…`, and localize `debug` key.

- [ ] **Step 4: Wire from `AppDelegate`**

Instantiate `DebugState` and `DebugWindowController`; pass `showDebug` to `MenuBarController`; update debug permission fields when permission snapshot changes.

- [ ] **Step 5: Verify and commit**

Run:

```bash
swift build
swift run SlidrFreeCoreChecks
git add Sources/SlidrFreeApp Resources
git commit -m "feat: add debug diagnostics panel"
```

Expected: build and checks PASS.

---

### Task 3: System action execution results

**Files:**
- Modify: `Sources/SlidrFreeApp/SystemControl.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Produces: `SystemActionResult` with `.success`, `.failed(String)`, `.unsupported(String)`.

- [ ] **Step 1: Add result model and checks**

Add app-layer enum:

```swift
enum SystemActionResult: Equatable {
    case success
    case failed(String)
    case unsupported(String)
}
```

No core check should import app code; instead add pure string/action-result formatting checks only if moved to core. If kept app-layer only, verify through `swift build`.

- [ ] **Step 2: Return results from actions**

Change `SystemControlling`:

```swift
func adjustVolume(delta: Double) -> SystemActionResult
func adjustBrightness(delta: Double) -> SystemActionResult
func middleClick(x: Double, y: Double) -> SystemActionResult
func showFeedback(kind: FeedbackKind, message: String?) -> SystemActionResult
```

Volume returns `.success` after posting media key events. Brightness returns `.failed("No built-in display service")` if no display service exists, otherwise `.success` after attempting IOKit call.

- [ ] **Step 3: Log results**

Modify `AppDelegate.execute(action:)` to update `DebugState.lastAction`, `lastActionResult`, and log each action.

- [ ] **Step 4: Verify and commit**

Run:

```bash
swift build
swift run SlidrFreeCoreChecks
git add Sources
git commit -m "feat: report system action execution results"
```

Expected: build and checks PASS.

---

### Task 4: Private MultitouchSupport physical trackpad monitor

**Files:**
- Create: `Sources/SlidrFreeApp/PhysicalTrackpadMonitor.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`
- Modify: `Sources/SlidrFreeApp/DebugState.swift`

**Interfaces:**
- Produces: `PhysicalTrackpadMonitor.start()`, `stop()`, `isRunning`, callback `(NormalizedInputEvent) -> Void`, status updates to DebugState.

- [ ] **Step 1: Implement private API wrapper types**

In `PhysicalTrackpadMonitor.swift`, isolate private definitions:

```swift
private typealias MTDeviceRef = UnsafeMutableRawPointer
private struct MTPoint { var x: Float; var y: Float }
private struct MTVector { var position: MTPoint; var velocity: MTPoint }
private struct MTTouch { /* include padding conservatively; expose only normalizedPosition, pressure, state, identifier */ }
```

Use dynamic loading path `/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`.

- [ ] **Step 2: Load required symbols**

Use `dlopen` and `dlsym` for `MTDeviceCreateDefault`, `MTRegisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`. If any symbol is missing, set DebugState multitouch status to failed and do not crash.

- [ ] **Step 3: Register callback and emit frames**

Callback converts touches to `[PhysicalTouch]` using normalized x/y and dispatches `.physicalTouchFrame` to main queue.

- [ ] **Step 4: Wire lifecycle**

In `AppDelegate.updateEventTap()`, stop using `InputEventTap` for gesture recognition. Start `PhysicalTrackpadMonitor` when app enabled; stop it when disabled/terminating. Keep `InputEventTap` only if needed for keyDown smart typing and middle click diagnostics, not for screen-edge scroll gestures.

- [ ] **Step 5: Verify and commit**

Run:

```bash
swift build
swift run SlidrFreeCoreChecks
git add Sources/SlidrFreeApp
git commit -m "feat: add experimental physical trackpad monitor"
```

Expected: build and checks PASS. Runtime may show unavailable on systems where private API loading fails.

---

### Task 5: Settings text, README risk docs, packaging, and release update

**Files:**
- Modify: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `README.md`
- Modify: `README.zh-CN.md`

**Interfaces:**
- Produces: documented experimental private API behavior and updated release artifact.

- [ ] **Step 1: Update settings wording**

Rename edge gesture labels to clearly say physical trackpad edge gestures. Add experimental/private API warning text to the settings section.

- [ ] **Step 2: Update README files**

Add sections explaining MultitouchSupport private API, experimental support, no public API fallback, Debug panel use, and failure modes.

- [ ] **Step 3: Final verification and package**

Run:

```bash
swift build
swift run SlidrFreeCoreChecks
rm -rf release/
bash scripts/package-release.sh
codesign --verify --verbose=2 release/Slidr-Free.app
```

Expected: all pass and zip exists.

- [ ] **Step 4: Commit and publish**

Run:

```bash
git add Sources Resources README.md README.zh-CN.md
git commit -m "docs: document experimental physical trackpad support"
git push origin main
gh release upload v0.1.0 release/Slidr-Free.app.zip --clobber
```

Expected: main pushed and v0.1.0 artifact updated.

---

## Self-Review

- Spec coverage: Debug panel, action diagnostics, private MultitouchSupport monitor, no screen-edge public fallback, README risk docs, and release update are covered.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: `PhysicalTouch`, `NormalizedInputEvent.physicalTouchFrame`, `DebugState`, `PhysicalTrackpadMonitor`, and `SystemActionResult` are introduced before use.
- Risk handling: private API failure paths explicitly update Debug state and do not crash the app.
