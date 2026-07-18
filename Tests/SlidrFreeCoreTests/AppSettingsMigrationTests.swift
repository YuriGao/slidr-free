import XCTest
@testable import SlidrFreeCore

final class AppSettingsMigrationTests: XCTestCase {
    func testDecodingV02SettingsPreservesExistingValuesAndAddsDefaultMiddleClick() throws {
        let payload = try XCTUnwrap(
            """
            {
              "isAppEnabled": false,
              "launchAtLogin": true,
              "features": {
                "volumeEdgeGesture": false,
                "brightnessEdgeGesture": true,
                "browserTabEdgeGesture": false,
                "swapSides": true
              },
              "gesture": {
                "edgeWidthPercent": 0.14,
                "physicalStepDistance": 0.07,
                "physicalStepIntervalSeconds": 0.11,
                "tabSwitchStepIntervalSeconds": 0.31,
                "horizontalDominanceRatio": 2.25
              }
            }
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)

        XCTAssertFalse(decoded.isAppEnabled)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertEqual(
            decoded.features,
            FeatureToggles(
                volumeEdgeGesture: false,
                brightnessEdgeGesture: true,
                browserTabEdgeGesture: false,
                swapSides: true
            )
        )
        XCTAssertEqual(
            decoded.gesture,
            GestureSettings(
                edgeWidthPercent: 0.14,
                physicalStepDistance: 0.07,
                physicalStepIntervalSeconds: 0.11,
                tabSwitchStepIntervalSeconds: 0.31,
                horizontalDominanceRatio: 2.25
            )
        )
        XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: false, tapEnabled: true, fingerCount: 4))
        XCTAssertEqual(decoded.cornerAppBindings, .empty)
        XCTAssertEqual(decoded.gesture.cornerTriggerPercent, GestureSettings.defaultCornerTriggerPercent)
        XCTAssertEqual(decoded.gesture.cornerMovementTolerancePercent, GestureSettings.defaultCornerMovementTolerancePercent)
        XCTAssertEqual(decoded.gesture.cornerDoubleTapIntervalSeconds, GestureSettings.defaultCornerDoubleTapIntervalSeconds)
        XCTAssertNotEqual(decoded.gesture.cornerTriggerPercent, decoded.gesture.edgeWidthPercent)
    }

    func testCornerAppBindingsRoundTripIndependently() throws {
        var original = AppSettings.default
        original.cornerAppBindings = CornerAppBindings(
            topLeft: app("com.example.one", "One", "/Applications/One.app"),
            topRight: app("com.example.two", "Two", "/Applications/Two.app"),
            bottomLeft: app("com.example.three", "Three", "/Applications/Three.app"),
            bottomRight: app("com.example.four", "Four", "/Applications/Four.app")
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.cornerAppBindings, original.cornerAppBindings)
    }

    func testValidationRemovesIncompleteCornerBindingsAndTrimsValidValues() {
        var settings = AppSettings.default
        settings.cornerAppBindings = CornerAppBindings(
            topLeft: app("", "Missing ID", "/Applications/Missing.app"),
            topRight: app("com.example.missing-name", "", "/Applications/Missing.app"),
            bottomLeft: app("com.example.missing-path", "Missing path", ""),
            bottomRight: app("  com.example.valid  ", "  Valid  ", "  /Applications/Valid.app  ")
        )

        let validated = settings.validated()

        XCTAssertNil(validated.cornerAppBindings.topLeft)
        XCTAssertNil(validated.cornerAppBindings.topRight)
        XCTAssertNil(validated.cornerAppBindings.bottomLeft)
        XCTAssertEqual(
            validated.cornerAppBindings.bottomRight,
            app("com.example.valid", "Valid", "/Applications/Valid.app")
        )
    }

    func testValidationRemovesNonApplicationCornerBinding() {
        var settings = AppSettings.default
        settings.cornerAppBindings.topLeft = app(
            "com.example.document",
            "Document",
            "/tmp/document.txt"
        )

        XCTAssertNil(settings.validated().cornerAppBindings.topLeft)
    }

    func testValidationRemovesRelativeApplicationPath() {
        var settings = AppSettings.default
        settings.cornerAppBindings.topLeft = app(
            "com.example.app",
            "Example",
            "Applications/Example.app"
        )

        XCTAssertNil(settings.validated().cornerAppBindings.topLeft)
    }

    func testLegacySharedStepDistanceMigratesToEveryEdge() throws {
        let decoded = try decodeSettings(gestureJSON: """
        {
          "edgeWidthPercent": 0.10,
          "physicalStepDistance": 0.17,
          "physicalStepIntervalSeconds": 0.08,
          "tabSwitchStepIntervalSeconds": 0.20,
          "horizontalDominanceRatio": 1.5
        }
        """)

        XCTAssertEqual(decoded.gesture.leftPhysicalStepDistance, 0.17)
        XCTAssertEqual(decoded.gesture.rightPhysicalStepDistance, 0.17)
        XCTAssertEqual(decoded.gesture.topPhysicalStepDistance, 0.17)
    }

    func testIndependentEdgeStepDistancesRoundTripWithoutLegacyField() throws {
        var original = AppSettings.default
        original.gesture.leftPhysicalStepDistance = 0.04
        original.gesture.rightPhysicalStepDistance = 0.11
        original.gesture.topPhysicalStepDistance = 0.23

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let gesture = try XCTUnwrap(root["gesture"] as? [String: Any])

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(gesture["leftPhysicalStepDistance"] as? Double, 0.04)
        XCTAssertEqual(gesture["rightPhysicalStepDistance"] as? Double, 0.11)
        XCTAssertEqual(gesture["topPhysicalStepDistance"] as? Double, 0.23)
        XCTAssertNil(gesture["physicalStepDistance"])
    }

    func testCornerTriggerPercentRoundTripsIndependentlyFromEdgeWidth() throws {
        var original = AppSettings.default
        original.gesture.edgeWidthPercent = 0.06
        original.gesture.cornerTriggerPercent = 0.18
        original.gesture.cornerMovementTolerancePercent = 0.08
        original.gesture.cornerDoubleTapIntervalSeconds = 0.95

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let gesture = try XCTUnwrap(root["gesture"] as? [String: Any])

        XCTAssertEqual(decoded.gesture.edgeWidthPercent, 0.06)
        XCTAssertEqual(decoded.gesture.cornerTriggerPercent, 0.18)
        XCTAssertEqual(decoded.gesture.cornerMovementTolerancePercent, 0.08)
        XCTAssertEqual(decoded.gesture.cornerDoubleTapIntervalSeconds, 0.95)
        XCTAssertEqual(gesture["edgeWidthPercent"] as? Double, 0.06)
        XCTAssertEqual(gesture["cornerTriggerPercent"] as? Double, 0.18)
        XCTAssertEqual(gesture["cornerMovementTolerancePercent"] as? Double, 0.08)
        XCTAssertEqual(gesture["cornerDoubleTapIntervalSeconds"] as? Double, 0.95)
    }

    func testValidationClampsCornerTriggerPercentWithoutChangingEdgeWidth() {
        var settings = AppSettings.default
        settings.gesture.edgeWidthPercent = 0.08
        settings.gesture.cornerTriggerPercent = 0.50
        settings.gesture.cornerMovementTolerancePercent = 0.50
        settings.gesture.cornerDoubleTapIntervalSeconds = 2.0

        let validated = settings.validated()

        XCTAssertEqual(validated.gesture.edgeWidthPercent, 0.08)
        XCTAssertEqual(validated.gesture.cornerTriggerPercent, GestureSettings.cornerTriggerPercentRange.upperBound)
        XCTAssertEqual(validated.gesture.cornerMovementTolerancePercent, GestureSettings.cornerMovementTolerancePercentRange.upperBound)
        XCTAssertEqual(validated.gesture.cornerDoubleTapIntervalSeconds, GestureSettings.cornerDoubleTapIntervalRange.upperBound)
    }

    func testDecodingMiddleClickWithOnlyIsEnabledDefaultsTapEnabled() throws {
        let decoded = try decodeSettings(middleClickJSON: """
        {"isEnabled": true}
        """)

        XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: true, tapEnabled: true, fingerCount: 4))
    }

    func testDecodingMiddleClickWithOnlyTapEnabledDefaultsIsEnabled() throws {
        let decoded = try decodeSettings(middleClickJSON: """
        {"tapEnabled": false}
        """)

        XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: false, tapEnabled: false, fingerCount: 4))
    }

    func testValidationPreservesMiddleClickBooleans() throws {
        let decoded = try decodeSettings(middleClickJSON: """
        {"isEnabled": true, "tapEnabled": false}
        """)

        XCTAssertEqual(decoded.validated().middleClick, MiddleClickSettings(isEnabled: true, tapEnabled: false, fingerCount: 4))
    }

    func testMiddleClickDefaultsToFourFingers() {
        XCTAssertEqual(MiddleClickSettings.default.fingerCount, 4)
    }

    func testSupportedFingerCountsRoundTrip() throws {
        for fingerCount in 2...4 {
            let original = MiddleClickSettings(isEnabled: true, tapEnabled: false, fingerCount: fingerCount)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(MiddleClickSettings.self, from: data)

            XCTAssertEqual(decoded, original)
        }
    }

    func testUnsupportedPersistedFingerCountsFallBackToFour() throws {
        for fingerCount in [1, 5] {
            let decoded = try decodeSettings(middleClickJSON: """
            {"isEnabled": true, "tapEnabled": false, "fingerCount": \(fingerCount)}
            """)

            XCTAssertEqual(decoded.middleClick.fingerCount, 4)
            XCTAssertTrue(decoded.middleClick.isEnabled)
            XCTAssertFalse(decoded.middleClick.tapEnabled)
        }
    }

    func testDirectFingerCountMutationNormalizesBeforeEncoding() throws {
        var settings = MiddleClickSettings.default
        settings.fingerCount = 5

        XCTAssertEqual(settings.fingerCount, 4)

        let data = try JSONEncoder().encode(settings)
        let decodedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decodedJSON["fingerCount"] as? Int, 4)
    }

    private func decodeSettings(middleClickJSON: String) throws -> AppSettings {
        try decodeSettings(
            gestureJSON: """
            {
              "edgeWidthPercent": 0.10,
              "physicalStepDistance": 0.05,
              "physicalStepIntervalSeconds": 0.08,
              "tabSwitchStepIntervalSeconds": 0.20,
              "horizontalDominanceRatio": 1.5
            }
            """,
            middleClickJSON: middleClickJSON
        )
    }

    private func decodeSettings(
        gestureJSON: String,
        middleClickJSON: String = #"{"isEnabled": false, "tapEnabled": true, "fingerCount": 4}"#
    ) throws -> AppSettings {
        let payload = try XCTUnwrap(
            """
            {
              "isAppEnabled": true,
              "launchAtLogin": false,
              "features": {
                "volumeEdgeGesture": true,
                "brightnessEdgeGesture": true,
                "browserTabEdgeGesture": true,
                "swapSides": false
              },
              "gesture": \(gestureJSON),
              "middleClick": \(middleClickJSON)
            }
            """.data(using: .utf8)
        )

        return try JSONDecoder().decode(AppSettings.self, from: payload)
    }

    private func app(_ identifier: String, _ name: String, _ path: String) -> ApplicationBinding {
        ApplicationBinding(bundleIdentifier: identifier, displayName: name, applicationPath: path)
    }
}
