import XCTest
@testable import SlidrFreeCore

final class EdgeAssignmentMigrationTests: XCTestCase {
    func testConfiguredGestureReflectsDirectAssignmentsAndMiddleClick() {
        var settings = AppSettings.default
        settings.edgeAssignments = EdgeAssignments(left: .none, right: .none, top: .none)
        settings.middleClick.isEnabled = false
        XCTAssertFalse(settings.hasConfiguredGesture)

        settings.edgeAssignments.left = .brightness
        XCTAssertTrue(settings.hasConfiguredGesture)
        settings.edgeAssignments.left = .none
        settings.middleClick.isEnabled = true
        XCTAssertTrue(settings.hasConfiguredGesture)

        settings.middleClick.isEnabled = false
        settings.cornerAppBindings.topLeft = ApplicationBinding(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            applicationPath: "/Applications/Example.app"
        )
        XCTAssertTrue(settings.hasConfiguredGesture)
    }

    func testEveryLegacyToggleCombinationMapsWithoutChangingBehavior() throws {
        for volume in [false, true] {
            for brightness in [false, true] {
                for tabs in [false, true] {
                    for swap in [false, true] {
                        let data = Data("""
                        {"isAppEnabled":true,"launchAtLogin":false,"features":{"volumeEdgeGesture":\(volume),"brightnessEdgeGesture":\(brightness),"browserTabEdgeGesture":\(tabs),"swapSides":\(swap)},"gesture":{"edgeWidthPercent":0.1}}
                        """.utf8)
                        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
                        let expectedLeft: SideEdgeAction = swap ? (volume ? .volume : .none) : (brightness ? .brightness : .none)
                        let expectedRight: SideEdgeAction = swap ? (brightness ? .brightness : .none) : (volume ? .volume : .none)
                        XCTAssertEqual(decoded.edgeAssignments.left, expectedLeft)
                        XCTAssertEqual(decoded.edgeAssignments.right, expectedRight)
                        XCTAssertEqual(decoded.edgeAssignments.top, tabs ? .browserTabs : .none)
                    }
                }
            }
        }
    }

    func testPersistedDirectAssignmentsWinOverLegacyFields() throws {
        var settings = AppSettings.default
        settings.features = FeatureToggles(volumeEdgeGesture: false, brightnessEdgeGesture: false, browserTabEdgeGesture: false, swapSides: true)
        settings.edgeAssignments = EdgeAssignments(left: .volume, right: .brightness, top: .browserTabs)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.edgeAssignments, settings.edgeAssignments)
    }
}
