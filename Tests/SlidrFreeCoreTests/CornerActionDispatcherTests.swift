import SlidrFreeCore
import XCTest

final class CornerActionDispatcherTests: XCTestCase {
    func testBoundCornerDispatchesItsApplication() {
        let binding = ApplicationBinding(
            bundleIdentifier: "com.example.bound",
            displayName: "Bound",
            applicationPath: "/Applications/Bound.app"
        )
        var settings = AppSettings.default
        settings.cornerAppBindings.topRight = binding

        XCTAssertEqual(
            ActionDispatcher(settings: settings).actions(for: .cornerDoubleTap(corner: .topRight)),
            [.toggleApplication(binding)]
        )
    }

    func testUnboundCornerDispatchesNothing() {
        XCTAssertTrue(
            ActionDispatcher(settings: .default)
                .actions(for: .cornerDoubleTap(corner: .bottomLeft))
                .isEmpty
        )
    }

    func testMiddleClickTapRequiresEnabledTapSetting() {
        var settings = AppSettings.default
        settings.middleClick.isEnabled = false
        settings.middleClick.tapEnabled = true
        XCTAssertTrue(ActionDispatcher(settings: settings).actions(for: .middleClickTap).isEmpty)

        settings.middleClick.isEnabled = true
        settings.middleClick.tapEnabled = false
        XCTAssertTrue(ActionDispatcher(settings: settings).actions(for: .middleClickTap).isEmpty)

        settings.middleClick.tapEnabled = true
        XCTAssertEqual(ActionDispatcher(settings: settings).actions(for: .middleClickTap), [.middleClick])
    }
}
