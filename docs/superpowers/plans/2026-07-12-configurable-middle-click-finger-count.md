# Configurable Middle-Click Finger Count Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent 2/3/4-finger middle-click selector, default it to 4, and use the exact selected count for both Tap and physical Click.

**Architecture:** Extend `MiddleClickSettings` with a validated `fingerCount`, inject it into the existing pure recognizer when a pipeline generation is created, and bind it to a native SwiftUI segmented picker. Reuse the existing equality-based quiesce/restart lifecycle so an active old-count session cannot survive a setting change.

**Tech Stack:** Swift 5.9, Swift Package Manager, SwiftUI, XCTest, JSON `Codable`, existing release shell checks.

---

## File map

- `Sources/SlidrFreeCore/MiddleClickSettings.swift`: supported range, default, persistence, and validation authority.
- `Tests/SlidrFreeCoreTests/AppSettingsMigrationTests.swift`: defaults, migration, round-trip, and invalid-value regressions.
- `Sources/SlidrFreeCore/MiddleClickRecognizer.swift`: exact configured-count recognition.
- `Tests/SlidrFreeCoreTests/MiddleClickRecognizerTests.swift`: 2/3/4 exact-count behavior and four-finger conflict regression.
- `Sources/SlidrFreeApp/InputPipelineStatus.swift`: inject the selected count into each pipeline recognizer.
- `Tests/SlidrFreeAppTests/InputPipelineLifecycleTests.swift`: prove the selected count reaches the pipeline and changes quiesce/rebuild it.
- `Sources/SlidrFreeApp/SettingsView.swift`: native 2/3/4 segmented picker and conditional guidance.
- `Resources/en.lproj/Localizable.strings`: count-neutral English copy and warnings.
- `Resources/zh-Hans.lproj/Localizable.strings`: count-neutral Simplified Chinese copy and warnings.
- `Sources/SlidrFreeCoreChecks/main.swift`: executable smoke checks for default and four-finger recognition.
- `README.md`, `README.zh-CN.md`: public behavior, defaults, limitations, and migration guidance.
- `docs/middle-click-provenance.md`: public-document behavior source and no-source-reuse record.

### Task 1: Persist and validate the selected count

**Files:**
- Modify: `Tests/SlidrFreeCoreTests/AppSettingsMigrationTests.swift`
- Modify: `Sources/SlidrFreeCore/MiddleClickSettings.swift`

- [ ] **Step 1: Write failing migration and validation tests**

Add assertions that the complete default and legacy payloads use 4, partial nested payloads preserve their booleans while using 4, values 2/3/4 round-trip, and values 1/5 decode to 4. Use the intended API:

```swift
XCTAssertEqual(MiddleClickSettings.default.fingerCount, 4)
XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: true, tapEnabled: false, fingerCount: 4))
XCTAssertEqual(try decodeSettings(middleClickJSON: #"{"fingerCount":2}"#).middleClick.fingerCount, 2)
XCTAssertEqual(try decodeSettings(middleClickJSON: #"{"fingerCount":5}"#).middleClick.fingerCount, 4)
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter AppSettingsMigrationTests`

Expected: compilation fails because `fingerCount` and the three-argument initializer do not exist.

- [ ] **Step 3: Implement the minimal model change**

Add `fingerCount`, a `supportedFingerCounts = 2...4` authority, a default of 4, and validation used by both initialization and decoding:

```swift
public var fingerCount: Int
public static let supportedFingerCounts = 2...4
public static let `default` = Self(isEnabled: false, tapEnabled: true, fingerCount: 4)

public init(isEnabled: Bool, tapEnabled: Bool, fingerCount: Int = Self.default.fingerCount) {
    self.isEnabled = isEnabled
    self.tapEnabled = tapEnabled
    self.fingerCount = Self.supportedFingerCounts.contains(fingerCount) ? fingerCount : Self.default.fingerCount
}
```

Decode the optional field and pass it through the same initializer. Keep the default argument temporarily so existing call sites remain source-compatible until they are made explicit where behavior matters.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter AppSettingsMigrationTests`

Expected: all migration tests pass.

- [ ] **Step 5: Commit the settings slice**

```bash
git add Sources/SlidrFreeCore/MiddleClickSettings.swift Tests/SlidrFreeCoreTests/AppSettingsMigrationTests.swift
git commit -m "feat: persist middle-click finger count"
```

### Task 2: Make recognition use the exact configured count

**Files:**
- Modify: `Tests/SlidrFreeCoreTests/MiddleClickRecognizerTests.swift`
- Modify: `Sources/SlidrFreeCore/MiddleClickRecognizer.swift`

- [ ] **Step 1: Write failing exact-count tests**

Add compact helpers that generate touches with unique IDs, then test counts 2, 3, and 4 independently. The four-finger case must prove both acceptance of 4 and rejection of 3/5:

```swift
func testFourFingerConfigurationRequiresExactlyFourTouches() {
    var recognizer = MiddleClickRecognizer(tapEnabled: true, fingerCount: 4)
    XCTAssertFalse(completeTap(&recognizer, touchCount: 3).tapCandidate)
    XCTAssertTrue(completeTap(&recognizer, touchCount: 4).tapCandidate)
    XCTAssertFalse(completeTap(&recognizer, touchCount: 5).tapCandidate)
}
```

Also test that `tapEnabled: false` still reports `chordActive == true` for the selected count so physical Click shares the configuration.

- [ ] **Step 2: Run the recognizer tests and verify RED**

Run: `swift test --filter MiddleClickRecognizerTests`

Expected: compilation fails because the recognizer has no `fingerCount` initializer parameter.

- [ ] **Step 3: Inject the count into the recognizer**

Replace the static exact count with an immutable validated instance value:

```swift
private let exactTouchCount: Int

public init(tapEnabled: Bool, fingerCount: Int = MiddleClickSettings.default.fingerCount) {
    self.tapEnabled = tapEnabled
    self.exactTouchCount = MiddleClickSettings.supportedFingerCounts.contains(fingerCount)
        ? fingerCount
        : MiddleClickSettings.default.fingerCount
}
```

Use `exactTouchCount` for maximum-count, equality, and unique-ID checks. Do not change timing, movement, session, or terminal-reason rules.

- [ ] **Step 4: Run the recognizer tests and verify GREEN**

Run: `swift test --filter MiddleClickRecognizerTests`

Expected: all recognizer tests pass.

- [ ] **Step 5: Commit the recognizer slice**

```bash
git add Sources/SlidrFreeCore/MiddleClickRecognizer.swift Tests/SlidrFreeCoreTests/MiddleClickRecognizerTests.swift
git commit -m "feat: recognize configured middle-click fingers"
```

### Task 3: Route count changes through the safe pipeline lifecycle

**Files:**
- Modify: `Tests/SlidrFreeAppTests/InputPipelineLifecycleTests.swift`
- Modify: `Sources/SlidrFreeApp/InputPipelineStatus.swift`

- [ ] **Step 1: Write failing pipeline propagation tests**

Extend the fake pipeline to record `settings.middleClick.fingerCount`. Assert the initial pipeline receives 4, then changing only the count to 3 quiesces the first pipeline, releases one pending transformed Down, and creates a fresh generation with 3:

```swift
settings.middleClick.fingerCount = 3
harness.coordinator.update(settings: settings, permission: .granted)
XCTAssertTrue(first.didQuiesce)
XCTAssertEqual(first.releaseCount, 1)
XCTAssertEqual(harness.factory.instances.map(\.fingerCount), [4, 3])
```

- [ ] **Step 2: Run the lifecycle tests and verify RED**

Run: `swift test --filter InputPipelineLifecycleTests`

Expected: the new fake-pipeline assertions fail because count is not recorded or injected into the recognizer.

- [ ] **Step 3: Inject the value during pipeline construction**

Construct the recognizer with both settings fields:

```swift
middleRecognizer = MiddleClickRecognizer(
    tapEnabled: settings.middleClick.tapEnabled,
    fingerCount: settings.middleClick.fingerCount
)
```

Keep the existing `$0.middleClick != newSettings.middleClick` restart predicate; the new Equatable property makes a count change use the established quiesce transaction.

- [ ] **Step 4: Run lifecycle and core tests and verify GREEN**

Run: `swift test --filter InputPipelineLifecycleTests && swift test --filter MiddleClickRecognizerTests`

Expected: both suites pass.

- [ ] **Step 5: Commit the lifecycle slice**

```bash
git add Sources/SlidrFreeApp/InputPipelineStatus.swift Tests/SlidrFreeAppTests/InputPipelineLifecycleTests.swift
git commit -m "feat: reconfigure pipeline for finger count"
```

### Task 4: Add the 2/3/4 Settings control and bilingual guidance

**Files:**
- Modify: `Sources/SlidrFreeApp/SettingsView.swift`
- Modify: `Resources/en.lproj/Localizable.strings`
- Modify: `Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/SlidrFreeCoreChecks/main.swift`

- [ ] **Step 1: Add a failing executable copy/default check**

Extend `SlidrFreeCoreChecks` to require the default count to be 4, a configured four-finger Tap to succeed, and a three-finger session under that configuration not to emit Tap.

- [ ] **Step 2: Run the core checks and verify RED**

Run: `swift run SlidrFreeCoreChecks`

Expected: the existing three-finger-default smoke check fails after Task 1, or the new four-finger check fails until its recognizer construction is updated.

- [ ] **Step 3: Implement the Settings UI and copy**

Add a segmented picker bound to `\.middleClick.fingerCount`:

```swift
Picker(NSLocalizedString("middle_click_finger_count", comment: ""), selection: binding(\.middleClick.fingerCount)) {
    ForEach(Array(MiddleClickSettings.supportedFingerCounts), id: \.self) { count in
        Text(String(count)).tag(count)
    }
}
.pickerStyle(.segmented)
.disabled(!store.settings.middleClick.isEnabled)
```

Replace fixed-count copy with count-neutral Tap/Click wording. Conditionally show `middle_click_two_finger_warning` for 2 and `middle_click_three_finger_drag_guidance` for 3. Keep status rows and layout unchanged.

- [ ] **Step 4: Update and run core checks**

Run: `swift run SlidrFreeCoreChecks`

Expected: exit 0 with all checks completed.

- [ ] **Step 5: Build the application target**

Run: `swift build --product SlidrFreeApp`

Expected: exit 0 with no Swift compile errors.

- [ ] **Step 6: Commit the UI slice**

```bash
git add Sources/SlidrFreeApp/SettingsView.swift Resources/en.lproj/Localizable.strings Resources/zh-Hans.lproj/Localizable.strings Sources/SlidrFreeCoreChecks/main.swift
git commit -m "feat: add middle-click finger selector"
```

### Task 5: Update public documentation and provenance

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/middle-click-provenance.md`

- [ ] **Step 1: Replace obsolete fixed-three claims**

Document the 2–4 range, exact matching, default 4, shared Tap/Click count, 2-finger warning, and four-finger recommendation for three-finger drag. Keep adjustable thresholds and `allowMoreFingers` explicitly out of scope.

- [ ] **Step 2: Extend the provenance record**

Record that the configurable behavior was derived only from public README/release/three-finger-drag documentation and the approved extension spec. State that no upstream source, resources, project files, or binaries were viewed or reused for this extension.

- [ ] **Step 3: Scan for stale public copy**

Run:

```bash
rg -n "fixed to exactly three|exactly three fingers|fixed-three|固定为恰好三指|只支持.*恰好三指|三指中键点击" README.md README.zh-CN.md Sources Resources docs/middle-click-provenance.md
```

Expected: no obsolete product claim remains; historical superseded design/plan files are intentionally not rewritten.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md README.zh-CN.md docs/middle-click-provenance.md
git commit -m "docs: explain configurable middle-click fingers"
```

### Task 6: Full verification, independent review, and GitHub publication

**Files:**
- Inspect: all changes since `71cb6c1`
- Update if necessary: files named by an actionable review finding

- [ ] **Step 1: Run formatting/diff sanity**

Run: `git diff --check 71cb6c1...HEAD && git status --short`

Expected: no whitespace errors and only intentional generated release artifacts, if any.

- [ ] **Step 2: Run the complete CI-equivalent suite**

Run:

```bash
swift run SlidrFreeCoreChecks
swift test
swift build
bash scripts/package-release.sh
bash scripts/verify-release.sh
bash scripts/test-verify-release-signature.sh
```

Expected: every command exits 0; XCTest reports zero failures; release verification reports both loose and archived apps valid with an ad-hoc signature.

- [ ] **Step 3: Run secret and provenance safety checks**

Run: `/Users/zhupin/.codex/hooks/secret-scan.sh <changed paths supported by the script>` after inspecting its usage.

Expected: no credential or secret finding in intended commit content.

- [ ] **Step 4: Request independent read-only review**

Give the reviewer the approved extension spec, diff range, and explicit checks for settings migration, exact-count recognition, lifecycle balance, UI copy, test gaps, and no upstream-source reuse. Fix every confirmed Critical/Important finding with a new failing test first, then rerun the relevant focused suite.

- [ ] **Step 5: Run final verification after review fixes**

Repeat the entire CI-equivalent suite from Step 2 and inspect `git diff --check`, `git status`, and `git log` fresh.

- [ ] **Step 6: Commit remaining intentional changes**

Use the GitHub-associated identity `Zhu Pin <288487787+zzp209@users.noreply.github.com>` and stage only files in this feature's scope.

- [ ] **Step 7: Push and update the existing PR**

Run:

```bash
gh auth status
git push -u origin codex/middleclick-integration
gh pr view 2 --repo YuriGao/slidr-free --json url,state,isDraft,headRefName,statusCheckRollup
```

Expected: push succeeds, PR #2 remains open/ready, and its head is `codex/middleclick-integration`.

- [ ] **Step 8: Wait for GitHub Actions**

Run: `gh pr checks 2 --repo YuriGao/slidr-free --watch`

Expected: all required checks pass before reporting completion.
