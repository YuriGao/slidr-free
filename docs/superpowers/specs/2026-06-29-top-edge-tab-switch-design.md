# Top Edge Browser Tab Switching Design

## Goal

Add a physical trackpad top-edge gesture that switches Safari and Chrome tabs:
rightward movement selects the next tab, leftward movement selects the previous
tab, and continuous movement keeps switching in the same direction with haptic
feedback per successful switch.

## Scope

- Detect the gesture only from physical trackpad frames already produced by
  `PhysicalTrackpadMonitor`.
- Keep existing left and right edge brightness/volume gestures unchanged.
- Execute tab switching only when the frontmost app is Safari or Google Chrome.
- Do not use AppleScript or browser automation permissions.
- Add a settings toggle so the feature can be disabled independently.

## Interaction

The top edge is active when a touch has `y >= 1 - edgeWidthPercent`. The first
frame establishes a baseline. While the same touch remains on the top edge,
the recognizer accumulates horizontal movement:

- Accumulated positive `deltaX` beyond `physicalStepDistance` emits
  `.browserTab(.next)`.
- Accumulated negative `deltaX` beyond `physicalStepDistance` emits
  `.browserTab(.previous)`.
- After each emitted step, one step distance is consumed and remaining movement
  stays accumulated, so sustained movement can emit repeated tab switches.
- Emissions are throttled by `tabSwitchStepIntervalSeconds`, default `0.20`.
- A horizontal movement sample only counts when
  `abs(deltaX) >= abs(deltaY) * horizontalDominanceRatio`, default `1.5`.

The recognizer resets top-edge accumulation when the touch leaves the top edge,
the touch id changes, or the app/feature is disabled.

## Execution

The core layer emits:

- `RecognizedGesture.browserTab(direction: BrowserTabDirection)`
- `SystemAction.switchBrowserTab(direction: BrowserTabDirection)`

The app layer checks `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`
at execution time. Allowed bundle identifiers:

- `com.apple.Safari`
- `com.google.Chrome`

If the frontmost app is not allowed, execution returns `.unsupported` and does
not trigger haptic feedback.

For allowed apps, the app posts synthetic keyboard events:

- Next tab: `Command + Shift + ]`
- Previous tab: `Command + Shift + [`

When the key events are posted successfully, `AppDelegate` performs one
`.levelChange` haptic feedback event.

## Settings

`FeatureToggles` gains `browserTabEdgeGesture`, default `true`.
`GestureSettings` gains:

- `tabSwitchStepIntervalSeconds`, default `0.20`, clamped to `0.05...0.80`
- `horizontalDominanceRatio`, default `1.5`, clamped to `1.0...4.0`

Settings decoding remains backward compatible with existing saved settings by
using defaults for missing fields.

The settings window adds one toggle in the physical edge gesture section:

- English: `Top edge browser tab switching`
- Simplified Chinese: `上边缘切换浏览器标签页`

## Tests

Core checks cover:

- Top-edge rightward movement emits next tab.
- Top-edge leftward movement emits previous tab.
- Sustained movement emits repeated steps.
- Movement below the threshold emits nothing.
- Vertically dominant movement emits nothing.
- Leaving the top edge or changing touch id resets accumulation.
- Disabling the feature suppresses tab switching.
- `ActionDispatcher` maps browser tab gestures to system actions.

App tests cover:

- Browser bundle id filtering allows Safari and Chrome and rejects other apps.
- Keyboard event generation produces down/up events with Command and Shift for
  the expected bracket key.

## Risks

- `MultitouchSupport` is private API, so top-edge coordinate orientation must be
  verified on the target Mac.
- Keyboard shortcuts depend on browser support and current keyboard layout.
- The feature could be too sensitive if the threshold is too small, so the
  existing edge width and step distance are reused and horizontal dominance is
  required.
