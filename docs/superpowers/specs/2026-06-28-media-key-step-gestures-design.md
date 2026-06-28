# Media-Key Brightness and Step Gesture Design

## Problem

The physical trackpad monitor now recognizes edge gestures, but two runtime problems remain:

1. Brightness gestures fail on the test Mac with `failed("No built-in display service")`.
2. Edge gestures are too sensitive because every physical touch frame with vertical movement can dispatch an action.

Debug logs show many brightness actions within the same second. The current brightness path uses `IOServiceMatching("IODisplayConnect")`, then `IODisplayGetFloatParameter` / `IODisplaySetFloatParameter`. That path is unreliable on modern macOS and Apple Silicon, where `IODisplayConnect` may not expose a built-in display service.

## Goals

- Make brightness gestures work on modern Macs when the system brightness keys work.
- Make brightness and volume gestures feel like pressing the system brightness/volume keys one step at a time.
- Reduce accidental repeated actions from high-frequency touch frames.
- Keep behavior easy to diagnose in the Debug window.

## Non-Goals

- Do not add a direct brightness slider or precision brightness percentage control.
- Do not introduce `DisplayServices.framework` in this iteration.
- Do not restore scroll-wheel screen-edge gestures.
- Do not change the physical trackpad private API monitor design.

## Chosen Approach

Use system-defined media-key events for both brightness and volume, and add step-based gesture accumulation before dispatch.

Brightness should use the same event style already used for the fixed volume path:

- event type: `.systemDefined`
- subtype: `8` auxiliary control buttons
- key states: `0xA` down, `0xB` up
- brightness up key type: `2`
- brightness down key type: `3`
- post converted `cgEvent` values to `.cghidEventTap`

The old `IODisplayConnect` brightness path should no longer be the primary implementation. It may be removed from action execution for now. If media-key brightness fails on a specific machine, the Debug panel should still show that a brightness media-key action was posted, making the failure mode clear.

## Gesture Step Behavior

Physical edge movement should accumulate vertical delta instead of dispatching on every frame.

Proposed model:

- Track the active physical touch ID.
- Accumulate vertical movement while the touch remains on the controlling edge.
- Trigger one gesture step only when accumulated movement crosses a threshold.
- After triggering, subtract one threshold from the accumulator so large swipes can produce multiple steps at a controlled pace.
- Reset the accumulator when the touch ends, touch ID changes, edge changes, or the touch leaves the edge.
- Apply a minimum interval between emitted steps so high-frequency touch callbacks cannot spam actions.

Initial defaults:

- `stepDistance`: `0.10` normalized trackpad height per emitted step.
- `minStepIntervalSeconds`: `0.08` seconds between emitted steps.
- Each emitted gesture uses `magnitude: 1.0`.

With this model, a bottom-to-top edge swipe can produce roughly ten key-like steps, while small jitter does nothing.

## Settings and Compatibility

Existing sensitivity settings should still matter, but should not multiply per-frame noise. In this design:

- The recognizer emits one key-like gesture step at a time.
- `ActionDispatcher` can keep applying existing sensitivity and fine-control settings, but defaults should be adjusted so a normal step maps to a single media-key press.
- If needed, follow-up work can simplify settings labels to describe step distance and repeat speed instead of raw sensitivity.

## Components

### `MediaKeyEventFactory`

Extend the existing media-key model with brightness cases:

- `brightnessUp`
- `brightnessDown`

The factory remains responsible only for constructing down/up `NSEvent` pairs.

### `SystemControl`

Change `adjustBrightness(delta:)` to post brightness media keys based on the sign of `delta`.

Remove the current failure path that depends on `IODisplayConnect` for normal brightness control.

### `GestureRecognizer`

Replace per-frame magnitude emission with step accumulation for physical touch frames. Recognition remains physical-edge-only.

The recognizer owns the accumulator state because it already tracks previous physical touch state and has access to timestamps.

### Tests

Add or update checks to cover:

- Brightness media-key event construction.
- Small physical movement below threshold emits no action.
- Crossing the threshold emits exactly one brightness or volume step.
- Repeated frames inside the minimum interval do not emit multiple steps.
- Movement after the interval can emit another step.
- Reset on touch ID or edge change.

## Error Handling and Diagnostics

- If media-key event construction fails, `SystemControl` should return `.failed("Failed to create media key events")`.
- Otherwise, return `.success` after posting the media-key event pair.
- Debug logs should become less noisy because actions are only emitted for completed steps.

## Risks

- Synthesized brightness media keys still depend on macOS accepting HID event posts and on Accessibility permission.
- Some external displays may not respond to system brightness keys. This is acceptable for this iteration because the target behavior is system-key-like built-in brightness control.
- The best default `stepDistance` may need tuning after real use.

## Acceptance Criteria

- A left-edge brightness swipe no longer reports `No built-in display service`.
- Brightness actions post `NX_KEYTYPE_BRIGHTNESS_UP/DOWN`-style media-key events.
- Volume and brightness gestures emit discrete steps rather than one action per touch frame.
- Tests and core checks pass.
- The release app can be rebuilt, ad-hoc signed, zipped, and uploaded.
