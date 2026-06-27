# Slidr-Free Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a free open-source macOS 13+ menu bar app that provides configurable trackpad edge gestures for volume/brightness, middle click, safety filters, permissions guidance, documentation, CI, packaging, and GitHub release artifacts.

**Architecture:** Use a Swift Package with a testable `SlidrFreeCore` library and an executable `SlidrFreeApp`. Core owns settings models, gesture recognition, dispatch decisions, and testable abstractions; App owns AppKit/SwiftUI UI, permissions, CGEventTap, and macOS system controls.

**Tech Stack:** Swift 5.9+, SwiftPM, AppKit, SwiftUI, CoreGraphics, ApplicationServices, ServiceManagement, executable `SlidrFreeCoreChecks`, GitHub Actions, gh CLI.

## Global Constraints

- Target platform: macOS 13+.
- Implementation: Swift + AppKit/SwiftUI native macOS menu bar application.
- Distribution: source code + unsigned Release package.
- License: MIT.
- Clean-room rule: do not copy third-party product names, icons, screenshots, copy, visual style, source code, binaries, or private implementation details.
- README and releases must state the project is independent and not affiliated with any commercial app.
- First version excludes external display DDC/CI brightness control.
- Every feature must be independently enabled/disabled.

---

## File Structure

- `Package.swift` — SwiftPM package definition for core library, app executable, and executable core checks.
- `Sources/SlidrFreeCore/AppSettings.swift` — settings model, defaults, toggle fields, persistence keys.
- `Sources/SlidrFreeCore/InputEvent.swift` — normalized input event types used by tests and app event tap.
- `Sources/SlidrFreeCore/GestureRecognizer.swift` — pure gesture recognition state machine.
- `Sources/SlidrFreeCore/ActionDispatcher.swift` — maps recognized gestures to abstract system actions.
- `Sources/SlidrFreeCore/PermissionStatus.swift` — pure permission status model for UI display.
- `Sources/SlidrFreeCoreChecks/main.swift` — executable checks for core behavior in environments without XCTest/Testing modules.
- `Sources/SlidrFreeApp/main.swift` — NSApplication entry point.
- `Sources/SlidrFreeApp/AppDelegate.swift` — app lifecycle, dependency wiring, event tap start/stop.
- `Sources/SlidrFreeApp/MenuBarController.swift` — `NSStatusItem` menu.
- `Sources/SlidrFreeApp/SettingsWindowController.swift` — hosts SwiftUI settings view.
- `Sources/SlidrFreeApp/SettingsView.swift` — SwiftUI settings UI.
- `Sources/SlidrFreeApp/PermissionManager.swift` — Accessibility/Input Monitoring checks and System Settings opening.
- `Sources/SlidrFreeApp/InputEventTap.swift` — CGEventTap bridge to normalized core events.
- `Sources/SlidrFreeApp/SystemControl.swift` — protocol implementation for volume, brightness, cursor, middle click, and feedback.
- `scripts/package-release.sh` — builds release executable and creates unsigned `.app.zip`.
- `.github/workflows/ci.yml` — build/test/package validation.
- `README.md`, `LICENSE`, `.gitignore` — public project documentation and repo metadata.

---

### Task 1: Initialize git-managed Swift package and metadata

**Files:**
- Create: `.gitignore`
- Create: `Package.swift`
- Create: `README.md`
- Create: `LICENSE`
- Create: `Sources/SlidrFreeCore/AppSettings.swift`
- Create: `Sources/SlidrFreeApp/main.swift`
- Create: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Produces: `AppSettings`, `FeatureToggles`, `GestureSettings`, `AppSettings.default`, `AppSettings.validate()`.

- [ ] **Step 1: Initialize git repository**

Run:

```bash
git init
```

Expected: repository initialized in `/Users/gaoyinrui/Documents/git/slidr-free`.

- [ ] **Step 2: Create SwiftPM skeleton and metadata**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlidrFree",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SlidrFreeCore", targets: ["SlidrFreeCore"]),
        .executable(name: "SlidrFreeApp", targets: ["SlidrFreeApp"]),
        .executable(name: "SlidrFreeCoreChecks", targets: ["SlidrFreeCoreChecks"])
    ],
    targets: [
        .target(name: "SlidrFreeCore"),
        .executableTarget(name: "SlidrFreeCoreChecks", dependencies: ["SlidrFreeCore"]),
        .executableTarget(
            name: "SlidrFreeApp",
            dependencies: ["SlidrFreeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
```

Create `.gitignore`:

```gitignore
.DS_Store
.build/
.swiftpm/
DerivedData/
*.xcuserdata/
*.zip
release/
```

Create `LICENSE` with MIT license using copyright holder `Slidr-Free contributors`.

Create initial `README.md` with: project purpose, independent/non-affiliated notice, macOS 13+ requirement, unsigned-build warning, build command `swift build`, executable check command `swift run SlidrFreeCoreChecks`, and feature list.

- [ ] **Step 3: Write settings executable checks**

Create `Sources/SlidrFreeCoreChecks/main.swift` with simple assertion helpers that exercise the AppSettings defaults and validation behavior without XCTest/Testing.

```swift
import SlidrFreeCore

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let settings = AppSettings.default
check(settings.isAppEnabled, "App should be enabled by default")
// Continue checking default feature toggles and validated gesture clamping.
print("All SlidrFreeCore checks passed")
```

- [ ] **Step 4: Run executable checks to verify they fail**

Run:

```bash
swift run SlidrFreeCoreChecks
```

Expected: FAIL because `AppSettings` is not defined.

- [ ] **Step 5: Implement settings model and minimal executable**

Create `Sources/SlidrFreeCore/AppSettings.swift`:

```swift
import Foundation

public struct FeatureToggles: Codable, Equatable, Sendable {
    public var volumeEdgeGesture: Bool
    public var brightnessEdgeGesture: Bool
    public var middleClick: Bool
    public var fineControl: Bool
    public var swapSides: Bool
    public var bottomQuarterOnly: Bool
    public var smartTypingDetection: Bool
    public var cursorFreeze: Bool
}

public struct GestureSettings: Codable, Equatable, Sendable {
    public var edgeWidthPercent: Double
    public var sensitivity: Double
    public var normalStep: Double
    public var fineStep: Double
    public var typingCooldownSeconds: Double
    public var continuousWindowSeconds: Double
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var isAppEnabled: Bool
    public var launchAtLogin: Bool
    public var features: FeatureToggles
    public var gesture: GestureSettings

    public static let `default` = AppSettings(
        isAppEnabled: true,
        launchAtLogin: false,
        features: FeatureToggles(
            volumeEdgeGesture: true,
            brightnessEdgeGesture: true,
            middleClick: true,
            fineControl: true,
            swapSides: false,
            bottomQuarterOnly: false,
            smartTypingDetection: true,
            cursorFreeze: true
        ),
        gesture: GestureSettings(
            edgeWidthPercent: 0.10,
            sensitivity: 1.0,
            normalStep: 1.0,
            fineStep: 0.35,
            typingCooldownSeconds: 1.0,
            continuousWindowSeconds: 0.35
        )
    )

    public func validated() -> AppSettings {
        var copy = self
        copy.gesture.edgeWidthPercent = min(max(copy.gesture.edgeWidthPercent, 0.04), 0.20)
        copy.gesture.sensitivity = min(max(copy.gesture.sensitivity, 0.10), 4.0)
        copy.gesture.normalStep = min(max(copy.gesture.normalStep, 0.10), 10.0)
        copy.gesture.fineStep = min(max(copy.gesture.fineStep, 0.05), copy.gesture.normalStep)
        copy.gesture.typingCooldownSeconds = min(max(copy.gesture.typingCooldownSeconds, 0.0), 2.0)
        copy.gesture.continuousWindowSeconds = min(max(copy.gesture.continuousWindowSeconds, 0.05), 1.0)
        return copy
    }
}
```

Create `Sources/SlidrFreeApp/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 6: Verify and commit**

Run:

```bash
swift run SlidrFreeCoreChecks
git add .
git commit -m "chore: initialize swift package"
```

Expected: executable checks PASS and first git commit created.

---

### Task 2: Add pure gesture recognizer and dispatcher

**Files:**
- Create: `Sources/SlidrFreeCore/InputEvent.swift`
- Create: `Sources/SlidrFreeCore/GestureRecognizer.swift`
- Create: `Sources/SlidrFreeCore/ActionDispatcher.swift`
- Create: `Tests/SlidrFreeCoreTests/GestureRecognizerTests.swift`
- Create: `Tests/SlidrFreeCoreTests/ActionDispatcherTests.swift`

**Interfaces:**
- Consumes: `AppSettings`.
- Produces: `NormalizedInputEvent`, `RecognizedGesture`, `GestureRecognizer.process(_:)`, `SystemAction`, `ActionDispatcher.actions(for:)`.

- [ ] **Step 1: Extend failing executable gesture checks**

Extend `Sources/SlidrFreeCoreChecks/main.swift` with checks for left brightness, right volume, swap sides, bottom-quarter filtering, typing cooldown, disabled app, and middle click.

Use exact event constructors from the original plan examples and custom equality assertions.

Extend `Sources/SlidrFreeCoreChecks/main.swift` with action dispatcher checks for fine control, normal control when fine control is disabled, and middle click dispatch.

- [ ] **Step 2: Run failing tests**

Run: `swift run SlidrFreeCoreChecks`

Expected: FAIL because recognizer and dispatcher types do not exist.

- [ ] **Step 3: Implement pure core recognition and dispatch**

Create the listed core files with public enums/structs matching the test names. Use `Foundation.CGSize` via `import Foundation`.

Implementation rules:

- Left edge: `x <= width * edgeWidthPercent`.
- Right edge: `x >= width * (1 - edgeWidthPercent)`.
- Bottom quarter: `y >= height * 0.75`.
- Increase when `deltaY > 0`, decrease when `deltaY < 0`.
- Magnitude for first version: `min(max(abs(deltaY) / 8.0, 0.25), 3.0)`.
- Typing cooldown: suppress when `timestamp - lastKeyDown <= typingCooldownSeconds`.

- [ ] **Step 4: Verify and commit**

Run:

```bash
swift run SlidrFreeCoreChecks
git add Sources/SlidrFreeCore Sources/SlidrFreeCoreChecks
git commit -m "feat: add gesture recognition core"
```

Expected: executable checks PASS.

---

### Task 3: Add AppKit menu bar app, settings UI, and settings persistence

**Files:**
- Create: `Sources/SlidrFreeApp/AppDelegate.swift`
- Create: `Sources/SlidrFreeApp/MenuBarController.swift`
- Create: `Sources/SlidrFreeApp/SettingsStore.swift`
- Create: `Sources/SlidrFreeApp/SettingsWindowController.swift`
- Create: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Sources/SlidrFreeApp/main.swift`

**Interfaces:**
- Consumes: `AppSettings`.
- Produces: `SettingsStore.settings`, `SettingsStore.save(_:)`, `MenuBarController.refresh()`, visible menu/settings toggles.

- [ ] **Step 1: Add app-layer settings store**

Implement `SettingsStore` as `ObservableObject` that stores encoded `AppSettings` in `UserDefaults` key `SlidrFree.settings.v1`. On decode failure, use `.default.validated()`.

- [ ] **Step 2: Implement SwiftUI settings view**

Create toggles and sliders for all settings groups: General, Edge Gestures, Clicks, Safety, Permissions placeholder. Every toggle updates `SettingsStore` immediately.

- [ ] **Step 3: Implement menu bar and app delegate**

Use `NSStatusItem.squareLength`, title `SF`, menu items: Enable/Disable App, Settings…, Permissions…, Quit. Wire Settings… to show the SwiftUI settings window.

- [ ] **Step 4: Verify build and commit**

Run:

```bash
swift build
swift run SlidrFreeCoreChecks
git add Sources/SlidrFreeApp
git commit -m "feat: add menu bar settings app"
```

Expected: build and executable checks PASS.

---

### Task 4: Add permissions manager and login item handling

**Files:**
- Create: `Sources/SlidrFreeCore/PermissionStatus.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`
- Create: `Sources/SlidrFreeApp/PermissionManager.swift`
- Modify: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Sources/SlidrFreeApp/MenuBarController.swift`

**Interfaces:**
- Produces: `PermissionState`, `PermissionSnapshot`, `PermissionManager.currentSnapshot()`, `PermissionManager.promptForAccessibility()`, `PermissionManager.openPrivacySettings()`, `PermissionManager.setLaunchAtLogin(_:)`.

- [ ] **Step 1: Add permission model executable checks**

Check that `PermissionSnapshot.canListen` is true only when both Accessibility and Input Monitoring are granted.

- [ ] **Step 2: Implement pure permission model**

Create `PermissionStatus.swift` with `PermissionState: String, Codable, Equatable` cases `.granted`, `.denied`, `.unknown`; and `PermissionSnapshot` with `accessibility`, `inputMonitoring`, `canListen`.

- [ ] **Step 3: Implement app permission bridge**

Use `AXIsProcessTrustedWithOptions`, `CGPreflightListenEventAccess()`, and `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)` for settings opening. Implement login item via `SMAppService.mainApp.register()` / `.unregister()` guarded for macOS 13+.

- [ ] **Step 4: Wire UI and commit**

Run:

```bash
swift run SlidrFreeCoreChecks
swift build
git add Sources
git commit -m "feat: add permission and login controls"
```

Expected: executable checks and build PASS.

---

### Task 5: Add event tap bridge and system control execution

**Files:**
- Create: `Sources/SlidrFreeApp/InputEventTap.swift`
- Create: `Sources/SlidrFreeApp/SystemControl.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `GestureRecognizer`, `ActionDispatcher`, `SystemAction`.
- Produces: running event pipeline from CGEventTap to macOS actions.

- [ ] **Step 1: Implement `SystemControlling` protocol and concrete system control**

Protocol methods: `adjustVolume(delta:)`, `adjustBrightness(delta:)`, `middleClick(x:y:)`, `freezeCursor(at:)`, `unfreezeCursor()`, `showFeedback(kind:)`.

Implementation constraints:

- Volume: use `NSSound.systemVolume` equivalent is unavailable, so simulate volume media keys with `CGEvent(keyboardEventSource:virtualKey:keyDown:)` using documented key event path where possible; if unreliable, log warning and show feedback.
- Brightness: wrap IOKit/CoreDisplay calls behind the protocol; if the call fails, log warning and show feedback.
- Middle click: post `.otherMouseDown` / `.otherMouseUp` with button number 2.
- Feedback: use a small original `NSPanel` or notification-like overlay; do not imitate commercial UI.

- [ ] **Step 2: Implement listen-only event tap bridge**

Create `InputEventTap` with `start()`, `stop()`, `isRunning`. Map scroll/click/key events into `NormalizedInputEvent`. Keep event tap callback minimal and dispatch to main queue for recognizer/action handling.

- [ ] **Step 3: Wire lifecycle**

In `AppDelegate`, start event tap only when app is enabled and permissions allow listening. Stop on terminate and when disabled. Rebuild recognizer when settings change.

- [ ] **Step 4: Verify build and commit**

Run:

```bash
swift build
swift run SlidrFreeCoreChecks
git add Sources/SlidrFreeApp
git commit -m "feat: connect event tap actions"
```

Expected: build and executable checks PASS. Manual functionality may require macOS permissions.

---

### Task 6: Add packaging, CI, and release documentation

**Files:**
- Create: `scripts/package-release.sh`
- Create: `.github/workflows/ci.yml`
- Modify: `README.md`

**Interfaces:**
- Produces: `release/Slidr-Free.app.zip`, GitHub Actions CI, complete user docs.

- [ ] **Step 1: Add packaging script**

Create script that runs `swift build -c release`, creates `release/Slidr-Free.app/Contents/MacOS`, copies `.build/release/SlidrFreeApp`, writes `Info.plist` with `LSUIElement=true`, then zips app bundle.

- [ ] **Step 2: Add CI**

GitHub Actions on push/PR using `macos-14`, steps: checkout, `swift run SlidrFreeCoreChecks`, `swift build`, `bash scripts/package-release.sh`, upload artifact `Slidr-Free.app.zip`.

- [ ] **Step 3: Complete README**

Document: features, toggles, permissions, unsigned build warning, build/test/package commands, clean-room/non-affiliation, roadmap, known limitations including no external display brightness in v0.1.0.

- [ ] **Step 4: Verify and commit**

Run:

```bash
bash scripts/package-release.sh
swift run SlidrFreeCoreChecks
git add README.md scripts .github
git commit -m "chore: add packaging and ci"
```

Expected: package zip exists and executable checks PASS.

---

### Task 7: Final verification, GitHub public repo, and release

**Files:**
- Modify only if verification finds required fixes.

**Interfaces:**
- Produces: public GitHub repository and first GitHub release with unsigned zip artifact.

- [ ] **Step 1: Run full verification**

Run:

```bash
git status --short
swift run SlidrFreeCoreChecks
swift build
bash scripts/package-release.sh
```

Expected: clean or intentional working tree, executable checks PASS, build PASS, `release/Slidr-Free.app.zip` exists.

- [ ] **Step 2: Create public GitHub repository with gh**

Run:

```bash
gh repo create slidr-free --public --source=. --remote=origin --push
```

Expected: GitHub public repository created and current branch pushed.

- [ ] **Step 3: Create v0.1.0 release**

Run:

```bash
gh release create v0.1.0 release/Slidr-Free.app.zip --title "Slidr-Free v0.1.0" --notes "Initial unsigned macOS 13+ menu bar release. Independent open-source project; not affiliated with any commercial app. Downloaded app is unsigned; see README for build and Gatekeeper instructions."
```

Expected: GitHub release created with `Slidr-Free.app.zip` attached.

---

## Self-Review

- Spec coverage: all first-version features, toggles, macOS 13+, Swift native app, MIT, unsigned release, docs, CI, GitHub release, no DDC/CI, clean-room notice are covered.
- Placeholder scan: no TBD/TODO placeholders; lower-level system API uncertainty is represented as an explicit fallback inside `SystemControl`.
- Type consistency: `AppSettings`, `GestureRecognizer`, `ActionDispatcher`, `PermissionSnapshot`, and action names are introduced before they are consumed.
- Scope note: this is a full first-version product. Tasks are split so core logic is testable before app/system integration.
