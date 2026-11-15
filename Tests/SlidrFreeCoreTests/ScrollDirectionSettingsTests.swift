import XCTest
@testable import SlidrFreeCore

final class ScrollDirectionSettingsTests: XCTestCase {
    func testContinuousDeltasAreTreatedAsTrackpadAndDiscreteOnesAsMouse() {
        let trackpad = ScrollEventClassification(isContinuous: true, verticalDelta: -3)
        let mouse = ScrollEventClassification(isContinuous: false, verticalDelta: -3)

        XCTAssertEqual(trackpad.deviceKind, .trackpad)
        XCTAssertEqual(mouse.deviceKind, .mouse)
    }

    func testGestureOrMomentumPhaseWithoutContinuousFlagStillCountsAsTrackpad() {
        XCTAssertEqual(
            ScrollEventClassification(isContinuous: false, scrollPhase: 2, verticalDelta: 4).deviceKind,
            .trackpad
        )
        XCTAssertEqual(
            ScrollEventClassification(isContinuous: false, momentumPhase: 1, verticalDelta: 2).deviceKind,
            .trackpad
        )
    }

    func testDefaultSettingsInvertNothing() {
        let settings = ScrollDirectionSettings.default
        XCTAssertFalse(settings.isActive)
        for isContinuous in [true, false] {
            XCTAssertEqual(
                settings.decision(for: ScrollEventClassification(isContinuous: isContinuous, verticalDelta: 8)),
                .identity
            )
        }
    }

    func testInvertingMouseWheelLeavesTrackpadUntouched() {
        let settings = ScrollDirectionSettings(invertMouseWheel: true)

        XCTAssertEqual(
            settings.decision(for: ScrollEventClassification(isContinuous: false, verticalDelta: -2)),
            ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: false)
        )
        XCTAssertEqual(
            settings.decision(for: ScrollEventClassification(isContinuous: true, verticalDelta: -2)),
            .identity
        )
        XCTAssertTrue(settings.isActive)
    }

    func testInvertingTrackpadLeavesMouseWheelUntouched() {
        let settings = ScrollDirectionSettings(invertTrackpad: true)

        XCTAssertEqual(
            settings.decision(for: ScrollEventClassification(isContinuous: true, verticalDelta: 5)),
            ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: false)
        )
        XCTAssertEqual(
            settings.decision(for: ScrollEventClassification(isContinuous: false, verticalDelta: 5)),
            .identity
        )
    }

    func testHorizontalInversionFollowsTheDeviceInversion() {
        let settings = ScrollDirectionSettings(invertMouseWheel: true, invertHorizontal: true)

        XCTAssertEqual(
            settings.decision(for: ScrollEventClassification(isContinuous: false, horizontalDelta: 3)),
            ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: true)
        )
        // Horizontal preference alone must not arm anything.
        XCTAssertFalse(ScrollDirectionSettings(invertHorizontal: true).isActive)
        XCTAssertEqual(
            ScrollDirectionSettings(invertHorizontal: true)
                .decision(for: ScrollEventClassification(isContinuous: false, verticalDelta: 3)),
            .identity
        )
    }

    func testPhaseOnlyFramesAreNeverInverted() {
        let settings = ScrollDirectionSettings(invertTrackpad: true, invertHorizontal: true)
        let began = ScrollEventClassification(isContinuous: true, scrollPhase: 1)
        let ended = ScrollEventClassification(isContinuous: true, momentumPhase: 3)

        XCTAssertFalse(began.hasDelta)
        XCTAssertEqual(settings.decision(for: began), .identity)
        XCTAssertEqual(settings.decision(for: ended), .identity)
    }

    func testDecodingMissingKeysFallsBackToDisabledDirections() throws {
        let decoded = try JSONDecoder().decode(ScrollDirectionSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .default)

        let partial = try JSONDecoder().decode(
            ScrollDirectionSettings.self,
            from: Data(#"{"invertMouseWheel":true}"#.utf8)
        )
        XCTAssertTrue(partial.invertMouseWheel)
        XCTAssertFalse(partial.invertTrackpad)
        XCTAssertFalse(partial.invertHorizontal)
    }

    func testRoundTripKeepsEveryFlag() throws {
        let original = ScrollDirectionSettings(invertTrackpad: true, invertMouseWheel: false, invertHorizontal: true)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ScrollDirectionSettings.self, from: data), original)
    }

    func testLegacyAppSettingsPayloadDecodesWithDisabledScrollDirection() throws {
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
              }
            }
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)
        XCTAssertEqual(decoded.scrollDirection, .default)
        XCTAssertFalse(decoded.scrollDirection.isActive)
    }

    func testScrollDirectionAloneCountsAsAConfiguredFeature() {
        var settings = AppSettings.default
        settings.edgeAssignments = EdgeAssignments(left: .none, right: .none, top: .none)
        settings.middleClick.isEnabled = false
        settings.cornerAppBindings = .empty
        XCTAssertFalse(settings.hasConfiguredGesture)
        XCTAssertFalse(settings.hasConfiguredFeature)

        settings.scrollDirection = ScrollDirectionSettings(invertMouseWheel: true)
        XCTAssertFalse(settings.hasConfiguredGesture)
        XCTAssertTrue(settings.hasConfiguredFeature)
    }
}
