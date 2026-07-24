import XCTest
@testable import SlidrFreeApp

final class MenuBarRefreshGateTests: XCTestCase {
    func testGateSkipsEquivalentPresentationAndAcceptsSemanticChanges() {
        var gate = MenuBarRefreshGate()
        let ready = MenuBarPresentation(
            health: .ready,
            isAppEnabled: true,
            canToggle: true
        )

        XCTAssertTrue(gate.shouldRefresh(ready))
        XCTAssertFalse(gate.shouldRefresh(ready))
        XCTAssertTrue(gate.shouldRefresh(MenuBarPresentation(
            health: .disabledByUser,
            isAppEnabled: false,
            canToggle: true
        )))
        XCTAssertTrue(gate.shouldRefresh(MenuBarPresentation(
            health: .disabledByUser,
            isAppEnabled: false,
            canToggle: false
        )))
    }
}
