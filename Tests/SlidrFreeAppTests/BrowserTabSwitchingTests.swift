import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class BrowserTabSwitchingTests: XCTestCase {
    func testBoundaryStateValidatesIndexAndDirection() {
        XCTAssertNil(BrowserTabState(activeIndex: 0, tabCount: 3))
        XCTAssertNil(BrowserTabState(activeIndex: 4, tabCount: 3))
        XCTAssertNil(BrowserTabState(activeIndex: 1, tabCount: 0))

        let first = BrowserTabState(activeIndex: 1, tabCount: 3)!
        XCTAssertTrue(first.permitsSwitch(.next))
        XCTAssertFalse(first.permitsSwitch(.previous))

        let middle = BrowserTabState(activeIndex: 2, tabCount: 3)!
        XCTAssertTrue(middle.permitsSwitch(.next))
        XCTAssertTrue(middle.permitsSwitch(.previous))

        let last = BrowserTabState(activeIndex: 3, tabCount: 3)!
        XCTAssertFalse(last.permitsSwitch(.next))
        XCTAssertTrue(last.permitsSwitch(.previous))
    }

    func testWrappingSwitchSkipsBoundaryLookupAndPostsEvent() {
        var lookupCount = 0
        var posted: [BrowserTabDirection] = []
        let control = makeControl(
            stateProvider: { _ in
                lookupCount += 1
                return nil
            },
            eventPoster: { direction in
                posted.append(direction)
                return true
            }
        )

        XCTAssertEqual(control.switchBrowserTab(direction: .next, wrapsAround: true), .success)
        XCTAssertEqual(lookupCount, 0)
        XCTAssertEqual(posted, [.next])
    }

    func testNonWrappingSwitchStopsAtBoundaryWithoutPostingEvent() {
        var posted: [BrowserTabDirection] = []
        let control = makeControl(
            stateProvider: { _ in BrowserTabState(activeIndex: 3, tabCount: 3) },
            eventPoster: { direction in
                posted.append(direction)
                return true
            }
        )

        XCTAssertEqual(
            control.switchBrowserTab(direction: .next, wrapsAround: false),
            .unsupported("Browser tab is already at the boundary")
        )
        XCTAssertTrue(posted.isEmpty)
    }

    func testNonWrappingSwitchPostsEventAwayFromBoundary() {
        var posted: [BrowserTabDirection] = []
        let control = makeControl(
            stateProvider: { identifier in
                XCTAssertEqual(identifier, "com.google.Chrome")
                return BrowserTabState(activeIndex: 2, tabCount: 3)
            },
            eventPoster: { direction in
                posted.append(direction)
                return true
            }
        )

        XCTAssertEqual(control.switchBrowserTab(direction: .previous, wrapsAround: false), .success)
        XCTAssertEqual(posted, [.previous])
    }

    func testNonWrappingSwitchFailsClosedWhenBoundaryCannotBeRead() {
        var posted: [BrowserTabDirection] = []
        let control = makeControl(
            stateProvider: { _ in nil },
            eventPoster: { direction in
                posted.append(direction)
                return true
            }
        )

        XCTAssertEqual(
            control.switchBrowserTab(direction: .next, wrapsAround: false),
            .failed("Browser tab boundary could not be determined")
        )
        XCTAssertTrue(posted.isEmpty)
    }

    private func makeControl(
        stateProvider: @escaping (String) -> BrowserTabState?,
        eventPoster: @escaping (BrowserTabDirection) -> Bool
    ) -> SystemControl {
        SystemControl(
            frontmostApplicationProvider: {
                FrontmostApplicationIdentity(
                    bundleIdentifier: "com.google.Chrome",
                    processIdentifier: 42
                )
            },
            browserTabStateProvider: stateProvider,
            browserTabEventPoster: eventPoster
        )
    }
}
