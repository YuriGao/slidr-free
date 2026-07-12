# Middle-Click Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in exact-three-finger Tap and physical Click middle-button behavior without breaking existing edge gestures, while preserving MIT licensing, fail-open input behavior, and v0.2 settings.

**Architecture:** The private touch callback synchronously drives a pure core recognizer and a lock-protected session bridge before main-queue delivery. A dedicated-run-loop Event Tap delegates decisions to a pure reducer, while AppDelegate owns a generation-based lifecycle and unified quiesce transaction.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit, CoreGraphics, ApplicationServices, Combine, SwiftUI, private MultitouchSupport loaded with `dlopen`, XCTest, shell packaging, GitHub Actions.

---

## Global Constraints

- Work only from `docs/superpowers/specs/2026-07-12-middle-click-integration-design.md` and existing Slidr Free code; do not inspect or reuse MiddleClick source.
- v0.3 supports exact three fingers only. No configurable finger count, `allowMoreFingers`, application ignore list, multi-device enumeration, or Developer ID work.
- Ordinary input is fail-open whenever chord state is stale, cancelled, unknown, or the pipeline is quiescing.
- A Tap claim and physical Click consumption are mutually exclusive per session.
- Every transformed Down has at most one matching center Up across normal and teardown paths.
- Event Tap decisions must be testable without live Accessibility permission.
- Production code follows TDD: add a focused failing test, run it and observe the expected failure, implement minimally, rerun the focused test, then run the surrounding suite.
- Do not commit `.build/`, `release/`, app/zip artifacts, secrets, or TCC data.

## File Map

### Core

- `Sources/SlidrFreeCore/MiddleClickSettings.swift`: additive Codable settings with `isEnabled` and `tapEnabled`.
- `Sources/SlidrFreeCore/MiddleClickRecognizer.swift`: exact-three-finger pure state machine and normalized update model.
- `Sources/SlidrFreeCore/AppSettings.swift`: top-level additive migration.
- `Sources/SlidrFreeCore/GestureRecognizer.swift`: edge suppression latch.
- `Sources/SlidrFreeCore/ActionDispatcher.swift`: middle-click Tap action.

### App bridge

- `Sources/SlidrFreeApp/MiddleClickSessionBridge.swift`: atomic session state, freshness, claim/consume/quiesce.
- `Sources/SlidrFreeApp/MouseButtonEventReducer.swift`: pure pass/transform/release/re-enable decisions.
- `Sources/SlidrFreeApp/MouseButtonEventTap.swift`: dedicated thread/CFRunLoop wrapper.
- `Sources/SlidrFreeApp/MiddleClickEmitter.swift`: atomic pair creation and posting.
- `Sources/SlidrFreeApp/InputPipelineStatus.swift`: bounded runtime status.
- `Sources/SlidrFreeApp/PhysicalTrackpadMonitor.swift`: zero-frame/cancellation/sequence/generation adapter.
- `Sources/SlidrFreeApp/AppDelegate.swift`: pipeline coordination and lifecycle.
- `Sources/SlidrFreeApp/SystemControl.swift`: middle-click action execution.

### UI, tests, packaging

- `Sources/SlidrFreeApp/SettingsView.swift`, localization files: opt-in UI and status.
- `Tests/SlidrFreeCoreTests/`: core settings/recognizer/edge tests.
- `Tests/SlidrFreeAppTests/`: bridge, reducer, emitter, adapter, migration, lifecycle tests.
- `Package.swift`, `.github/workflows/ci.yml`: test targets and mandatory `swift test`.
- `scripts/package-release.sh`: v0.3.0/3001 plus packaged LICENSE.
- `docs/middle-click-provenance.md`, README files: provenance, scope, limitations, TCC.

### Task 1: Add core settings migration and exact-three-finger recognizer

**Files:**
- Create: `Sources/SlidrFreeCore/MiddleClickSettings.swift`
- Create: `Sources/SlidrFreeCore/MiddleClickRecognizer.swift`
- Create: `Tests/SlidrFreeCoreTests/MiddleClickRecognizerTests.swift`
- Create: `Tests/SlidrFreeCoreTests/AppSettingsMigrationTests.swift`
- Modify: `Sources/SlidrFreeCore/AppSettings.swift`
- Modify: `Package.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

- [ ] **Step 1: Add the Core XCTest target and failing migration tests**

Add `.testTarget(name: "SlidrFreeCoreTests", dependencies: ["SlidrFreeCore"])` to `Package.swift`. Write tests that decode representative v0.2 JSON, assert all old fields remain unchanged, and assert:

```swift
XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: false, tapEnabled: true))
```

Also test a nested payload containing only `{"isEnabled":true}` defaults `tapEnabled` to true.

- [ ] **Step 2: Run migration tests and verify RED**

Run:

```bash
swift test --filter AppSettingsMigrationTests
```

Expected: compile failure because `MiddleClickSettings` and `AppSettings.middleClick` do not exist.

- [ ] **Step 3: Implement additive settings decoding**

Define:

```swift
public struct MiddleClickSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var tapEnabled: Bool
    public static let `default` = Self(isEnabled: false, tapEnabled: true)
}
```

Provide custom nested and top-level decoders using `decodeIfPresent`. Keep `SlidrFree.settings.v1` unchanged and include `middleClick` in `AppSettings.validated()` without changing the two booleans.

- [ ] **Step 4: Run migration tests and verify GREEN**

Run `swift test --filter AppSettingsMigrationTests`. Expected: all selected tests pass.

- [ ] **Step 5: Add failing recognizer tests**

Define the desired API in tests:

```swift
var recognizer = MiddleClickRecognizer(tapEnabled: true)
let first = recognizer.process(.frame(generation: 1, sequence: 1, timestamp: 1.00, receivedAt: 10.00, touches: [touch(1)]))
let qualified = recognizer.process(.frame(generation: 1, sequence: 2, timestamp: 1.05, receivedAt: 10.05, touches: [touch(1), touch(2), touch(3)]))
let finished = recognizer.process(.empty(generation: 1, sequence: 3, timestamp: 1.20, receivedAt: 10.20))
XCTAssertFalse(first.chordActive)
XCTAssertTrue(qualified.chordActive)
XCTAssertTrue(finished.tapCandidate)
```

Cover exact-three success, counts above three, placement/release, duration/movement inclusive boundaries, ID reorder, ID replacement, non-increasing timestamp, cancellation, Tap disabled, and session ID increment.

- [ ] **Step 6: Run recognizer tests and verify RED**

Run `swift test --filter MiddleClickRecognizerTests`. Expected: compile failure because recognizer/update types do not exist.

- [ ] **Step 7: Implement the minimal pure recognizer**

Create normalized update and output types:

```swift
public enum MiddleClickInputUpdate: Equatable, Sendable {
    case frame(generation: UInt64, sequence: UInt64, timestamp: Double, receivedAt: Double, touches: [PhysicalTouch])
    case empty(generation: UInt64, sequence: UInt64, timestamp: Double, receivedAt: Double)
    case cancel(generation: UInt64, sequence: UInt64, receivedAt: Double, reason: MiddleClickCancellationReason)
}

public enum MiddleClickCancellationReason: Equatable, Sendable {
    case missingBuffer
    case invalidTouchCount
    case monitorStopped
    case pipelineReconfigured
    case permissionLost
    case systemSleep
}

public enum MiddleClickTerminalReason: Equatable, Sendable {
    case completed
    case invalidated
    case cancelled(MiddleClickCancellationReason)
}

public struct MiddleClickTouchUpdate: Equatable, Sendable {
    public let sessionID: UInt64?
    public let chordActive: Bool
    public let tapCandidate: Bool
    public let generation: UInt64
    public let sequence: UInt64
    public let receivedAt: Double
    public let terminalReason: MiddleClickTerminalReason?
}
```

Implement the state machine exactly as Section 7 of the design: session starts on first non-empty, exact-three qualification, stable ID set, centroid distance, release phase, inclusive thresholds, cancellation, and one candidate at empty.

- [ ] **Step 8: Run core tests and checks**

Run:

```bash
swift test --filter SlidrFreeCoreTests
swift run SlidrFreeCoreChecks
```

Expected: all selected tests and checks pass.

- [ ] **Step 9: Commit Task 1**

```bash
git add Package.swift Sources/SlidrFreeCore Sources/SlidrFreeCoreChecks Tests/SlidrFreeCoreTests
git commit -m "feat: add middle-click core recognizer"
```

### Task 2: Harden touch adaptation and edge arbitration

**Files:**
- Modify: `Sources/SlidrFreeCore/InputEvent.swift`
- Modify: `Sources/SlidrFreeCore/GestureRecognizer.swift`
- Modify: `Sources/SlidrFreeApp/PhysicalTrackpadMonitor.swift`
- Create: `Tests/SlidrFreeCoreTests/EdgeGestureArbitrationTests.swift`
- Create: `Tests/SlidrFreeAppTests/PhysicalTouchAdapterTests.swift`

- [ ] **Step 1: Write failing zero-frame adapter tests**

Extract a pure adapter that accepts `count`, optional touch values, sequence, generation, timestamps, and returns `.frame`, `.empty`, or `.cancel`. Test:

```swift
let empty = adapter.adapt(
    count: 0, touches: nil, generation: 7, sequence: 11,
    timestamp: 2.0, receivedAt: 20.0
)
XCTAssertEqual(empty, .empty(generation: 7, sequence: 11, timestamp: 2.0, receivedAt: 20.0))

let missing = adapter.adapt(
    count: 1, touches: nil, generation: 7, sequence: 12,
    timestamp: 2.1, receivedAt: 20.1
)
XCTAssertEqual(
    missing,
    .cancel(generation: 7, sequence: 12, receivedAt: 20.1, reason: .missingBuffer)
)
```

Also test invalid counts and generation/sequence propagation.

- [ ] **Step 2: Run adapter tests and verify RED**

Run `swift test --filter PhysicalTouchAdapterTests`. Expected: compile failure because adapter does not exist.

- [ ] **Step 3: Implement adapter and synchronous middle-click callback path**

Handle `count == 0` before unwrapping the buffer. Add monotonically increasing frame sequence and explicit cancellation on stop/restart. Copy values and invoke an injected synchronous `middleClickUpdateHandler: (MiddleClickInputUpdate) -> Void`; Task 5 will wire that seam to the recognizer and bridge. Then dispatch the existing normalized event to main for edge handling.

- [ ] **Step 4: Run adapter tests and verify GREEN**

Run `swift test --filter PhysicalTouchAdapterTests`. Expected: pass.

- [ ] **Step 5: Write failing edge-latch tests**

Test that normal single-finger edge steps still emit, a two/three-touch frame resets continuity and latches suppression, later single-touch frames stay suppressed, and empty/cancel clears the latch.

- [ ] **Step 6: Run edge tests and verify RED**

Run `swift test --filter EdgeGestureArbitrationTests`. Expected: at least the post-multitouch single-finger case fails under current `touches.first` behavior.

- [ ] **Step 7: Implement edge suppression latch**

Extend `NormalizedInputEvent` with `.physicalTouchCancelled`. Add `isSuppressingEdgesUntilEmpty`. Set it on `touches.count > 1`; reset continuity and return nil while latched; clear on empty/cancel. Preserve existing single-finger thresholds and browser behavior.

- [ ] **Step 8: Run core and app tests**

Run:

```bash
swift test --filter EdgeGestureArbitrationTests
swift test --filter PhysicalTouchAdapterTests
swift run SlidrFreeCoreChecks
```

- [ ] **Step 9: Commit Task 2**

```bash
git add Sources/SlidrFreeCore Sources/SlidrFreeApp/PhysicalTrackpadMonitor.swift Tests
git commit -m "feat: harden physical touch sequencing"
```

### Task 3: Implement atomic session bridge and pure mouse reducer

**Files:**
- Create: `Sources/SlidrFreeApp/MiddleClickSessionBridge.swift`
- Create: `Sources/SlidrFreeApp/MouseButtonEventReducer.swift`
- Create: `Tests/SlidrFreeAppTests/MiddleClickSessionBridgeTests.swift`
- Create: `Tests/SlidrFreeAppTests/MouseButtonEventReducerTests.swift`

- [ ] **Step 1: Write failing bridge tests**

Define bridge operations `applyTouchUpdate`, `claimTap`, `beginPhysical`, `continueDrag`, `finishPhysical`, and `quiesce`. Test both claim-vs-Down orders, freshness >0.15, event-number/button/generation matching, second Down, mismatched/duplicate Up, and one-time release extraction.

- [ ] **Step 2: Run bridge tests and verify RED**

Run `swift test --filter MiddleClickSessionBridgeTests`. Expected: compile failure because bridge types do not exist.

- [ ] **Step 3: Implement bridge reducer under one NSLock**

Use explicit private state cases matching the design. Use injected `now: () -> Double` for deterministic freshness tests. Never call CGEvent or UI while holding the lock. `quiesce()` atomically sets accepting false, increments generation, clears state, and returns an optional pending-release value.

- [ ] **Step 4: Run bridge tests and verify GREEN**

Run `swift test --filter MiddleClickSessionBridgeTests`. Expected: pass.

- [ ] **Step 5: Write failing mouse reducer tests**

Define normalized metadata:

```swift
struct MouseButtonEventMetadata: Equatable {
    var kind: Kind
    var sourceButton: Int64
    var eventNumber: Int64
    var marker: Int64
}
```

Test pass-through, Down/Dragged/Up transforms, marker pass-through, click state 1, mixed buttons, pending mismatch, timeout release request, and degraded decision after retries.

- [ ] **Step 6: Run reducer tests and verify RED**

Run `swift test --filter MouseButtonEventReducerTests`. Expected: compile failure because reducer types do not exist.

- [ ] **Step 7: Implement reducer decisions**

Return pure decisions only; do not construct CGEvents. Delegate atomic state changes to bridge. Tagged Slidr Free events pass through. Disabled notifications request quiesce/release and re-enable.

- [ ] **Step 8: Run bridge/reducer suites**

Run:

```bash
swift test --filter MiddleClickSessionBridgeTests
swift test --filter MouseButtonEventReducerTests
```

- [ ] **Step 9: Commit Task 3**

```bash
git add Sources/SlidrFreeApp/MiddleClickSessionBridge.swift Sources/SlidrFreeApp/MouseButtonEventReducer.swift Tests/SlidrFreeAppTests
git commit -m "feat: add atomic middle-click session bridge"
```

### Task 4: Add Event Tap, emitter, and system action

**Files:**
- Create: `Sources/SlidrFreeApp/MouseButtonEventTap.swift`
- Create: `Sources/SlidrFreeApp/MiddleClickEmitter.swift`
- Modify: `Sources/SlidrFreeCore/ActionDispatcher.swift`
- Modify: `Sources/SlidrFreeApp/SystemControl.swift`
- Create: `Tests/SlidrFreeAppTests/MiddleClickEmitterTests.swift`
- Create: `Tests/SlidrFreeAppTests/MouseButtonEventFactoryTests.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

- [ ] **Step 1: Write failing emitter/factory tests**

Inject event creation/posting protocols. Test both events are created before posting, neither posts when either creation fails, Down then Up order, shared current location, marker, center button, and click state 1.

- [ ] **Step 2: Run tests and verify RED**

Run `swift test --filter MiddleClickEmitterTests`. Expected: compile failure because emitter/factory types do not exist.

- [ ] **Step 3: Implement emitter and transform factory**

Create `MiddleClickEmitter.emitClick() -> SystemActionResult`. Add a factory function that applies reducer decisions to incoming CGEvent type/button/click state while preserving unrelated fields.

- [ ] **Step 4: Run emitter/factory tests and verify GREEN**

Run:

```bash
swift test --filter MiddleClickEmitterTests
swift test --filter MouseButtonEventFactoryTests
```

- [ ] **Step 5: Add failing action-dispatch checks**

Assert `.middleClickTap` maps to `.middleClick` and SystemControl delegates to the emitter.

- [ ] **Step 6: Implement the action path**

Extend `RecognizedGesture`, `SystemAction`, `ActionDispatcher`, `SystemControlling`, and AppDelegate switch exhaustiveness. Do not add haptic feedback in v0.3.

- [ ] **Step 7: Implement dedicated Event Tap wrapper**

Create a dedicated Thread/CFRunLoop owner. Add left/right Down/Up/Dragged mask, timeout/user-input disabled handling, three 100 ms re-enable attempts verified with `CGEvent.tapIsEnabled`, completion-based start/quiesce/stop, and safe deinit.

- [ ] **Step 8: Run app tests and build**

Run:

```bash
swift test --filter SlidrFreeAppTests
swift run SlidrFreeCoreChecks
swift build
```

- [ ] **Step 9: Commit Task 4**

```bash
git add Sources Tests
git commit -m "feat: add middle-button event bridge"
```

### Task 5: Integrate lifecycle, settings UI, and diagnostics

**Files:**
- Create: `Sources/SlidrFreeApp/InputPipelineStatus.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`
- Modify: `Sources/SlidrFreeApp/PermissionManager.swift`
- Modify: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Sources/SlidrFreeApp/SettingsStore.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/SlidrFreeAppTests/InputPipelineLifecycleTests.swift`
- Create: `Tests/SlidrFreeAppTests/SettingsStoreMigrationTests.swift`

- [ ] **Step 1: Write failing SettingsStore migration tests**

Use an isolated UserDefaults suite. Write real v0.2 encoded data, initialize SettingsStore, verify every old field plus middle-click defaults, save, reload, and compare the complete settings value.

- [ ] **Step 2: Run migration tests and verify RED**

Run `swift test --filter SettingsStoreMigrationTests`. Expected: fail until SettingsStore/AppSettings integration is complete.

- [ ] **Step 3: Write failing lifecycle coordinator tests**

Extract pipeline decisions behind protocols for touch monitor, Event Tap, bridge, emitter, permissions, and wake notifications. Test enabled/disabled, Tap-only preference, permission loss, settings change while pending, will-sleep/did-wake 2-second restart, termination wait, Event Tap failure, and no restart for unrelated settings.

- [ ] **Step 4: Run lifecycle tests and verify RED**

Run `swift test --filter InputPipelineLifecycleTests`. Expected: compile failure because coordinator seams/status do not exist.

- [ ] **Step 5: Implement generation-based AppDelegate coordination**

Rename `updateEventTap` to `updateInputPipeline`. Add unified quiesce/restart sequencing, settings diffing, permission refresh, sleep/wake observers, status publishing, synchronous middle-click frame callback, and main-queue Tap action dispatch.

- [ ] **Step 6: Implement settings UI and localization**

Add feature and Tap toggles, fixed-three-finger text, conflict guidance, and bounded runtime state. Do not add advanced threshold or finger-count controls.

- [ ] **Step 7: Run focused and full tests**

Run:

```bash
swift test --filter SettingsStoreMigrationTests
swift test --filter InputPipelineLifecycleTests
swift test
swift run SlidrFreeCoreChecks
```

- [ ] **Step 8: Commit Task 5**

```bash
git add Sources Resources Tests
git commit -m "feat: integrate middle-click input lifecycle"
```

### Task 6: Package license/version, document provenance, and verify the branch

**Files:**
- Modify: `scripts/package-release.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Create: `docs/middle-click-provenance.md`
- Create: `Tests/SlidrFreeAppTests/ReleaseBundleContractTests.swift` or `scripts/verify-release.sh`

- [ ] **Step 1: Write a failing release contract check**

Create `scripts/verify-release.sh` that exits non-zero unless the packaged app contains:

```text
Contents/Resources/LICENSE
CFBundleIdentifier = com.slidr.free
CFBundleShortVersionString = 0.3.0
CFBundleVersion = 3001
```

It also runs `codesign --verify --verbose=2`.

- [ ] **Step 2: Run package verification and observe RED**

Run:

```bash
bash scripts/package-release.sh
bash scripts/verify-release.sh
```

Expected: verification fails because baseline version is 0.2.0 and LICENSE is absent.

- [ ] **Step 3: Update packaging and CI**

Set version 0.3.0/build 3001, copy root LICENSE into app Resources, recreate ZIP, and run the verifier in CI after packaging. Add unconditional `swift test` before build/package.

- [ ] **Step 4: Add provenance and user documentation**

Document fixed reference SHA, allowed/prohibited inputs, no source reuse, dependency inventory, exact-three/default-device/global-mouse-source limitations, private API risk, TCC reauthorization, default-off beta behavior, and rollback baseline. Remove stale Debug-panel and “no menu bar” claims.

- [ ] **Step 5: Run secret scan and documentation checks**

Run:

```bash
/Users/zhupin/.codex/hooks/secret-scan.sh README.md README.zh-CN.md docs scripts
git diff --check
```

Expected: no secret matches and no whitespace errors.

- [ ] **Step 6: Run mandatory automated gates**

```bash
swift run SlidrFreeCoreChecks
swift test
swift build
bash scripts/package-release.sh
bash scripts/verify-release.sh
```

Expected: all commands exit 0; XCTest reports 0 failures; core checks report all PASS; app signature and release contract verify.

- [ ] **Step 7: Verify repository hygiene**

```bash
git status --short
git check-ignore -q .build release/Slidr-Free.app release/Slidr-Free.app.zip
git diff --check
```

Expected: only intentional source/docs changes before commit; generated build/release outputs ignored.

- [ ] **Step 8: Commit Task 6**

```bash
git add .github Package.swift README.md README.zh-CN.md Resources Sources Tests docs scripts
git commit -m "chore: prepare middle-click beta verification"
```

### Task 7: Final review, GitHub submission, and PR evidence

**Files:**
- Modify only files required by final review findings.

- [ ] **Step 1: Run a whole-branch review against baseline**

Review `1246345e526190de89618ce4b301c6f34cc90e21..HEAD` for spec compliance, concurrency safety, fail-open behavior, license provenance, test quality, and repository hygiene. Fix every Critical/Important finding with focused tests and re-review.

- [ ] **Step 2: Re-run all mandatory gates after final fixes**

```bash
swift run SlidrFreeCoreChecks
swift test
swift build
bash scripts/package-release.sh
bash scripts/verify-release.sh
/Users/zhupin/.codex/hooks/secret-scan.sh README.md README.zh-CN.md docs scripts
git diff --check 1246345e526190de89618ce4b301c6f34cc90e21..HEAD
```

- [ ] **Step 3: Confirm commit scope and identity**

```bash
git status --short --branch
git log --oneline --decorate 1246345e526190de89618ce4b301c6f34cc90e21..HEAD
git config user.email
```

Expected: clean worktree; intentional commits only; email `288487787+zzp209@users.noreply.github.com`.

- [ ] **Step 4: Push the implementation branch**

Push the current `codex/` branch to `https://github.com/YuriGao/slidr-free.git` without force.

- [ ] **Step 5: Open a ready-for-review PR**

Target `main`. Include scope, architecture, exact limitations, automated test output, packaging/license verification, manual beta matrix status, TCC note, rollback baseline, and provenance statement. Do not merge or create a GitHub Release without separate authorization.
