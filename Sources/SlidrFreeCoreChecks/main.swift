import SlidrFreeCore

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
    try check(settings.features.cursorFreeze, "Cursor freeze should be enabled by default")
    try check(!settings.launchAtLogin, "Launch at login should be disabled by default")
}

private func testValidationClampsGestureSettings() throws {
    var settings = AppSettings.default
    settings.gesture.edgeWidthPercent = 0.50
    settings.gesture.sensitivity = -2.0
    settings.gesture.typingCooldownSeconds = 5.0

    let validated = settings.validated()

    try checkEqual(validated.gesture.edgeWidthPercent, 0.20, accuracy: 0.0001, "Edge width percent should clamp")
    try checkEqual(validated.gesture.sensitivity, 0.10, accuracy: 0.0001, "Sensitivity should clamp")
    try checkEqual(validated.gesture.typingCooldownSeconds, 2.0, accuracy: 0.0001, "Typing cooldown should clamp")
}

let checks: [(String, () throws -> Void)] = [
    ("default settings", testDefaultSettingsEnableAllFirstVersionFeaturesIndividually),
    ("gesture validation", testValidationClampsGestureSettings)
]

do {
    for (name, run) in checks {
        try run()
        print("PASS: \(name)")
    }
    print("All SlidrFreeCore checks passed")
} catch {
    print("FAIL: \(error)")
    preconditionFailure("SlidrFreeCoreChecks failed")
}
