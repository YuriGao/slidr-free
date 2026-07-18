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
}
