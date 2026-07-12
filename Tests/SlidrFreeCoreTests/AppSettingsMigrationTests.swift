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
        XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: false, tapEnabled: true))
    }

    func testDecodingMiddleClickWithOnlyIsEnabledDefaultsTapEnabled() throws {
        let decoded = try decodeSettings(middleClickJSON: """
        {"isEnabled": true}
        """)

        XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: true, tapEnabled: true))
    }

    func testDecodingMiddleClickWithOnlyTapEnabledDefaultsIsEnabled() throws {
        let decoded = try decodeSettings(middleClickJSON: """
        {"tapEnabled": false}
        """)

        XCTAssertEqual(decoded.middleClick, MiddleClickSettings(isEnabled: false, tapEnabled: false))
    }

    func testValidationPreservesMiddleClickBooleans() throws {
        let decoded = try decodeSettings(middleClickJSON: """
        {"isEnabled": true, "tapEnabled": false}
        """)

        XCTAssertEqual(decoded.validated().middleClick, MiddleClickSettings(isEnabled: true, tapEnabled: false))
    }

    private func decodeSettings(middleClickJSON: String) throws -> AppSettings {
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
              "gesture": {
                "edgeWidthPercent": 0.10,
                "physicalStepDistance": 0.05,
                "physicalStepIntervalSeconds": 0.08,
                "tabSwitchStepIntervalSeconds": 0.20,
                "horizontalDominanceRatio": 1.5
              },
              "middleClick": \(middleClickJSON)
            }
            """.data(using: .utf8)
        )

        return try JSONDecoder().decode(AppSettings.self, from: payload)
    }
}
