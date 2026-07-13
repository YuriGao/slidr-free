# Middle-click haptic feedback design

**Date:** 2026-07-13  
**Status:** Ready for user review  
**Repository:** `YuriGao/slidr-free`  
**Depends on:** configurable 2–4 finger middle click and the sequential-placement fix at `1fc34cf`

## 1. Goal

Add restrained trackpad haptic confirmation to the middle-click feature without changing recognition, event-delivery, permission, or failure behavior.

The user experience is:

- one generic haptic request for each middle click that Slidr Free successfully submits or transforms;
- no haptic request for recognition alone, invalid or cancelled sessions, ordinary mouse clicks, recovery, teardown, or compensating releases;
- a settings switch named “Haptic feedback on success”, enabled by default;
- disabling the switch takes effect immediately and does not restart the touch monitor or mouse Event Tap.

## 2. Non-goals

- Guaranteeing that every haptic request produces a perceptible vibration. AppKit and the system retain final control.
- Detecting whether the target application acted on the middle-click event. Quartz provides no such acknowledgement.
- Adding a gesture-ready pulse while the selected fingers are merely resting on the trackpad.
- Emitting separate recognition and completion pulses.
- Driving the trackpad through private actuator, IOKit, MultitouchSupport, Core Haptics, or device-specific APIs.
- Changing Tap duration, movement thresholds, finger-count rules, physical click transformation, or permissions.

## 3. Success definition

“Success” means Slidr Free has crossed its last locally observable delivery boundary:

- **Tap:** both synthetic center-button Down and Up events were created, configured, and posted. The haptic callback runs only after both posts.
- **Physical press:** the matching source Mouse Up was accepted by the active middle-click session and successfully converted to center-button `otherMouseUp`. The callback is scheduled only for that transformed Up.

This definition does not claim that a browser or another target application consumed the event.

## 4. Interaction contract

### 4.1 Pattern and timing

Use:

```swift
NSHapticFeedbackManager.defaultPerformer.perform(
    .generic,
    performanceTime: .now
)
```

`.generic` matches a neutral action confirmation. `.alignment` describes alignment guides, while `.levelChange` describes discrete pressure levels and remains appropriate for Slidr Free's existing volume, brightness, and tab-step behavior.

The performer must be requested at execution time rather than cached because the active input device, accessibility choices, and user preferences can change while the app is running.

### 4.2 Exactly-once behavior

- Tap success requests one haptic after the synthetic pair is posted.
- Physical Down and Drag request no haptic.
- The first valid transformed physical Up requests one haptic.
- A duplicate Up passes unchanged because the bridge has already consumed the session, so it requests no second haptic.
- Slidr Free's tagged synthetic Tap events pass through the Event Tap unchanged and cannot trigger the physical feedback path.
- A session can be claimed by Tap or physical click, not both.

### 4.3 Failure and cancellation

No feedback is requested when:

- pointer location, Down creation, or Up creation fails;
- the selected finger chord never qualifies or becomes invalid;
- Tap is disabled;
- the mouse event is unrelated, stale, duplicated, or tagged as Slidr Free's own event;
- an Event Tap timeout or user-input disable occurs;
- the pipeline quiesces, permissions are lost, the system sleeps, or the app terminates;
- a synthetic Up is emitted only to release a pending physical Down.

Haptic suppression or unsupported hardware must never change the middle-click result, pipeline status, or error state.

## 5. Platform boundary

Use the public AppKit `NSHapticFeedbackManager` API. It is available before the project's macOS 13 deployment target and requires no additional TCC permission.

The API is best-effort and returns no delivery result. The system may suppress feedback based on the active input device, system settings, accessibility preferences, or lack of current trackpad contact. This is especially relevant to Tap because the recognizer confirms Tap only after all fingers lift. Slidr Free will not issue an earlier, semantically misleading “success” pulse to work around suppression.

Unsupported hardware, mouse-only input, or disabled system haptics must degrade silently while middle click continues to work.

## 6. Architecture

### 6.1 Persisted setting

Extend `MiddleClickSettings` with:

```swift
public var hapticFeedbackEnabled: Bool
```

Rules:

- default: `true`;
- missing JSON field: decode as `true` so existing users receive the requested behavior;
- explicit `false`: round-trips unchanged;
- the setting is disabled in the UI when middle click itself is disabled, but its stored value is preserved.

### 6.2 Haptic boundary

Add this injectable app-layer abstraction:

```swift
protocol MiddleClickHapticFeedbackPerforming: AnyObject {
    func performSuccess()
}
```

`AppKitMiddleClickHapticFeedback` is the production implementation. It receives injected `isEnabled`, `deliverOnMain`, and `perform` closures so its delivery semantics are independently testable. The production `perform` closure fetches `NSHapticFeedbackManager.defaultPerformer` and calls `.generic` with `.now`.

`performSuccess()`:

- accepts calls from either the main thread or the Event Tap thread;
- always enqueues one closure onto the main queue so an Event Tap callback can return first;
- checks the latest `hapticFeedbackEnabled` value only when that main-queue closure executes;
- fetches `NSHapticFeedbackManager.defaultPerformer` for every request;
- performs `.generic` with `.now`;
- provides no failure callback because AppKit provides no feedback result.

Tests inject a spy `MiddleClickHapticFeedbackPerforming` at success boundaries and deterministic closures into `AppKitMiddleClickHapticFeedback` itself.

### 6.3 Tap delivery path

Keep `MiddleClickRecognizer`, `MiddleClickSessionBridge`, and `ActionDispatcher` free of AppKit effects.

Give `MiddleClickEmitter` an optional injected `MiddleClickHapticFeedbackPerforming`. `emitClick()` invokes `performSuccess()` exactly once after posting Down and Up, immediately before returning `.success`. Every early failure returns without invoking it. `emitRelease(eventNumber:)` never invokes it.

`AppDelegate` owns one `AppKitMiddleClickHapticFeedback` instance and injects it into the `MiddleClickEmitter` used by `SystemControl`.

### 6.4 Physical click path

Pass the same `MiddleClickHapticFeedbackPerforming` instance through:

```text
AppDelegate
  -> ProductionInputPipelineFactory
  -> ProductionInputPipeline
  -> MouseButtonEventTap
  -> MouseButtonEventTapContext
```

`MouseButtonEventTapContext.handle` separates `.transform` from `.passUnchanged`. After the factory successfully produces the transformed event, it invokes `performSuccess()` only when `transform.kind == .up`. The injected implementation enqueues the actual work onto the main queue, keeping the Event Tap callback short and avoiding AppKit work on its dedicated run-loop thread.

Recovery and pending-release callbacks remain separate and never invoke haptics.

### 6.5 Setting changes without pipeline restart

The current coordinator restarts when any `MiddleClickSettings` field changes. First validate `newSettings`, store that validated value, and compare the previous value with the same validated value. Narrow the restart predicate so a restart occurs only when the input semantics change:

- `isAppEnabled`;
- `middleClick.isEnabled`;
- `middleClick.tapEnabled`;
- `middleClick.fingerCount`.

A change only to `hapticFeedbackEnabled` must keep the current generation, touch monitor, bridge, and Event Tap alive. The haptic boundary reads the latest setting at delivery time, so the switch does not need to be copied into a pipeline generation.

Unrelated edge settings continue through the existing live-update path.

## 7. Settings UI and copy

Add one Toggle in the Middle Click section after “Enable tap” and before the finger-count picker:

- English: `Haptic feedback on success`
- Simplified Chinese: `成功时触感反馈`

Add concise help copy near the existing exact-count help:

- English: `Feedback is requested only after Slidr Free submits a middle click. macOS may suppress it depending on the trackpad and system settings.`
- Simplified Chinese: `仅在 Slidr-Free 成功提交中键点击后请求反馈；macOS 可能根据触控板和系统设置抑制反馈。`

Do not add a runtime “haptic available” status because AppKit exposes neither capability detection nor delivery acknowledgement.

Update `README.md` and `README.zh-CN.md` to state that success feedback is enabled by default, can be disabled, and remains best-effort under AppKit. Update the local provenance record to identify this as a native Slidr Free extension using the public AppKit haptic API; no upstream MiddleClick implementation material is involved.

## 8. Test plan

### 8.1 Settings and migration

- the complete default enables haptic feedback;
- settings payloads without the new field migrate to enabled;
- explicit disabled values decode and round-trip;
- existing settings fields remain unchanged.

### 8.2 Tap path

- successful synthetic Down/Up posting invokes the callback once and after both posts;
- pointer, Down creation, and Up creation failures invoke it zero times;
- `emitRelease` invokes it zero times.

### 8.3 Physical path

- qualifying Down and Drag invoke zero callbacks;
- the matching transformed Up invokes one callback;
- duplicate Up, ordinary click, stale session, own-marker event, cancellation, Event Tap recovery, quiesce, and compensating Up invoke zero callbacks;
- a Tap-generated tagged Down/Up pair cannot cause a second physical callback.

### 8.4 Haptic boundary

- enabled requests call the performer once;
- disabled requests call it zero times;
- a request arriving off-main is delivered through the injected main scheduler;
- the enablement closure is evaluated at delivery time, not captured as a stale pipeline value.

### 8.5 Lifecycle regression

- toggling only haptic feedback does not quiesce or replace the active pipeline;
- recognition-affecting middle-click fields still quiesce and create a new generation;
- all existing middle-click, edge-gesture, permission, sleep/wake, packaging, and release checks continue to pass.

### 8.6 Manual hardware acceptance

On the currently installed app and trackpad:

1. Enable four-finger middle click and success haptics.
2. Four-finger Tap a browser link; verify the link opens in a background tab and at most one confirmation pulse is perceived.
3. Four-finger physical-click a browser link; verify background-tab opening and at most one additional confirmation pulse.
4. Disable success haptics without restarting the app; repeat both actions and verify middle click still works with no app-requested pulse.
5. Re-enable the switch; verify behavior resumes without restarting the touch monitor or Event Tap.

Tap feedback is accepted as best-effort if macOS suppresses the request after finger release. A future “gesture ready” pulse requires a separate design decision because it changes the meaning of feedback.

## 9. Verification and delivery

Required automated gates:

```bash
swift run SlidrFreeCoreChecks
swift test
swift build
bash scripts/package-release.sh
bash scripts/verify-release.sh
bash scripts/test-verify-release-signature.sh
git diff --check
```

Run the repository secret scan before pushing. Package and install only after automated gates pass. Because replacing the ad-hoc signed app can change its code identity, re-check Accessibility authorization after local installation.

The implementation branch is based on the open sequential-placement fix PR. Keep the haptic change as a separate stacked pull request while that fix remains open; do not broaden or rewrite the existing bug-fix PR.

## 10. Acceptance criteria

- The setting defaults to enabled, persists, and can be disabled without an input-pipeline restart.
- Tap success requests exactly one generic haptic after successful event posting.
- Physical click success requests exactly one generic haptic after the matching transformed Up.
- No failure, cancellation, recovery, teardown, or compensating path requests feedback.
- Haptic capability or suppression never breaks middle click.
- No new permission, private haptic API, or target-application assumption is introduced.
- Automated verification passes, the packaged app is signature-verified, and the change is submitted to GitHub as a focused pull request.
