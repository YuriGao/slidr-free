# Configurable Middle-Click Finger Count Design

**Date:** 2026-07-12

**Status:** Approved for implementation planning

**Target:** Extend the open v0.3.0 middle-click integration

**Supersedes:** The fixed exact-three-finger scope in Sections 1, 3, 7, 8, and 9 of `2026-07-12-middle-click-integration-design.md`. All unrelated architecture, safety, licensing, and verification contracts in that design remain in force.

## 1. Summary

Slidr Free will replace the fixed three-finger middle-click requirement with one global, user-selectable finger count. The Settings window will offer exactly **2**, **3**, and **4** fingers. The default will be **4 fingers** so macOS users who enable three-finger drag can use middle click without a gesture conflict.

Tap and physical Click will share the same selected count and will continue to require exactly that many active touches. The setting takes effect immediately through the existing safe pipeline-reconfiguration lifecycle.

This is a behavior-level reimplementation based on public MiddleClick documentation. No MiddleClick source, resources, project files, or build artifacts may be copied, translated, or used as implementation input.

## 2. Goals

- Let users select 2, 3, or 4 fingers in the existing Middle Click settings section.
- Default new and migrated configurations to 4 fingers.
- Use the same count for Tap and physical Click.
- Preserve exact-count matching: fewer or more fingers do not qualify.
- Warn users that 2 fingers can conflict with macOS two-finger secondary click and ordinary touch interactions.
- Apply count changes without restarting the application.
- Preserve balanced middle-button Down/Dragged/Up behavior during reconfiguration.
- Keep the existing duration, movement, freshness, arbitration, and lifecycle contracts unchanged.

## 3. Non-goals

- Counts below 2 or above 4.
- Separate finger counts for Tap and physical Click.
- An `allowMoreFingers` or “at least N fingers” mode.
- User-adjustable movement, duration, or freshness thresholds.
- A menu-bar shortcut for changing the count.
- Detecting whether macOS three-finger drag is enabled.
- Reading or adapting GPL-licensed implementation code from MiddleClick.

## 4. Public Behavior Reference and Licensing Boundary

The permitted behavior references are public user documentation:

- MiddleClick documents one `fingers` preference used to change the middle-click finger count.
- Its documentation warns that 2 fingers can conflict with normal two-finger right click and other clicks.
- Exact matching is the documented default; accepting additional fingers is a separate optional behavior.
- Its three-finger-drag guidance recommends selecting 4 fingers to avoid the conflict.
- Its 3.2.0 release notes state that the finger count can be changed from the application menu.

Slidr Free will reproduce only these user-visible ideas in its own settings model, recognizer, UI, tests, and wording. `docs/middle-click-provenance.md` must be updated to record this extension and the no-source-reuse boundary.

## 5. Settings Model and Migration

`MiddleClickSettings` gains:

```swift
fingerCount: Int
```

The supported domain is the closed range `2...4`. The model owns validation so UI, persisted data, and pipeline construction share one contract.

Defaults and decoding rules:

- New settings default to `fingerCount = 4`.
- Existing JSON without `fingerCount` migrates to `4` while preserving all other fields.
- Decoded values outside `2...4` fall back to `4` rather than being silently clamped to another user choice.
- Encoding always writes the validated value.
- The existing settings storage key and additive JSON schema remain unchanged.

Changing `fingerCount` is a semantic middle-click settings change. Existing equality-based pipeline lifecycle handling must quiesce the old configuration and start a fresh generation with the new count.

## 6. Recognition Behavior

`MiddleClickRecognizer` receives the validated finger count at initialization. The fixed `exactTouchCount = 3` constant is removed from recognition decisions.

For a configured count `N`:

1. Counts below `N` are placement or release frames under the existing state-machine rules.
2. The first frame with exactly `N` active touches qualifies the session and records its touch-ID set and centroid.
3. Any frame above `N` invalidates the session.
4. While the count remains `N`, the touch-ID set must remain identical.
5. Tap duration and movement limits remain unchanged.
6. Physical Click eligibility is active only while a fresh exact-`N` chord is active.
7. Tap and physical Click remain mutually exclusive within one touch session.

The current edge-gesture suppression latch already activates for any multi-touch frame, so all supported counts remain isolated from single-finger edge actions without changing that contract.

## 7. Settings UI

The Middle Click section adds a native segmented selector with the values **2**, **3**, and **4**. Four fingers is selected by default.

UI behavior:

- The selector is enabled only when Middle Click is enabled, matching the section's existing dependent controls.
- The Tap label and explanatory copy become count-neutral; fixed “three-finger” wording is removed.
- Selecting 2 fingers shows an inline warning that it may conflict with macOS secondary click and common two-finger gestures.
- Selecting 3 fingers shows concise guidance that macOS three-finger drag users should choose 4.
- Selecting 4 fingers needs no warning.
- English and Simplified Chinese strings are updated together.
- The selected value is persisted immediately through the existing settings binding flow.

The menu-bar menu remains unchanged because the existing Settings window is the established configuration surface and the requested range is small.

## 8. Runtime Reconfiguration and Failure Handling

No new lifecycle mechanism is introduced. When `fingerCount` changes, the existing unified quiesce transaction must:

1. Stop accepting new middle-click transformations.
2. Release at most one pending synthetic middle-button Down.
3. Cancel recognizer/session state and advance the pipeline generation.
4. Recreate the recognizer with the validated new count.
5. Restart eligible monitoring and Event Tap components.

The application must never carry a partially qualified old-count session into the new configuration. If restart fails, the existing degraded/runtime-state reporting remains authoritative and ordinary mouse input continues to pass through.

## 9. Tests

Automated coverage must include:

- default settings encode `fingerCount = 4`;
- legacy top-level and nested payloads without the field migrate to 4 while preserving prior values;
- persisted values 2, 3, and 4 round-trip;
- values below 2 or above 4 fall back to 4;
- each configured count qualifies only an exact-count Tap;
- counts below or above the configured value do not emit Tap;
- configured 4 rejects a three-finger session, covering the three-finger-drag conflict;
- physical Click uses the configured count and produces balanced center Down/Dragged/Up;
- Tap and physical Click use the same configured value;
- changing the count during an active/pending session safely releases and rebuilds the pipeline;
- unrelated settings changes retain the selected count;
- localized UI copy contains no fixed-count promise and includes the 2-finger warning.

Verification must run the repository's full Swift test suite, release build/package checks, license/provenance checks, and the existing CI-equivalent commands. Manual acceptance on a Mac with three-finger drag enabled must confirm that 4-finger Tap and physical Click work while 3-finger placement does not trigger middle click.

## 10. Documentation and Release Scope

Update both READMEs, settings screenshots or text references if present, release notes/checklists, and `docs/middle-click-provenance.md` so they state:

- the supported range is 2–4 fingers;
- the default is 4;
- matching is exact;
- Tap and physical Click share the selected count;
- 2 fingers may conflict with standard macOS gestures;
- 4 fingers is recommended for three-finger-drag users.

The change remains part of the existing v0.3.0 beta PR. It does not require importing a new dependency or changing the MIT license.

## 11. Acceptance Criteria

The feature is complete when:

1. A user can select 2, 3, or 4 fingers from Settings and the choice survives relaunch.
2. A legacy installation receives the 4-finger default without losing any existing setting.
3. Tap and physical Click respond only to exactly the selected number of touches.
4. Changing the selection during an active gesture cannot leave the middle button logically held down.
5. The 2-finger conflict warning and three-finger-drag guidance are present in both supported languages.
6. All automated and packaging checks pass.
7. Provenance records confirm that only public behavior documentation, this design, and existing Slidr Free code were used.
