import XCTest
@testable import SlidrFreeCore

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsEnableAllFirstVersionFeaturesIndividually() {
        let settings = AppSettings.default

        XCTAssertTrue(settings.isAppEnabled)
        XCTAssertTrue(settings.features.volumeEdgeGesture)
        XCTAssertTrue(settings.features.brightnessEdgeGesture)
        XCTAssertTrue(settings.features.middleClick)
        XCTAssertTrue(settings.features.fineControl)
        XCTAssertFalse(settings.features.swapSides)
        XCTAssertFalse(settings.features.bottomQuarterOnly)
        XCTAssertTrue(settings.features.smartTypingDetection)
        XCTAssertTrue(settings.features.cursorFreeze)
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testValidationClampsGestureSettings() {
        var settings = AppSettings.default
        settings.gesture.edgeWidthPercent = 0.50
        settings.gesture.sensitivity = -2.0
        settings.gesture.typingCooldownSeconds = 5.0

        let validated = settings.validated()

        XCTAssertEqual(validated.gesture.edgeWidthPercent, 0.20, accuracy: 0.0001)
        XCTAssertEqual(validated.gesture.sensitivity, 0.10, accuracy: 0.0001)
        XCTAssertEqual(validated.gesture.typingCooldownSeconds, 2.0, accuracy: 0.0001)
    }
}
