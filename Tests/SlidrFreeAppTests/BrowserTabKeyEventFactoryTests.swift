import XCTest
import SlidrFreeCore
@testable import SlidrFreeApp

final class BrowserTabKeyEventFactoryTests: XCTestCase {
    func testAllowsSafariChromeAndEdgeBundleIdentifiers() {
        XCTAssertTrue(BrowserTabKeyEventFactory.isSupportedBrowser(bundleIdentifier: "com.apple.Safari"))
        XCTAssertTrue(BrowserTabKeyEventFactory.isSupportedBrowser(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(BrowserTabKeyEventFactory.isSupportedBrowser(bundleIdentifier: "com.microsoft.edgemac"))
        XCTAssertFalse(BrowserTabKeyEventFactory.isSupportedBrowser(bundleIdentifier: "com.apple.finder"))
        XCTAssertFalse(BrowserTabKeyEventFactory.isSupportedBrowser(bundleIdentifier: nil))
    }

    func testNextTabUsesCommandShiftRightBracketEvents() throws {
        let events = try XCTUnwrap(BrowserTabKeyEventFactory.events(for: .next))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [30, 30])
        XCTAssertTrue(events.allSatisfy { $0.flags.contains(.maskCommand) })
        XCTAssertTrue(events.allSatisfy { $0.flags.contains(.maskShift) })
    }

    func testPreviousTabUsesCommandShiftLeftBracketEvents() throws {
        let events = try XCTUnwrap(BrowserTabKeyEventFactory.events(for: .previous))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [33, 33])
        XCTAssertTrue(events.allSatisfy { $0.flags.contains(.maskCommand) })
        XCTAssertTrue(events.allSatisfy { $0.flags.contains(.maskShift) })
    }
}
