# Slidr Free Middle-Click Integration Design

**Date:** 2026-07-12

**Status:** Approved for implementation planning after review revision

**Target:** Submit an implementation PR for v0.3.0 beta

**Slidr Free baseline:** `main@1246345e526190de89618ce4b301c6f34cc90e21`

**Behavior reference snapshot:** `artginzburg/MiddleClick@21234476a51d58b87c4b8d6fdd7b49ce49147c8d`

## 1. Summary

Slidr Free will add opt-in, exact-three-finger middle-click behavior for the single default multitouch device already monitored by the app. The feature supports:

1. **Three-finger tap:** a short stationary three-finger session emits one middle-button down/up pair at the current pointer location.
2. **Three-finger physical click:** a real left- or right-button down/drag/up stream that begins while a fresh three-finger chord is active is transformed into a coherent middle-button stream.

The implementation reuses Slidr Free's existing SwiftPM structure, private-framework bridge, settings, menu-bar app, permission flow, action dispatch, packaging, and CI. It does not import, copy, translate, link, or adapt source or build artifacts from MiddleClick.

The v0.3 scope is deliberately narrow: exact three fingers, the current default multitouch device, no per-application exclusions, and no promise that a physical Click originated from the touch device rather than another system mouse source.

## 2. Goals

- Deliver reliable three-finger Tap and physical Click middle-button behavior.
- Preserve existing single-finger volume, brightness, and browser-tab gestures.
- Suppress edge gestures from the first observed multi-touch frame until all touches lift.
- Guarantee Tap and physical Click are mutually exclusive within one touch session.
- Guarantee every transformed middle-button Down is released at most once.
- Fail open when touch state is stale, the Event Tap is unavailable, or lifecycle teardown starts.
- Preserve all v0.2 settings while adding middle-click settings.
- Keep the Slidr Free codebase MIT-licensed by avoiding reuse of GPL-covered expression and recording implementation provenance.
- Package the MIT license with every binary archive.
- Keep v0.2.0 as a verified rollback point.

## 3. Non-goals

- Importing or adapting MiddleClick, MoreTouch, ConfigCore, their Xcode project, resources, state machines, menus, or login-item code.
- Claiming a strict legal clean-room process. The project will instead claim no source reuse or transliteration and will keep a provenance record.
- Supporting configurable finger counts, `allowMoreFingers`, or user-adjustable duration/movement thresholds in v0.3.
- Supporting two-finger middle click.
- Enumerating multiple multitouch devices, identifying device kinds, or guaranteeing Magic Mouse/external Magic Trackpad behavior in v0.3.
- Per-application ignore lists.
- Delaying every single-finger edge action to discover whether more fingers will arrive.
- Mac App Store distribution.
- Developer ID signing and notarization in this PR.

## 4. Licensing and Provenance

MiddleClick is GPL-3.0 and Slidr Free is MIT. If GPL-protected implementation expression is incorporated or adapted, or GPL code is linked into the same application, public distribution will normally require GPLv3 treatment of the combined work. The exact legal boundary is fact-dependent; this document is an engineering control, not legal advice.

Implementation controls:

- The requirements source is this approved design, public user-visible behavior, black-box validation, Apple documentation, and existing Slidr Free code.
- MiddleClick source, resources, build artifacts, and line-by-line translations are prohibited implementation inputs.
- Implementation agents receive this specification and the Slidr Free repository, not the MiddleClick checkout or prior source-analysis context.
- `docs/middle-click-provenance.md` records the fixed reference SHA, permitted sources, implementer/reviewer roles, dependency inventory, and the no-source-reuse decision.
- Before publication, a reviewer inspects the diff for source or structural copying and records the result in the provenance note.
- The release archive includes Slidr Free's `LICENSE`; automated verification fails if it is missing.
- If any GPL source, resource, or build artifact enters the deliverable, the MIT publishing flow stops pending a new license decision.

Copyright protects copyrightable program expression, not the underlying idea, method, or algorithm. This distinction supports behavior-level reimplementation but does not make source copying permissible.

## 5. Existing Baseline

The current pipeline is:

```text
MultitouchSupport
    -> PhysicalTrackpadMonitor
    -> DispatchQueue.main
    -> GestureRecognizer
    -> ActionDispatcher
    -> SystemControl
```

`PhysicalTrackpadMonitor` uses `MTDeviceCreateDefault`. It currently rejects a nil touch buffer before handling `count == 0`, silently drops malformed frames, and posts normalized frames asynchronously to the main queue. `GestureRecognizer` reads the first touch. `AppDelegate` recreates the recognizer on every settings update.

Commit `b027186448254dec3225aa9767983e778739fc0c` removed an earlier event listener that replayed already-existing middle clicks. It did not recognize a three-finger gesture and must not be restored or cherry-picked.

## 6. Target Architecture

```text
Multitouch callback
    -> normalize active touches / empty frame / cancellation
    -> synchronous MiddleClickRecognizer + MiddleClickSessionBridge
    -> main queue: edge recognizer, UI status, tap action delivery

Dedicated Event Tap run loop
    -> MouseButtonEventReducer
    -> MiddleClickSessionBridge
    -> pass / transform / release / re-enable decision
```

### 6.1 Single touch source and sequencing authority

There is one `PhysicalTrackpadMonitor` callback. After copying the callback data into value types, the monitor synchronously feeds the middle-click recognizer and bridge before scheduling edge/UI work on the main queue. This removes the main-queue delay from physical-click chord activation and deactivation.

Each normalized update carries:

- a monotonically increasing `frameSequence`;
- a pipeline `generation`;
- a monotonic receipt time;
- active touches;
- an update kind: `frame`, `empty`, or `cancel(reason)`.

Updates from an older generation or non-increasing sequence are ignored. Event Tap considers a chord eligible only when its last frame age is no more than `0.15` seconds. A stale chord is inactive and ordinary input passes through.

### 6.2 Zero-touch and cancellation contract

- `count == 0` always becomes an empty update, even if `touchBytes == nil`; no buffer is dereferenced.
- `count > 0 && touchBytes == nil`, invalid counts, monitor stop/restart, sleep, permission loss, and settings reconfiguration produce cancellation.
- Empty completes a normal Tap candidate; cancellation never produces Tap.
- Empty and cancellation atomically deactivate the chord.
- Stop/restart advances generation so queued stale updates cannot reactivate old state.

The adapter treats the callback `count` as the active-touch count for v0.3. It retains `MTTouch.state` for diagnostics and tests. If target-hardware validation shows inactive contacts inside `count`, implementation stops and revises the filter contract before release.

### 6.3 Middle-click recognizer

`MiddleClickRecognizer` is a pure, lock-free value state machine owned by the synchronous touch-processing path. It does not read settings storage, access AppKit/CGEvent, inspect applications, or perform I/O.

It produces `MiddleClickTouchUpdate` values containing:

- session ID;
- chord active/inactive;
- tap candidate ready/not ready;
- frame sequence and monotonic time;
- terminal reason when the session closes.

### 6.4 Atomic session bridge

`MiddleClickSessionBridge` is a small lock-protected reducer shared by touch processing and Event Tap. Its states are:

```text
idle
open(session, chordFresh)
physicalPending(session, sourceButton, eventNumber, generation)
physicalConsumed(session)
tapClaimed(session)
closed(session)
```

Binding rules:

- `claimTap(session)` succeeds only from `open` after chord deactivation by normal empty completion, then atomically enters `tapClaimed`/`closed`.
- A physical Down transforms only from a fresh `open` state and atomically enters `physicalPending`.
- `tapClaimed`, `physicalPending`, and `physicalConsumed` are mutually exclusive for a session.
- A matching Up is identified by original source button, `mouseEventNumber`, pipeline generation, and pending state.
- A matching Up atomically extracts and clears pending state before any output is emitted.
- A second Down while one is pending, a mismatched Up, duplicate Up, or obsolete generation is passed through unchanged.
- Once any physical Down is accepted, the touch session can never claim Tap.

### 6.5 Edge gesture arbitration

The edge recognizer processes only `touches.count == 1`. Once a frame with two or more touches is observed, an edge-suppression latch remains active until the next empty/cancellation update.

The latch cannot undo a single-finger edge action emitted before the second finger arrived. v0.3 preserves immediate single-finger response rather than buffering every edge action. Acceptance therefore requires no edge action after multi-touch is observed and no unexpected edge action during normal stationary three-finger placement; it does not promise mathematical prevention before multi-touch is visible.

### 6.6 Event Tap ownership and reducer

`MouseButtonEventTap` owns a dedicated serial thread and CFRunLoop. Creation, source add/remove, enable, disable, and invalidation occur only on that executor. `start`, `quiesce`, and `stop` have completion callbacks so pipeline lifecycle can wait for a defined transition.

The mask includes:

- left/right Down and Up;
- left/right Dragged;
- tap-disabled-by-timeout/user-input notifications.

`MouseButtonEventReducer` is a pure component. It accepts normalized event metadata and bridge state, and returns one of:

- pass unchanged;
- transform to center Down/Dragged/Up;
- request one synthetic center Up;
- re-enable Event Tap;
- enter degraded state.

Transformed Down/Dragged/Up set event type and `mouseEventButtonNumber` to center, set `mouseEventClickState` to `1` for v0.3, preserve location/timestamp/modifiers and unrelated fields, and keep the matching event number.

If a chord is active while an external mouse or another unmarked system source generates a qualifying event, that event may be transformed. Quartz does not expose a reliable trackpad-device association for these mouse events. This is a documented v0.3 limitation and a required manual test.

### 6.7 Unified quiesce transaction

Settings changes that affect middle-click semantics, app disable, permission loss, Event Tap disable, will-sleep, monitor restart, and application termination use one transaction:

1. Under the bridge lock set `accepting=false` and advance generation.
2. Atomically extract and clear any pending physical Down.
3. Outside the lock, request at most one tagged center Up.
4. On the Event Tap run loop, disable/remove/invalidate the tap as required.
5. Cancel recognizer and edge-suppression state.
6. Validate/apply new configuration.
7. Create a fresh generation and restart eligible components.

Event Tap timeout/user-input disable first runs the release portion of this transaction, then attempts re-enable up to 3 times at 100 ms intervals. Success requires `CGEvent.tapIsEnabled == true`. Failure latches `degraded` until the next explicit pipeline restart.

### 6.8 Tap emitter

Tap action delivery uses the existing ActionDispatcher/SystemControl path. `MiddleClickEmitter` first creates and fully configures tagged Down and Up events. It posts neither event unless both were created successfully. Both use the same current Quartz pointer location and click state `1`.

## 7. Exact-Three-Finger Tap State Machine

Constants are internal and not exposed in v0.3 UI:

- exact active touch count: `3`;
- maximum session duration: `0.30` seconds;
- maximum centroid movement: `0.05` normalized Euclidean distance;
- chord freshness: `0.15` seconds.

Rules:

1. The first non-empty frame opens a session and starts the monotonic duration clock.
2. Before qualification, counts 1 and 2 are placement frames. Empty cancels without Tap.
3. The first exact-three frame qualifies and records the touch-ID set and centroid.
4. Any count above 3 invalidates Tap for the session and deactivates physical-click eligibility.
5. While count remains 3, the touch-ID set must remain identical. Array ordering may change; ID replacement invalidates Tap.
6. Movement is the maximum Euclidean distance from the initial qualified centroid using the same ID set.
7. The first count below 3 after qualification begins release. Any later increase before empty invalidates Tap.
8. Empty completes the session. Tap candidate passes only when total duration from first non-empty frame is `<= 0.30`, maximum movement is `<= 0.05`, and no invalidation/cancellation occurred.
9. A non-increasing input timestamp cancels the Tap candidate. Receipt-time freshness still controls physical-click eligibility.
10. Completion/cancellation clears recognizer state. Session IDs increase only when a new first non-empty frame opens a session.

When `tapEnabled == false`, the recognizer still tracks session/chord updates needed by physical Click but never creates a Tap candidate.

## 8. Settings and Migration

`AppSettings` gains JSON property `middleClick` with:

- `isEnabled`, default `false`;
- `tapEnabled`, default `true`.

The default object remains `isEnabled=false, tapEnabled=true`; toggling the feature must not overwrite the saved Tap preference.

Migration requirements:

- `AppSettings.middleClick` missing: decode the complete beta default.
- Individual nested fields missing: default each independently.
- Representative v0.2 payload: preserve every existing value exactly.
- Structurally corrupt payload: keep the current application behavior of falling back to validated defaults and record a non-sensitive diagnostic.
- Keep `SlidrFree.settings.v1`; custom top-level and nested decoders make the schema additive.

Any change to `isEnabled` or `tapEnabled` quiesces the active middle-click session before new configuration takes effect. Unrelated settings may update without restarting Event Tap.

## 9. Settings UI

The settings form gains a **Middle Click** section with:

- middle-click feature toggle;
- three-finger Tap toggle;
- fixed “3 fingers” explanatory text;
- guidance about macOS three-finger drag and lookup/data-detector conflicts;
- touch-monitor and physical-click Event Tap runtime state.

The menu-bar menu remains unchanged. English and Simplified Chinese strings ship together.

## 10. Lifecycle, Permissions, and Diagnostics

- Start `PhysicalTrackpadMonitor` when the app is enabled, Accessibility is granted, and any physical gesture is enabled.
- Start `MouseButtonEventTap` only when middle click is enabled and Accessibility is granted.
- Refresh Accessibility on application activation and before every pipeline start. Event Tap creation/re-enable failure also forces a permission refresh.
- Observe will-sleep and did-wake. Will-sleep quiesces; did-wake restarts after 2 seconds in a fresh generation.
- App termination uses quiesce and waits for the Event Tap stop completion before returning.

Runtime status covers framework/device availability, touch monitor state, Event Tap state, generation, last bounded failure reason, and last frame age. It never records raw frames, pointer coordinates, application activity, or user content.

## 11. Source Changes

New core/app components:

- `Sources/SlidrFreeCore/MiddleClickRecognizer.swift`
- `Sources/SlidrFreeCore/MiddleClickSettings.swift`
- `Sources/SlidrFreeApp/MiddleClickSessionBridge.swift`
- `Sources/SlidrFreeApp/MouseButtonEventReducer.swift`
- `Sources/SlidrFreeApp/MouseButtonEventTap.swift`
- `Sources/SlidrFreeApp/MiddleClickEmitter.swift`
- `Sources/SlidrFreeApp/InputPipelineStatus.swift`

Modified integration files:

- core settings, gesture/action models, core checks;
- `AppDelegate`, `PhysicalTrackpadMonitor`, `PermissionManager`, `SettingsView`, `SystemControl`;
- `Package.swift`, CI, localizations, README files;
- `scripts/package-release.sh` and release verification.

New tests and governance files:

- `Tests/SlidrFreeCoreTests/`;
- Event reducer, session bridge, emitter factory, adapter/lifecycle, migration, and existing app tests;
- `docs/middle-click-provenance.md`.

## 12. Automated Testing

Required tests include:

- exact-three placement, qualification, release, ID reordering/replacement, movement/duration boundaries, non-monotonic timestamps, cancellation, missing/empty frames, and Tap disabled;
- nil-buffer zero frame, missing non-empty buffer, invalid count, stop/restart generation, stale chord timeout;
- edge-suppression latch and normal single-finger regression;
- claim-vs-physical-Down concurrency in both orders;
- pending matching by source button/event number/generation;
- second Down, mismatched Up, duplicate Up, mixed left/right, multiple physical clicks, and Dragged conversion;
- stop-vs-Down, stop-vs-Up, timeout-between-Down/Up, sleep-while-Down, settings change while pending;
- emitter Down/Up creation failures and pair-only posting;
- v0.2 UserDefaults migration through `SettingsStore` save/reload;
- pipeline start/stop/reconfigure/wake and Event Tap factory failure/re-enable/degraded state;
- release bundle contains `LICENSE`, expected version, bundle ID, and valid ad-hoc signature.

Tests use pure reducers/factories and must not require live Accessibility permission.

Mandatory gates:

1. `swift run SlidrFreeCoreChecks`
2. `swift test`
3. `swift build`
4. `bash scripts/package-release.sh`
5. `codesign --verify --verbose=2 release/Slidr-Free.app`
6. Verify packaged `LICENSE`, `CFBundleIdentifier=com.slidr.free`, and version `0.3.0`
7. Secret scan on documentation and release inputs

## 13. Manual Beta Verification

Required target: this arm64 Mac running macOS 26.5 with its built-in trackpad.

- 50 three-finger Taps: 50 middle clicks, zero duplicates, zero stuck buttons.
- 50 three-finger physical Clicks: 50 balanced middle streams, zero duplicates/stuck buttons.
- 20 physical click-and-drag actions: coherent center Down/Dragged/Up.
- 100 ordinary left and 100 ordinary right clicks with no chord: zero conversions.
- Normal stationary three-finger placement near each edge: no edge action after multi-touch is observed.
- External mouse Click while chord active: record the documented global-source behavior.
- Five enable/disable cycles and five Tap setting changes, including one while a physical Down is pending.
- Three sleep/wake cycles, including one while a physical Down is pending.
- Accessibility grant, revoke, and regrant; ad-hoc app replacement and reauthorization.
- Safari middle-link behavior/tab close, Terminal paste, Finder, Chrome, and Edge.
- Five-minute idle observation: no sustained CPU regression greater than 0.5 percentage points versus v0.2.0 on the same machine.

Record build SHA, macOS version, hardware, TCC state, counts, and results in the PR. Duplicate or stuck clicks are release-blocking.

## 14. Packaging, Submission, and Rollback

This task submits a tested branch and pull request; it does not create a public GitHub Release or merge the PR without a separate user instruction.

Packaging rules:

- `CFBundleShortVersionString=0.3.0` and `CFBundleVersion=3001` for beta build 1.
- Release tag, if later authorized: `v0.3.0-beta.1`.
- The ad-hoc app and ZIP are experimental direct-download artifacts; `codesign --verify` does not imply Developer ID, notarization, Gatekeeper acceptance, private-API approval, or TCC persistence.
- Include `LICENSE` in `Contents/Resources` and verify it after packaging.
- Record archive SHA-256 when a release asset is later created.

Rollback rules:

- Known-good source/tag: `v0.2.0` / `eb93e18e9ba225502bac580ae98e006c1bf1aec5`.
- Preserve a copy and SHA-256 of the known-good v0.2.0 app archive before installing beta.
- Back up `SlidrFree.settings.v1` before beta installation.
- Rollback stops the running app, replaces the bundle, restores/retains compatible settings, resets Accessibility only when needed, relaunches, and verifies version plus all existing edge gestures.
- Test v0.3 settings -> v0.2 launch -> v0.3 relaunch before any later public release.

## 15. Gates

### Implementation complete

- All mandatory automated gates pass.
- Provenance review and license-in-archive check pass.
- No open Critical/Important code-review findings.

### Ready to submit PR

- Implementation-complete gate passes.
- PR describes private API, default-device scope, global mouse-source limitation, default-off behavior, and TCC reauthorization.
- No secret or generated release artifact is committed.

### Ready for beta release

- PR is merged by authorized maintainer.
- Manual beta matrix passes on the required target.
- Rollback rehearsal passes.
- Archive/version/license/hash evidence is attached.

### Ready for stable release

- Separate user authorization.
- At least seven days of daily use or an explicitly approved shorter window.
- Zero known duplicate/stuck-click defects and zero P0/P1 ordinary-input regressions.
- Stable default value is decided from beta evidence rather than assumed.

## 16. Acceptance Criteria

- Valid Tap produces exactly one middle click; valid physical Click produces a balanced center stream.
- Tap and physical Click never both win one session.
- Matching Up is emitted at most once across normal completion and teardown races.
- Stale/unknown/cancelled chord state always passes ordinary input through.
- Existing single-finger gestures pass their current tests and work on the target Mac.
- After multi-touch is observed, edge actions remain suppressed until empty/cancellation.
- v0.2 settings survive migration.
- Event Tap failure, permission loss, sleep, setting changes, and stop/restart do not crash the app or strand a middle button.
- Binary archive contains MIT `LICENSE` and the verified app identity/version.
- Documentation states supported scope and limitations without claiming strict clean-room, notarization, or device-source guarantees.

## 17. Deferred Work

- Configurable 4/5-finger gestures and `allowMoreFingers`.
- User-adjustable duration/movement thresholds.
- Multi-device enumeration and device-kind routing.
- Magic Mouse and guaranteed external Magic Trackpad support.
- Per-application exclusions.
- Developer ID signing/notarization.
