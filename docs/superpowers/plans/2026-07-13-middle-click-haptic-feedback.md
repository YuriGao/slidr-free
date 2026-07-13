# Middle-click Haptic Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `dispatching-parallel-agents` when tasks are genuinely independent; otherwise use `executing-plans`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable, best-effort AppKit haptic confirmation exactly once after a successful Tap or physical middle click.

**Architecture:** Persist a default-on `hapticFeedbackEnabled` preference, isolate AppKit behind an injectable `MiddleClickHapticFeedbackPerforming`, and inject one production instance into the synthetic Tap emitter and physical Event Tap. Feedback always queues to the main thread and reads the latest setting when the queued closure runs; the input pipeline restart predicate excludes haptic-only changes.

**Tech Stack:** Swift 5.9, SwiftPM, AppKit `NSHapticFeedbackManager`, CoreGraphics Event Tap, SwiftUI, XCTest.

## Global Constraints

- Deployment target remains macOS 13; add no package dependency or permission.
- Use only public AppKit for haptics: `.generic` with `.now`, fetched from `defaultPerformer` per request.
- Tap feedback occurs only after both synthetic center-button events are posted.
- Physical feedback occurs only after the first matching Up is successfully transformed.
- Recognition, failure, cancellation, recovery, teardown, and compensating Up produce no feedback.
- Feedback is best-effort and must not affect middle-click success, pipeline state, or error reporting.
- `hapticFeedbackEnabled` defaults to `true`, missing fields migrate to `true`, and explicit `false` round-trips.
- Toggling only haptic feedback must not quiesce or restart the touch monitor/Event Tap.
- Do not inspect or reuse upstream MiddleClick source, resources, project files, or build artifacts.

---

## File map

- `Sources/SlidrFreeCore/MiddleClickSettings.swift`: persisted setting and migration default.
- `Sources/SlidrFreeCoreChecks/main.swift`: executable migration/default gate.
- `Sources/SlidrFreeApp/MiddleClickHapticFeedback.swift`: public-AppKit boundary, main-queue delivery, latest-setting check.
- `Sources/SlidrFreeApp/MiddleClickEmitter.swift`: Tap success boundary only.
- `Sources/SlidrFreeApp/MouseButtonEventTap.swift`: physical transformed-Up success boundary only.
- `Sources/SlidrFreeApp/InputPipelineStatus.swift`: physical feedback dependency plumbing and restart semantics.
- `Sources/SlidrFreeApp/AppDelegate.swift`: owns and injects the single production haptic instance.
- `Sources/SlidrFreeApp/SettingsView.swift`: default-on middle-click haptic Toggle.
- `Resources/{en,zh-Hans}.lproj/Localizable.strings`: bilingual labels/help.
- `README.md`, `README.zh-CN.md`, `docs/middle-click-provenance.md`: behavior, limitations, and provenance.
- `Tests/SlidrFreeCoreTests/AppSettingsMigrationTests.swift`: core migration and round-trip.
- `Tests/SlidrFreeAppTests/SettingsStoreMigrationTests.swift`: stored legacy payload migration.
- `Tests/SlidrFreeAppTests/MiddleClickHapticFeedbackTests.swift`: scheduling/latest-setting behavior.
- `Tests/SlidrFreeAppTests/MiddleClickEmitterTests.swift`: Tap success/failure feedback boundary.
- `Tests/SlidrFreeAppTests/MouseButtonEventTapTests.swift`: physical exact-once and recovery exclusions.
- `Tests/SlidrFreeAppTests/ProductionInputPipelineTests.swift`: production dependency wiring.
- `Tests/SlidrFreeAppTests/InputPipelineLifecycleTests.swift`: haptic-only changes do not restart.

---

### Task 1: Persist and migrate the haptic preference

**Files:**
- Modify: `Tests/SlidrFreeCoreTests/AppSettingsMigrationTests.swift`
- Modify: `Tests/SlidrFreeAppTests/SettingsStoreMigrationTests.swift`
- Modify: `Sources/SlidrFreeCore/MiddleClickSettings.swift`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

**Interfaces:**
- Produces: `MiddleClickSettings.hapticFeedbackEnabled: Bool` and initializer parameter `hapticFeedbackEnabled: Bool = true`.
- Consumes: existing `MiddleClickSettings` Codable and `.default` behavior.

- [ ] **Step 1: Write failing migration tests**

Add core tests that require the full default and old payloads without the field to use `true`, and explicit `false` to round-trip:

```swift
func testMiddleClickHapticFeedbackDefaultsOnAndMissingFieldMigratesOn() throws {
    XCTAssertTrue(MiddleClickSettings.default.hapticFeedbackEnabled)
    let decoded = try decodeSettings(middleClickJSON: #"{"isEnabled":true,"tapEnabled":true,"fingerCount":4}"#)
    XCTAssertTrue(decoded.middleClick.hapticFeedbackEnabled)
}

func testMiddleClickHapticFeedbackDisabledRoundTrips() throws {
    let original = MiddleClickSettings(
        isEnabled: true,
        tapEnabled: true,
        fingerCount: 4,
        hapticFeedbackEnabled: false
    )
    let data = try JSONEncoder().encode(original)
    XCTAssertEqual(try JSONDecoder().decode(MiddleClickSettings.self, from: data), original)
}
```

Extend `SettingsStoreMigrationTests.testV02PayloadPreservesEveryFieldAndRoundTripsWithMiddleClickDefaults` with `XCTAssertTrue(store.settings.middleClick.hapticFeedbackEnabled)`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter AppSettingsMigrationTests
swift test --filter SettingsStoreMigrationTests
```

Expected: compile failure because `hapticFeedbackEnabled` does not exist.

- [ ] **Step 3: Implement the persisted field**

Extend `MiddleClickSettings`:

```swift
public var hapticFeedbackEnabled: Bool

public static let `default` = Self(
    isEnabled: false,
    tapEnabled: true,
    fingerCount: defaultFingerCount,
    hapticFeedbackEnabled: true
)

private enum CodingKeys: String, CodingKey {
    case isEnabled, tapEnabled, fingerCount, hapticFeedbackEnabled
}

public init(
    isEnabled: Bool,
    tapEnabled: Bool,
    fingerCount: Int = 4,
    hapticFeedbackEnabled: Bool = true
) {
    self.isEnabled = isEnabled
    self.tapEnabled = tapEnabled
    self.fingerCount = Self.validatedFingerCount(fingerCount)
    self.hapticFeedbackEnabled = hapticFeedbackEnabled
}
```

Decode the field with:

```swift
hapticFeedbackEnabled: try container.decodeIfPresent(
    Bool.self,
    forKey: .hapticFeedbackEnabled
) ?? Self.default.hapticFeedbackEnabled
```

Add a `SlidrFreeCoreChecks` assertion that the default is enabled and the legacy missing-middle-click payload still decodes to `.default`.

- [ ] **Step 4: Run tests and core checks and verify GREEN**

Run:

```bash
swift test --filter AppSettingsMigrationTests
swift test --filter SettingsStoreMigrationTests
swift run SlidrFreeCoreChecks
```

Expected: all selected tests and checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SlidrFreeCore/MiddleClickSettings.swift Sources/SlidrFreeCoreChecks/main.swift Tests/SlidrFreeCoreTests/AppSettingsMigrationTests.swift Tests/SlidrFreeAppTests/SettingsStoreMigrationTests.swift
git commit -m "feat: persist middle-click haptic preference"
```

---

### Task 2: Add the testable public-AppKit haptic boundary

**Files:**
- Create: `Tests/SlidrFreeAppTests/MiddleClickHapticFeedbackTests.swift`
- Create: `Sources/SlidrFreeApp/MiddleClickHapticFeedback.swift`

**Interfaces:**
- Consumes: `isEnabled: () -> Bool`, injected main scheduler, and injected AppKit performer closure.
- Produces: `MiddleClickHapticFeedbackPerforming.performSuccess()` and `AppKitMiddleClickHapticFeedback`.

- [ ] **Step 1: Write failing scheduler/latest-value tests**

```swift
final class MiddleClickHapticFeedbackTests: XCTestCase {
    func testAlwaysQueuesAndReadsLatestEnabledValueAtDeliveryTime() {
        var enabled = true
        var queued: [() -> Void] = []
        var performCount = 0
        let feedback = AppKitMiddleClickHapticFeedback(
            isEnabled: { enabled },
            deliverOnMain: { queued.append($0) },
            perform: { performCount += 1 }
        )

        feedback.performSuccess()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(performCount, 0)
        enabled = false
        queued.removeFirst()()
        XCTAssertEqual(performCount, 0)

        enabled = true
        feedback.performSuccess()
        queued.removeFirst()()
        XCTAssertEqual(performCount, 1)
    }
}
```

- [ ] **Step 2: Run test and verify RED**

Run: `swift test --filter MiddleClickHapticFeedbackTests`

Expected: compile failure because the protocol and production class do not exist.

- [ ] **Step 3: Implement the boundary**

Create:

```swift
import AppKit

protocol MiddleClickHapticFeedbackPerforming: AnyObject {
    func performSuccess()
}

final class AppKitMiddleClickHapticFeedback: MiddleClickHapticFeedbackPerforming {
    private let isEnabled: () -> Bool
    private let deliverOnMain: (@escaping () -> Void) -> Void
    private let perform: () -> Void

    init(
        isEnabled: @escaping () -> Bool,
        deliverOnMain: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        },
        perform: @escaping () -> Void = {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    ) {
        self.isEnabled = isEnabled
        self.deliverOnMain = deliverOnMain
        self.perform = perform
    }

    func performSuccess() {
        deliverOnMain { [isEnabled, perform] in
            guard isEnabled() else { return }
            perform()
        }
    }
}
```

- [ ] **Step 4: Run test and verify GREEN**

Run: `swift test --filter MiddleClickHapticFeedbackTests`

Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/SlidrFreeApp/MiddleClickHapticFeedback.swift Tests/SlidrFreeAppTests/MiddleClickHapticFeedbackTests.swift
git commit -m "feat: add middle-click haptic boundary"
```

---

### Task 3: Trigger feedback only after successful synthetic Tap posting

**Files:**
- Modify: `Tests/SlidrFreeAppTests/MiddleClickEmitterTests.swift`
- Modify: `Sources/SlidrFreeApp/MiddleClickEmitter.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `MiddleClickHapticFeedbackPerforming.performSuccess()` from Task 2.
- Produces: `MiddleClickEmitter.init(eventSource:marker:hapticFeedback:)` with an optional injected performer.

- [ ] **Step 1: Write failing Tap boundary tests**

Add a spy and require success once, all creation failures zero, and compensating release zero:

```swift
private final class HapticFeedbackSpy: MiddleClickHapticFeedbackPerforming {
    let onPerform: () -> Void
    var performCount = 0

    init(onPerform: @escaping () -> Void = {}) {
        self.onPerform = onPerform
    }

    func performSuccess() {
        performCount += 1
        onPerform()
    }
}
```

In the existing success test, construct `HapticFeedbackSpy { source.log.append("haptic") }`, inject it into the emitter, and assert `source.log.suffix(3) == ["post-down", "post-up", "haptic"]` plus `performCount == 1`. In each pointer/Down/Up creation failure test, inject a spy and assert `performCount == 0`. In the pending-release test, inject a spy and assert `performCount == 0` after `emitRelease`.

- [ ] **Step 2: Run test and verify RED**

Run: `swift test --filter MiddleClickEmitterTests`

Expected: compile failure because `MiddleClickEmitter` does not accept `hapticFeedback`.

- [ ] **Step 3: Implement minimal Tap integration**

Add this optional dependency to `MiddleClickEmitter`:

```swift
private let hapticFeedback: (any MiddleClickHapticFeedbackPerforming)?

init(
    eventSource: any MiddleClickEventSource = QuartzMiddleClickEventSource(),
    marker: Int64 = MiddleClickEventIdentity.marker,
    hapticFeedback: (any MiddleClickHapticFeedbackPerforming)? = nil
) {
    self.eventSource = eventSource
    self.marker = marker
    self.hapticFeedback = hapticFeedback
}
```

After `down.post()` and `up.post()`, call `hapticFeedback?.performSuccess()` before returning `.success`. Do not call it from `emitRelease`.

In `AppDelegate`, create lazy production dependencies so the latest stored setting is read:

```swift
private lazy var middleClickHapticFeedback = AppKitMiddleClickHapticFeedback(
    isEnabled: { [weak self] in
        self?.settingsStore.settings.middleClick.hapticFeedbackEnabled ?? false
    }
)
private lazy var systemControl = SystemControl(
    middleClickEmitter: MiddleClickEmitter(hapticFeedback: middleClickHapticFeedback)
)
```

Remove the old eager `private let systemControl = SystemControl()`.

- [ ] **Step 4: Run tests and build and verify GREEN**

Run:

```bash
swift test --filter MiddleClickEmitterTests
swift test --filter SystemControlMiddleClickTests
swift build
```

Expected: selected tests and build pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SlidrFreeApp/MiddleClickEmitter.swift Sources/SlidrFreeApp/AppDelegate.swift Tests/SlidrFreeAppTests/MiddleClickEmitterTests.swift
git commit -m "feat: confirm successful middle-click taps"
```

---

### Task 4: Trigger feedback once after a successful physical Up transformation

**Files:**
- Modify: `Tests/SlidrFreeAppTests/MouseButtonEventTapTests.swift`
- Modify: `Tests/SlidrFreeAppTests/ProductionInputPipelineTests.swift`
- Modify: `Sources/SlidrFreeApp/MouseButtonEventTap.swift`
- Modify: `Sources/SlidrFreeApp/InputPipelineStatus.swift`
- Modify: `Sources/SlidrFreeApp/AppDelegate.swift`

**Interfaces:**
- Consumes: the shared `MiddleClickHapticFeedbackPerforming` instance.
- Produces: optional haptic dependency plumbing from `ProductionInputPipelineFactory` through `MouseButtonEventTapContext`.

- [ ] **Step 1: Write failing physical exact-once tests**

Add this test to `MouseButtonEventTapTests` using a shared `MiddleClickHapticFeedbackSpy`:

```swift
func testPhysicalMiddleClickPerformsHapticOnlyAfterFirstTransformedUp() throws {
    let bridge = MiddleClickSessionBridge(generation: 1, now: { 10 })
    bridge.applyTouchUpdate(.init(
        sessionID: 7,
        chordActive: true,
        tapCandidate: false,
        generation: 1,
        sequence: 1,
        receivedAt: 10,
        terminalReason: nil
    ))
    let feedback = MiddleClickHapticFeedbackSpy()
    let context = MouseButtonEventTapContext(
        reducer: .init(bridge: bridge, generation: 1, ownMarker: MiddleClickEventIdentity.marker),
        releaseHandler: { _ in },
        statusHandler: { _ in },
        hapticFeedback: feedback
    )

    let down = try mouseEvent(button: 0, number: 42)
    _ = context.handle(type: .leftMouseDown, event: down)
    XCTAssertEqual(feedback.performCount, 0)

    let dragged = try mouseEvent(button: 0, number: 42)
    _ = context.handle(type: .leftMouseDragged, event: dragged)
    XCTAssertEqual(feedback.performCount, 0)

    let up = try mouseEvent(button: 0, number: 42)
    _ = context.handle(type: .leftMouseUp, event: up)
    XCTAssertEqual(feedback.performCount, 1)

    let duplicateUp = try mouseEvent(button: 0, number: 42)
    _ = context.handle(type: .leftMouseUp, event: duplicateUp)
    XCTAssertEqual(feedback.performCount, 1)
}
```

Implement the private test helper with `CGEvent(source: nil)`, `.mouseEventButtonNumber`, and `.mouseEventNumber`. Add a second test that injects the spy into the existing tap-disabled recovery context and asserts the synthetic pending release leaves `performCount == 0`; also pass an own-marker event and assert zero.

Extend `ProductionInputPipelineTests` with a spy Event Tap factory that records the received haptic instance. After sequential 1→4 placement, reduce matching Down and Up through the retained reducer/context and assert the injected feedback spy reaches one call. This verifies the dependency reaches the production pipeline rather than only a directly constructed context.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter MouseButtonEventTapTests
swift test --filter ProductionInputPipelineTests
```

Expected: compile failure because Event Tap types do not accept the haptic dependency.

- [ ] **Step 3: Implement the physical success boundary**

Add optional `hapticFeedback: (any MiddleClickHapticFeedbackPerforming)? = nil` parameters to `MouseButtonEventTap` and `MouseButtonEventTapContext`; store it only on the context. Split this switch branch:

```swift
case .passUnchanged:
    return Unmanaged.passUnretained(event)
case .transform(let transform):
    guard let output = MouseButtonEventFactory.event(for: decision, original: event) else {
        return Unmanaged.passUnretained(event)
    }
    if transform.kind == .up {
        hapticFeedback?.performSuccess()
    }
    return Unmanaged.passUnretained(output)
```

Do not invoke feedback in reducer, bridge, release handler, recovery, or quiesce.

Use this exact factory signature:

```swift
typealias InputEventTapFactory = (
    MouseButtonEventReducer,
    any MiddleClickReleaseEmitting,
    (any MiddleClickHapticFeedbackPerforming)?,
    @escaping (MouseButtonEventTapStatus) -> Void
) -> any InputEventTapLifecycle
```

Add `hapticFeedback: (any MiddleClickHapticFeedbackPerforming)? = nil` to `ProductionInputPipeline.init`, store it, and pass it as the third Event Tap factory argument. Add a required haptic dependency to `ProductionInputPipelineFactory`:

```swift
init(
    hapticFeedback: any MiddleClickHapticFeedbackPerforming,
    actionHandler: @escaping (RecognizedGesture) -> Void
) {
    self.hapticFeedback = hapticFeedback
    self.actionHandler = actionHandler
}
```

The factory passes it to each `ProductionInputPipeline`. Inject `middleClickHapticFeedback` when `AppDelegate` creates `ProductionInputPipelineFactory`, and update test factories to accept or ignore the new third argument explicitly.

- [ ] **Step 4: Run physical tests and verify GREEN**

Run:

```bash
swift test --filter MouseButtonEventTapTests
swift test --filter ProductionInputPipelineTests
swift test --filter MouseButtonEventReducerTests
```

Expected: all selected tests pass; duplicate Up and recovery remain zero-feedback.

- [ ] **Step 5: Commit**

```bash
git add Sources/SlidrFreeApp/MouseButtonEventTap.swift Sources/SlidrFreeApp/InputPipelineStatus.swift Sources/SlidrFreeApp/AppDelegate.swift Tests/SlidrFreeAppTests/MouseButtonEventTapTests.swift Tests/SlidrFreeAppTests/ProductionInputPipelineTests.swift
git commit -m "feat: confirm successful physical middle clicks"
```

---

### Task 5: Make the switch live without restarting the input pipeline

**Files:**
- Modify: `Tests/SlidrFreeAppTests/InputPipelineLifecycleTests.swift`
- Modify: `Sources/SlidrFreeApp/InputPipelineStatus.swift`

**Interfaces:**
- Consumes: `MiddleClickSettings.hapticFeedbackEnabled` from Task 1.
- Produces: validated, recognition-only pipeline restart comparison.

- [ ] **Step 1: Write the failing no-restart lifecycle test**

```swift
func testHapticPreferenceChangeDoesNotRestartOrReleasePendingPhysicalClick() {
    let harness = Harness()
    var settings = enabledSettings()
    harness.coordinator.update(settings: settings, permission: .granted)
    let first = harness.factory.last!
    first.hasPending = true

    settings.middleClick.hapticFeedbackEnabled = false
    harness.coordinator.update(settings: settings, permission: .granted)

    XCTAssertEqual(harness.factory.instances.count, 1)
    XCTAssertFalse(first.didQuiesce)
    XCTAssertEqual(first.releaseCount, 0)
    XCTAssertEqual(first.edgeUpdates, 1)
}
```

- [ ] **Step 2: Run test and verify RED**

Run: `swift test --filter InputPipelineLifecycleTests/testHapticPreferenceChangeDoesNotRestartOrReleasePendingPhysicalClick`

Expected: failure because the current whole-`MiddleClickSettings` comparison restarts the pipeline.

- [ ] **Step 3: Narrow the restart comparison using validated settings**

In `updateLocked`, compute and store one validated value:

```swift
let previous = settings
let validated = newSettings.validated()
settings = validated
permission = newPermission
```

Compare `previous` with `validated` using:

```swift
let semanticChange = previous.map {
    $0.isAppEnabled != validated.isAppEnabled
        || $0.middleClick.isEnabled != validated.middleClick.isEnabled
        || $0.middleClick.tapEnabled != validated.middleClick.tapEnabled
        || $0.middleClick.fingerCount != validated.middleClick.fingerCount
} ?? true
```

Use `validated` for the eligibility check and live edge update in this call.

- [ ] **Step 4: Run lifecycle tests and verify GREEN**

Run: `swift test --filter InputPipelineLifecycleTests`

Expected: all lifecycle tests pass, including existing restart tests for Tap and finger count.

- [ ] **Step 5: Commit**

```bash
git add Sources/SlidrFreeApp/InputPipelineStatus.swift Tests/SlidrFreeAppTests/InputPipelineLifecycleTests.swift
git commit -m "fix: keep haptic preference changes live"
```

---

### Task 6: Add Settings UI, bilingual copy, and provenance

**Files:**
- Modify: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/middle-click-provenance.md`

**Interfaces:**
- Consumes: `MiddleClickSettings.hapticFeedbackEnabled`.
- Produces: discoverable default-on settings control and documented best-effort behavior.

- [ ] **Step 1: Add the Toggle and help text**

Insert after “Enable Tap”:

```swift
Toggle(
    NSLocalizedString("middle_click_haptic_feedback", comment: ""),
    isOn: binding(\.middleClick.hapticFeedbackEnabled)
)
.disabled(!store.settings.middleClick.isEnabled)
```

Add caption text using `middle_click_haptic_feedback_help` after the exact-count help.

- [ ] **Step 2: Add exact bilingual localization**

English:

```text
"middle_click_haptic_feedback" = "Haptic feedback on success";
"middle_click_haptic_feedback_help" = "Feedback is requested only after Slidr Free submits a middle click. macOS may suppress it depending on the trackpad and system settings.";
```

Simplified Chinese:

```text
"middle_click_haptic_feedback" = "成功时触感反馈";
"middle_click_haptic_feedback_help" = "仅在 Slidr-Free 成功提交中键点击后请求反馈；macOS 可能根据触控板和系统设置抑制反馈。";
```

- [ ] **Step 3: Update user documentation and provenance**

State in both READMEs that success feedback defaults on, can be disabled without restarting the input pipeline, uses public AppKit, and may be suppressed. Add the haptic extension and independent review role to `docs/middle-click-provenance.md`; record that no upstream source or assets were used.

- [ ] **Step 4: Build and run localization/static checks**

Run:

```bash
swift build
plutil -lint Resources/en.lproj/Localizable.strings
plutil -lint Resources/zh-Hans.lproj/Localizable.strings
git diff --check
```

Expected: build passes, both string files report `OK`, and diff check is clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/SlidrFreeApp/SettingsView.swift Resources/en.lproj/Localizable.strings Resources/zh-Hans.lproj/Localizable.strings README.md README.zh-CN.md docs/middle-click-provenance.md
git commit -m "docs: expose middle-click haptic feedback"
```

---

### Task 7: Complete verification, review, and GitHub submission

**Files:**
- Review: all changes since `6a576f0`
- Generated: `release/Slidr-Free.app`, `release/Slidr-Free.app.zip`

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: verified branch and focused stacked GitHub pull request.

- [ ] **Step 1: Run full automated verification**

```bash
swift run SlidrFreeCoreChecks
swift test
swift build
bash scripts/package-release.sh
bash scripts/verify-release.sh
bash scripts/test-verify-release-signature.sh
git diff --check
```

Expected: core checks pass; every XCTest passes; debug/release builds succeed; loose and archived app signatures verify as ad-hoc; verifier self-test passes.

- [ ] **Step 2: Run scoped secret and repository hygiene checks**

```bash
/Users/zhupin/.codex/hooks/secret-scan.sh Sources Tests Resources README.md README.zh-CN.md docs
git status --short --branch
git log --format='%h %an <%ae> %s' 1fc34cf..HEAD
```

Expected: secret scan returns zero; only intended files/ignored release artifacts appear; every new commit uses `zhupin <288487787+zzp209@users.noreply.github.com>`.

- [ ] **Step 3: Perform independent specification/code review**

Review for: exact success boundaries, zero-feedback exclusions, Event Tap callback latency, main-queue AppKit access, latest-setting read, lifecycle non-restart, migration compatibility, README/provenance completeness, and no upstream implementation reuse. Fix every Critical or Important finding and rerun affected plus full tests.

- [ ] **Step 4: Push the branch**

```bash
git push -u origin codex/middleclick-haptic-feedback
```

Expected: push succeeds and remote tracks the branch.

- [ ] **Step 5: Create the focused stacked pull request**

While PR #3 remains open, create the PR with base `codex/middleclick-integration` so the haptic diff excludes the sequential-placement bugfix:

```bash
gh pr create \
  --repo YuriGao/slidr-free \
  --base codex/middleclick-integration \
  --head codex/middleclick-haptic-feedback \
  --title "feat: add middle-click haptic feedback" \
  --body-file /tmp/slidr-middle-click-haptic-pr.md
```

The PR body must summarize behavior, compatibility limits, exact automated verification, manual hardware validation status, and dependency on PR #3. Expected: a ready, non-draft PR URL.

- [ ] **Step 6: Verify GitHub checks**

```bash
gh pr checks --repo YuriGao/slidr-free --watch <PR_NUMBER>
gh pr view --repo YuriGao/slidr-free <PR_NUMBER> --json state,isDraft,mergeStateStatus,statusCheckRollup,url
```

Expected: CI succeeds; PR is OPEN, non-draft, and has no unresolved failing check.
