# Slidr Free Middle-Click Integration Design

**Date:** 2026-07-12

**Status:** Approved for implementation planning

**Target release:** v0.3.0 beta, followed by v0.3.0 stable

**Baseline:** `YuriGao/slidr-free` `main@1246345e526190de89618ce4b301c6f34cc90e21`

## 1. Summary

Slidr Free will add configurable three-finger middle-click behavior for the currently monitored trackpad. The feature will support both:

1. **Three-finger tap:** lifting a stationary three-finger chord emits one middle-button down/up pair at the current pointer location.
2. **Three-finger physical click:** a real left- or right-button down/up pair produced while the chord is active is transformed in place into a middle-button down/up pair.

The implementation will reuse Slidr Free's existing `PhysicalTrackpadMonitor`, settings, menu-bar app, permission flow, action dispatch, packaging, and SwiftPM structure. It will not import or adapt source files from `artginzburg/MiddleClick`.

The first release targets the single default multitouch device already supported by Slidr Free. Multi-device enumeration, Magic Mouse support, hot-plug routing, and per-application exclusions are deferred.

## 2. Goals

- Add reliable three-finger tap and physical-click middle-button behavior.
- Keep Slidr Free's existing volume, brightness, and browser-tab gestures unchanged for single-finger input.
- Prevent a multi-finger gesture from triggering an edge gesture.
- Prevent one physical interaction from producing two middle clicks.
- Preserve existing v0.2 user settings during decoding and migration.
- Fail open: if the middle-click event tap is unavailable or fails, ordinary mouse input must continue unchanged.
- Keep the distributed Slidr Free source under its existing MIT license by independently implementing behavior rather than copying GPL-covered implementation code.
- Maintain a reversible release path and document macOS Accessibility reauthorization behavior.

## 3. Non-goals

- Importing `MiddleClick`, `MoreTouch`, `ConfigCore`, its Xcode project, menu implementation, login-item implementation, icons, or source-level state machines.
- Magic Mouse support in v0.3.
- Enumerating multiple multitouch devices or routing gestures by device kind in v0.3.
- Per-application ignore lists in v0.3.
- Supporting two-finger middle click. The configurable range is 3 to 5 fingers because two fingers conflict with common secondary-click behavior.
- Replacing the private `MultitouchSupport` dependency with a public API; macOS does not expose an equivalent per-finger physical-coordinate API.
- Mac App Store distribution.

## 4. Licensing Decision

`artginzburg/MiddleClick` is GPL-3.0, while Slidr Free is MIT-licensed. Directly copying, translating, adapting, or linking its implementation into the distributed Slidr Free application would make the combined distribution subject to GPL obligations.

The v0.3 implementation therefore follows these rules:

- Use only public, user-visible behavior as the product requirement.
- Design and write all new source in the Slidr Free repository without copying or line-by-line translating MiddleClick source.
- Do not import MiddleClick packages or build artifacts.
- Keep a short design note in the repository explaining the independent implementation decision.
- Perform a final license review before public release. This design is an engineering decision record, not legal advice.

## 5. Existing Baseline

Slidr Free currently has a single input pipeline:

```text
MultitouchSupport
    -> PhysicalTrackpadMonitor
    -> NormalizedInputEvent.physicalTouchFrame
    -> GestureRecognizer
    -> ActionDispatcher
    -> SystemControl
```

`PhysicalTrackpadMonitor` dynamically loads the private framework and calls `MTDeviceCreateDefault`. `GestureRecognizer` currently reads the first touch and recognizes left, right, and top edge movement. `AppDelegate` owns pipeline lifecycle, while `SettingsStore` persists a version-one JSON value in `UserDefaults`.

The repository previously contained a middle-click event listener, removed by commit `b027186448254dec3225aa9767983e778739fc0c`. That implementation listened for already-generated middle-button events and replayed them; it did not recognize a three-finger gesture. It must not be restored or cherry-picked.

## 6. Target Architecture

```text
                              +-> Edge GestureRecognizer -> ActionDispatcher
PhysicalTrackpadMonitor ------+
                              +-> MiddleClickRecognizer --+-> tap intent
                                                         +-> chord state

tap intent -> ActionDispatcher -> SystemControl -> MiddleClickEmitter -> CGEvent middle down/up
thread-safe chord state -----------> MouseButtonEventTap -> transform left/right to middle
```

### 6.1 Single touch-frame source

There will be exactly one `PhysicalTrackpadMonitor` and one private-framework callback. Each normalized frame will be offered to two independent recognizers:

- the existing edge recognizer;
- the new `MiddleClickRecognizer`.

The recognizers do not call one another and do not own macOS event objects. They operate on normalized data and return state or intents.

### 6.2 Edge gesture arbitration

The existing edge recognizer will only process a frame when `touches.count == 1`. A frame with zero or more than one touch resets edge continuity and its accumulated physical step.

This rule prevents a three-finger chord near the trackpad edge from changing volume, brightness, or browser tabs.

### 6.3 Middle-click recognizer

`MiddleClickRecognizer` is a pure state machine in `SlidrFreeCore`. It accepts a full touch frame and returns a state update containing:

- whether the configured finger chord is currently active;
- whether a tap candidate is ready to be atomically claimed;
- a session identifier used to suppress duplicate delivery.

It does not inspect the frontmost application, read `UserDefaults`, access `CGEvent`, or perform I/O.

### 6.4 Thread-safe chord state

Touch frames are delivered to the main queue, while a Quartz event-tap callback may execute on its run-loop thread. A small lock-protected `MiddleClickChordState` bridges those contexts.

The event tap may synchronously read and update only:

- chord active/inactive;
- current session identifier;
- whether a physical mouse down was transformed;
- the original button associated with a pending transformed down;
- whether the session was consumed by a physical click.

No UI work, settings reads, app lookup, logging, or allocation-heavy processing occurs in the event-tap callback.

### 6.5 Mouse event transformation

`MouseButtonEventTap` uses a modifiable `.cghidEventTap` at `.headInsertEventTap`. It listens for:

- `.leftMouseDown` and `.leftMouseUp`;
- `.rightMouseDown` and `.rightMouseUp`;
- `.tapDisabledByTimeout` and `.tapDisabledByUserInput`.

When a left/right down arrives while the configured chord is active, it is transformed in place to `.otherMouseDown` with button `.center`. The bridge records that the down was transformed and marks the touch session as consumed.

Once a down has been transformed, the up matching its original source button is always transformed to `.otherMouseUp`, even if the fingers have already left the trackpad. This pairing rule prevents a stuck or mismatched button state.

When the chord is inactive and there is no pending transformed down, the original event is returned unchanged. If event-tap creation fails, the tap is stopped, the degraded state is reported, and normal input remains untouched.

### 6.6 Tap emission

When the recognizer emits a tap intent, `AppDelegate` atomically calls `claimTap(sessionID:)` on `MiddleClickChordState`. The claim succeeds only when the same session has not been consumed by a physical click and no transformed down is pending. A successful claim is routed through `ActionDispatcher` and `SystemControl`; `MiddleClickEmitter` then reads the current Quartz pointer location and posts one center-button down/up pair.

Synthetic events are tagged with a Slidr Free-specific `eventSourceUserData` marker. The event tap passes these tagged events through without reinterpreting them.

## 7. Gesture State Machine

### 7.1 Defaults

- Feature enabled: `false` in v0.3 beta.
- Finger count: `3`.
- Allow more fingers: `false`.
- Tap enabled: `true` when the feature is enabled.
- Maximum qualifying duration: `0.30` seconds.
- Maximum centroid movement: `0.05` in normalized trackpad coordinates.

### 7.2 Tap recognition

1. Frames below the configured finger count are accepted as the user places fingers; they do not start timing.
2. The first frame satisfying the configured count starts a candidate, records its timestamp, active touch identifiers, and centroid.
3. If `allowMoreFingers` is false, any later frame above the configured count invalidates the candidate.
4. While the qualifying count remains present, the recognizer records the maximum Euclidean distance between the current centroid and the initial centroid.
5. After qualification, the first reduction in touch count begins the release phase. A later increase before all fingers lift invalidates the candidate as ambiguous.
6. A zero-touch frame completes the session.
7. The session emits one tap candidate only when it qualified, did not exceed the duration or movement thresholds, and was not invalidated. The atomic claim in Section 6.6 rejects a candidate already consumed by a physical click.
8. Completion or cancellation clears all candidate state.

Using the centroid rather than individual finger order avoids false movement when the private framework changes touch-array ordering.

Chord tracking remains active when `tapEnabled` is false so physical-click transformation continues to work. Disabling Tap suppresses only tap-candidate creation and completion.

### 7.3 Physical-click recognition

The chord is active only while the current frame satisfies the configured count rule. Physical click delivery is driven by the event tap, not by pressure thresholds in the private touch frame.

The event tap tracks at most one pending transformed down/up pair at a time. After that pair completes, another physical click may be transformed while the chord remains active. Any transformed down marks the touch session as consumed so lifting the fingers cannot also emit a tap middle click.

## 8. Settings and Migration

`AppSettings` gains a `MiddleClickSettings` value with:

- `isEnabled`;
- `fingerCount`;
- `allowMoreFingers`;
- `tapEnabled`;
- `maxDurationSeconds`;
- `maxMovement`.

Validation clamps:

- finger count to `3...5`;
- duration to `0.10...0.60` seconds;
- movement to `0.01...0.15`.

Custom decoding must use `decodeIfPresent` and fall back to the safe beta defaults. Decoding a v0.2 settings payload must preserve all existing feature values and add middle-click settings without resetting the entire object.

The existing `SlidrFree.settings.v1` key remains unchanged because the encoded model already supports additive migration. No destructive migration or defaults reset is allowed.

## 9. Settings UI

The SwiftUI settings form gains a **Middle Click** section containing:

- feature toggle;
- finger-count picker for 3, 4, or 5 fingers;
- tap toggle;
- allow-more-fingers toggle;
- an expandable Advanced group for duration and movement thresholds;
- compact conflict guidance for three-finger drag and three-finger lookup/data-detector gestures;
- runtime state text distinguishing touch monitoring from physical-click event-tap availability.

The menu-bar menu remains unchanged in v0.3. Middle click is configured in the settings window rather than adding another quick toggle.

English and Simplified Chinese strings are added together. The documentation will state that granting Accessibility again may be required after replacing an ad-hoc signed build.

## 10. Input Pipeline Lifecycle

`AppDelegate.updateEventTap()` is renamed to `updateInputPipeline()` because it manages more than an event tap.

The pipeline rules are:

- Start `PhysicalTrackpadMonitor` when the app is enabled, Accessibility is granted, and any physical gesture feature is enabled.
- Start `MouseButtonEventTap` only when middle click is enabled and Accessibility is granted.
- Stop and clear both components when the application is disabled or permission is revoked.
- If a transformed down is pending during shutdown, request one best-effort center-button up before invalidating the event tap, then clear pending state. A later unmodified source-button up is allowed to pass through.
- Re-enable the event tap after `.tapDisabledByTimeout` or `.tapDisabledByUserInput`; if repeated re-enable fails, report a degraded state and leave mouse input untouched.
- On system wake, restart the private touch monitor after a bounded delay and recreate the event tap if required.

Multi-device hot-plug handling, display-change restarts, and fast-user-switching specialization are deferred until multi-device support.

## 11. Error Handling and Diagnostics

The current private-framework bridge silently drops several failures. The integration adds a lightweight runtime status model covering:

- private framework loaded/unavailable;
- default touch device available/unavailable;
- touch monitor running/stopped;
- mouse event tap running/degraded/stopped;
- last non-sensitive failure reason.

Diagnostics must not record raw touch frames, pointer locations, application activity, or user content. Status is displayed in the settings window and printed only as bounded development logging.

Failure behavior:

- Private framework unavailable: all physical gestures stop; the app and settings remain usable.
- Event tap unavailable: edge gestures and three-finger tap may continue; physical-click transformation is marked unavailable.
- Accessibility revoked: all event-generating input components stop until permission is restored.
- Invalid settings: values are clamped before recognizers are created.

## 12. Expected Source Changes

### New core files

- `Sources/SlidrFreeCore/MiddleClickRecognizer.swift`
- `Sources/SlidrFreeCore/MiddleClickSettings.swift`

### New app files

- `Sources/SlidrFreeApp/MiddleClickChordState.swift`
- `Sources/SlidrFreeApp/MouseButtonEventTap.swift`
- `Sources/SlidrFreeApp/MiddleClickEmitter.swift`
- `Sources/SlidrFreeApp/InputPipelineStatus.swift`

### Modified files

- `Sources/SlidrFreeCore/AppSettings.swift`
- `Sources/SlidrFreeCore/GestureRecognizer.swift`
- `Sources/SlidrFreeCore/ActionDispatcher.swift`
- `Sources/SlidrFreeApp/AppDelegate.swift`
- `Sources/SlidrFreeApp/PhysicalTrackpadMonitor.swift`
- `Sources/SlidrFreeApp/PermissionManager.swift`
- `Sources/SlidrFreeApp/SettingsView.swift`
- `Sources/SlidrFreeApp/SystemControl.swift`
- localized strings, core checks, XCTest files, CI, README, and packaging documentation.

The implementation plan may consolidate a proposed file when the resulting type remains focused and testable, but it must preserve the component boundaries in this design.

## 13. Testing Strategy

### 13.1 Pure recognizer tests

- Exact 3-finger chord succeeds; 2 and 4 fail by default.
- `allowMoreFingers` accepts counts above the configured value.
- Gradual placement and gradual release succeed.
- Count increase after release begins cancels.
- Duration and movement values immediately inside and outside boundaries behave correctly.
- Touch-array reordering does not create false movement.
- Timeout, cancellation, empty-frame completion, and settings disable clear state.
- One session emits at most one tap intent.
- A session consumed by physical click emits no tap intent.

### 13.2 Arbitration tests

- Existing single-finger left, right, and top edge cases remain unchanged.
- Every frame with more than one touch resets edge continuity and emits no edge action.
- Leaving and re-entering an edge establishes a fresh baseline.

### 13.3 Event-tap tests

The callback logic is separated from tap creation so synthetic event fixtures can verify:

- left/right down and matching up convert to center events;
- up remains converted after chord deactivation;
- input passes through when no chord is active;
- tagged synthetic events pass through;
- sequential physical clicks remain balanced and convert while the chord stays active;
- disabling the feature clears pending state;
- stopping with a pending transformed down requests a best-effort center-button up;
- timeout/user-input disable events request safe re-enable;
- physical conversion marks the matching touch session consumed.

### 13.4 Settings and migration tests

- Decode representative v0.2 JSON without losing existing values.
- Decode missing middle-click fields to beta defaults.
- Clamp finger count, duration, and movement.
- Save and reload all new settings.

### 13.5 Verification gates

Local and CI gates are:

1. `swift run SlidrFreeCoreChecks`
2. `swift test` where XCTest is available
3. `swift build`
4. `swift build -c release`
5. `bash scripts/package-release.sh`
6. `codesign --verify --verbose=2 release/Slidr-Free.app`

CI will add `swift test` rather than relying only on core checks.

### 13.6 Manual test matrix

- macOS 13, 14, 15, and 26 where hardware is available.
- Built-in Force Touch trackpad; the current default-device behavior on an external Magic Trackpad is exploratory, not a v0.3 guarantee.
- Tap to Click on/off.
- Three-finger drag and three-finger lookup/data-detector gestures on/off.
- Safari background-link opening and tab closing, Terminal middle-button paste, Finder, Chrome, and Edge.
- Ordinary left click, right click, click-and-drag, and existing edge gestures.
- Accessibility first grant, denial, revocation, app replacement, and reauthorization.
- Sleep/wake and app enable/disable cycles.
- Idle CPU observation and repeated rapid gestures to identify stuck event taps or duplicated clicks.

## 14. Rollout and Rollback

1. Release an opt-in v0.3.0 beta with middle click disabled by default.
2. Install it alongside the established packaging flow and reauthorize Accessibility if macOS invalidates the ad-hoc replacement.
3. Run the manual matrix on the target Mac before enabling the feature by default in any later release.
4. Keep v0.2.0 as the known-good rollback release until v0.3.0 is accepted in daily use.
5. Tag and attach the verified application archive only after packaging and signature checks pass.
6. If input feels unreliable, duplicates clicks, or interferes with ordinary mouse behavior, roll back the installed app immediately rather than tuning the behavior in place on the user's primary environment.

## 15. Acceptance Criteria

The v0.3 design is complete when all of the following are true:

- A valid configured tap produces exactly one middle click at the current pointer location.
- A valid configured physical click transforms exactly one down/up pair to the center button.
- Physical click and tap recognition never double-deliver for the same touch session.
- A transformed down always receives a transformed matching up.
- Ordinary left/right input is unchanged when no chord is active or the feature is disabled.
- Existing volume, brightness, and browser-tab gestures still work for single-finger input.
- Multi-finger input never triggers an edge action.
- Existing v0.2 settings survive migration.
- Permission loss, event-tap failure, or private-framework failure does not block ordinary input or crash the app.
- Automated verification gates pass and the manual target-Mac matrix has no critical failures.
- README and release notes describe the private-API limitation, Accessibility/TCC behavior, supported device scope, default-off beta state, and MIT/GPL implementation boundary accurately.

## 16. Deferred Follow-up

After v0.3 is accepted, a separate design cycle may add:

- `MTDeviceCreateList` multi-device enumeration;
- stable device identifiers and device-kind routing;
- Magic Mouse-specific recognition;
- external Magic Trackpad hot-plug support;
- per-application exclusions;
- Developer ID signing and notarization if distribution credentials are available.

These items are deliberately excluded from the v0.3 implementation plan.
