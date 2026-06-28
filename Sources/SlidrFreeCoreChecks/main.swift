import SlidrFreeCore
import Foundation

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure.failed(message)
    }
}

private func checkEqual(
    _ actual: Double,
    _ expected: Double,
    accuracy: Double,
    _ message: String
) throws {
    if abs(actual - expected) > accuracy {
        throw CheckFailure.failed("\(message): expected \(expected), got \(actual)")
    }
}

private func checkEqual(_ actual: RecognizedGesture?, _ expected: RecognizedGesture?, _ message: String) throws {
    if actual != expected {
        throw CheckFailure.failed("\(message): expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

private func checkEqual(_ actual: [SystemAction], _ expected: [SystemAction], _ message: String) throws {
    if actual != expected {
        throw CheckFailure.failed("\(message): expected \(expected), got \(actual)")
    }
}

private func testPermissionSnapshotCanListenRequiresBothPermissions() throws {
    let cases: [(PermissionSnapshot, Bool)] = [
        (PermissionSnapshot(accessibility: .granted, inputMonitoring: .granted), true),
        (PermissionSnapshot(accessibility: .granted, inputMonitoring: .denied), false),
        (PermissionSnapshot(accessibility: .denied, inputMonitoring: .granted), false),
        (PermissionSnapshot(accessibility: .unknown, inputMonitoring: .granted), false),
        (PermissionSnapshot(accessibility: .granted, inputMonitoring: .unknown), false),
        (PermissionSnapshot(accessibility: .denied, inputMonitoring: .denied), false)
    ]

    for (snapshot, expected) in cases {
        try check(
            snapshot.canListen == expected,
            "PermissionSnapshot.canListen should be \(expected) for accessibility=\(snapshot.accessibility.rawValue), inputMonitoring=\(snapshot.inputMonitoring.rawValue)"
        )
    }
}

private func testDefaultSettingsEnableAllFirstVersionFeaturesIndividually() throws {
    let settings = AppSettings.default

    try check(settings.isAppEnabled, "App should be enabled by default")
    try check(settings.features.volumeEdgeGesture, "Volume edge gesture should be enabled by default")
    try check(settings.features.brightnessEdgeGesture, "Brightness edge gesture should be enabled by default")
    try check(settings.features.middleClick, "Middle click should be enabled by default")
    try check(settings.features.fineControl, "Fine control should be enabled by default")
    try check(!settings.features.swapSides, "Swap sides should be disabled by default")
    try check(!settings.features.bottomQuarterOnly, "Bottom quarter only should be disabled by default")
    try check(settings.features.smartTypingDetection, "Smart typing detection should be enabled by default")
    try check(!settings.launchAtLogin, "Launch at login should be disabled by default")
    try checkEqual(settings.gesture.physicalStepDistance, 0.10, accuracy: 0.0001, "Physical step distance should default to 0.10")
    try checkEqual(settings.gesture.physicalStepIntervalSeconds, 0.08, accuracy: 0.0001, "Physical step interval should default to 0.08s")
}

private func testValidationClampsGestureSettings() throws {
    var settings = AppSettings.default
    settings.gesture.edgeWidthPercent = 0.50
    settings.gesture.sensitivity = -2.0
    settings.gesture.typingCooldownSeconds = 5.0
    settings.gesture.physicalStepDistance = 2.0
    settings.gesture.physicalStepIntervalSeconds = -1.0

    let validated = settings.validated()

    try checkEqual(validated.gesture.edgeWidthPercent, 0.20, accuracy: 0.0001, "Edge width percent should clamp")
    try checkEqual(validated.gesture.sensitivity, 0.10, accuracy: 0.0001, "Sensitivity should clamp")
    try checkEqual(validated.gesture.typingCooldownSeconds, 2.0, accuracy: 0.0001, "Typing cooldown should clamp")
    try checkEqual(validated.gesture.physicalStepDistance, 0.50, accuracy: 0.0001, "Physical step distance should clamp")
    try checkEqual(validated.gesture.physicalStepIntervalSeconds, 0.0, accuracy: 0.0001, "Physical step interval should clamp")
}

private func testSettingsDecodeMigratesMissingPhysicalStepFields() throws {
    let legacyJSON = """
    {
      "isAppEnabled": false,
      "launchAtLogin": true,
      "features": {
        "volumeEdgeGesture": true,
        "brightnessEdgeGesture": false,
        "middleClick": true,
        "fineControl": false,
        "swapSides": true,
        "bottomQuarterOnly": true,
        "smartTypingDetection": false
      },
      "gesture": {
        "edgeWidthPercent": 0.12,
        "sensitivity": 1.5,
        "normalStep": 2.0,
        "fineStep": 0.5,
        "typingCooldownSeconds": 0.7,
        "continuousWindowSeconds": 0.25
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

    try check(!decoded.isAppEnabled, "Legacy settings should preserve isAppEnabled")
    try check(decoded.launchAtLogin, "Legacy settings should preserve launchAtLogin")
    try check(!decoded.features.brightnessEdgeGesture, "Legacy settings should preserve feature toggles")
    try checkEqual(decoded.gesture.edgeWidthPercent, 0.12, accuracy: 0.0001, "Legacy gesture settings should preserve existing fields")
    try checkEqual(decoded.gesture.physicalStepDistance, AppSettings.default.gesture.physicalStepDistance, accuracy: 0.0001, "Missing physical step distance should decode to default")
    try checkEqual(decoded.gesture.physicalStepIntervalSeconds, AppSettings.default.gesture.physicalStepIntervalSeconds, accuracy: 0.0001, "Missing physical step interval should decode to default")
}

private func testGestureRecognition() throws {
    let screenSize = CGSize(width: 1000, height: 800)
    var recognizer = GestureRecognizer(settings: .default)

    try checkEqual(
        recognizer.process(.scroll(x: 50, y: 300, deltaY: 16, timestamp: 10, screenSize: screenSize)),
        nil,
        "Scroll events should not produce edge gestures"
    )

    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.30, pressure: 0.5, state: 4)], timestamp: 10.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.41, pressure: 0.5, state: 4)], timestamp: 10.1)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Physical left edge brightness increase should emit one step"
    )

    try checkEqual(
        recognizer.process(.scroll(x: 950, y: 300, deltaY: -8, timestamp: 11, screenSize: screenSize)),
        nil,
        "Right edge scroll should not control volume"
    )

    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 2, x: 0.95, y: 0.70)], timestamp: 11.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 2, x: 0.95, y: 0.58)], timestamp: 11.1)),
        .volume(direction: .decrease, magnitude: 1.0),
        "Physical right edge volume decrease"
    )

    var swappedSettings = AppSettings.default
    swappedSettings.features.swapSides = true
    recognizer = GestureRecognizer(settings: swappedSettings)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 3, x: 0.95, y: 0.20)], timestamp: 12.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 3, x: 0.95, y: 0.32)], timestamp: 12.1)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Swap sides should move physical brightness to right edge"
    )

    var bottomQuarterSettings = AppSettings.default
    bottomQuarterSettings.features.bottomQuarterOnly = true
    recognizer = GestureRecognizer(settings: bottomQuarterSettings)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 4, x: 0.05, y: 0.50)], timestamp: 13.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 4, x: 0.05, y: 0.62)], timestamp: 13.1)),
        nil,
        "Bottom-quarter filtering should suppress upper physical touches"
    )
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 4, x: 0.05, y: 0.76)], timestamp: 14.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 4, x: 0.05, y: 0.88)], timestamp: 14.1)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Bottom-quarter filtering should allow lower physical touches"
    )

    recognizer = GestureRecognizer(settings: .default)
    try checkEqual(recognizer.process(.keyDown(timestamp: 20)), nil, "Key down should not produce a gesture")
    try checkEqual(
        recognizer.process(.scroll(x: 50, y: 300, deltaY: 16, timestamp: 20.5, screenSize: screenSize)),
        nil,
        "Scroll gestures should remain suppressed during typing cooldown"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 5, x: 0.05, y: 0.30)], timestamp: 20.5)),
        nil,
        "Typing cooldown should suppress physical gestures"
    )

    recognizer = GestureRecognizer(settings: .default)
    try checkEqual(recognizer.process(.keyDown(timestamp: 50)), nil, "Key down should not produce a gesture")
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 6, x: 0.05, y: 0.10)], timestamp: 50.5)),
        nil,
        "Typing cooldown should suppress but record physical touch state"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 6, x: 0.05, y: 0.11)], timestamp: 51.1)),
        nil,
        "Physical touch state should stay fresh during typing cooldown"
    )

    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.20)], timestamp: 60.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.25)], timestamp: 60.1)),
        nil,
        "Physical movement below step threshold should not emit"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.31)], timestamp: 60.2)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Crossing physical step threshold should emit one brightness step"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.42)], timestamp: 60.23)),
        nil,
        "Physical step interval should suppress immediate repeated steps"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 7, x: 0.05, y: 0.53)], timestamp: 60.32)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Physical movement after interval should emit another step"
    )

    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 8, x: 0.05, y: 0.20)], timestamp: 61.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 8, x: 0.30, y: 0.40)], timestamp: 61.1)),
        nil,
        "Leaving the physical edge should reset accumulated movement"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 8, x: 0.05, y: 0.51)], timestamp: 61.2)),
        nil,
        "Re-entering the physical edge should establish a fresh baseline"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 8, x: 0.05, y: 0.62)], timestamp: 61.3)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Movement after physical edge re-entry baseline should emit"
    )

    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 13, x: 0.05, y: 0.20)], timestamp: 61.4))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 13, x: 0.95, y: 0.35)], timestamp: 61.5)),
        nil,
        "Direct physical edge change should establish a fresh baseline"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 13, x: 0.95, y: 0.23)], timestamp: 61.6)),
        .volume(direction: .decrease, magnitude: 1.0),
        "Movement after direct physical edge change baseline should emit"
    )

    recognizer = GestureRecognizer(settings: bottomQuarterSettings)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 10, x: 0.05, y: 0.76)], timestamp: 62.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 10, x: 0.05, y: 0.60)], timestamp: 62.1)),
        nil,
        "Leaving the bottom quarter should reset accumulated movement"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 10, x: 0.05, y: 0.76)], timestamp: 62.2)),
        nil,
        "Re-entering the bottom quarter should establish a fresh baseline"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 10, x: 0.05, y: 0.87)], timestamp: 62.3)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Movement after bottom-quarter re-entry baseline should emit"
    )

    recognizer = GestureRecognizer(settings: .default)
    _ = recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 11, x: 0.05, y: 0.20)], timestamp: 63.0))
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 12, x: 0.05, y: 0.35)], timestamp: 63.1)),
        nil,
        "Changing physical touch ID should reset accumulated movement"
    )
    try checkEqual(
        recognizer.process(.physicalTouchFrame(touches: [PhysicalTouch(id: 12, x: 0.05, y: 0.46)], timestamp: 63.2)),
        .brightness(direction: .increase, magnitude: 1.0),
        "Movement after physical touch ID baseline should emit"
    )

    var disabledSettings = AppSettings.default
    disabledSettings.isAppEnabled = false
    recognizer = GestureRecognizer(settings: disabledSettings)
    try checkEqual(
        recognizer.process(.scroll(x: 50, y: 300, deltaY: 16, timestamp: 30, screenSize: screenSize)),
        nil,
        "Disabled app should suppress gestures"
    )

    recognizer = GestureRecognizer(settings: .default)
    try checkEqual(
        recognizer.process(.middleClick(x: 400, y: 300, timestamp: 40)),
        .middleClick(x: 400, y: 300),
        "Middle click should be recognized"
    )
}

private func testActionDispatcher() throws {
    var dispatcher = ActionDispatcher(settings: .default)
    try checkEqual(
        dispatcher.actions(for: .brightness(direction: .increase, magnitude: 2.0)),
        [.adjustBrightness(delta: 0.70)],
        "Fine control should use fine step"
    )

    var normalSettings = AppSettings.default
    normalSettings.features.fineControl = false
    dispatcher = ActionDispatcher(settings: normalSettings)
    try checkEqual(
        dispatcher.actions(for: .volume(direction: .decrease, magnitude: 2.0)),
        [.adjustVolume(delta: -2.0)],
        "Normal control should use normal step when fine control is disabled"
    )

    try checkEqual(
        dispatcher.actions(for: .middleClick(x: 250, y: 125)),
        [.middleClick(x: 250, y: 125)],
        "Middle click should dispatch"
    )
}

let checks: [(String, () throws -> Void)] = [
    ("default settings", testDefaultSettingsEnableAllFirstVersionFeaturesIndividually),
    ("gesture validation", testValidationClampsGestureSettings),
    ("settings migration", testSettingsDecodeMigratesMissingPhysicalStepFields),
    ("gesture recognition", testGestureRecognition),
    ("action dispatch", testActionDispatcher),
    ("permission snapshot", testPermissionSnapshotCanListenRequiresBothPermissions)
]

do {
    for (name, run) in checks {
        try run()
        print("PASS: \(name)")
    }
    print("All SlidrFreeCore checks passed")
} catch {
    FileHandle.standardError.write("FAIL: \(error)\n".data(using: .utf8)!)
    preconditionFailure("SlidrFreeCoreChecks failed")
}
