import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class SystemControlMiddleClickTests: XCTestCase {
    func testFrontmostWindowToggleRestoresAlreadyMinimizedWindow() {
        XCTAssertEqual(ApplicationWindowController.action(forIsMinimized: false), .minimize)
        XCTAssertEqual(ApplicationWindowController.action(forIsMinimized: true), .restore)
    }

    func testMiddleClickDelegatesToEmitterAndReturnsItsResult() {
        let emitter = MiddleClickEmitterSpy(result: .failed("test failure"))
        let control = SystemControl(middleClickEmitter: emitter)

        XCTAssertEqual(control.middleClick(), .failed("test failure"))
        XCTAssertEqual(emitter.emitCount, 1)
    }

    func testOpenApplicationPrefersBundleIdentifierResolution() {
        let resolved = URL(fileURLWithPath: "/Resolved/Example.app")
        var opened: [URL] = []
        let control = SystemControl(
            applicationURLResolver: { identifier in
                XCTAssertEqual(identifier, "com.example.app")
                return resolved
            },
            applicationOpener: { url in opened.append(url); return true }
        )

        XCTAssertEqual(control.activateOrMinimizeApplication(appBinding()), .success)
        XCTAssertEqual(opened, [resolved])
    }

    func testOpenApplicationFallsBackToStoredPath() {
        let fallback = URL(fileURLWithPath: "/Applications/Example.app")
        var opened: [URL] = []
        let control = SystemControl(
            applicationURLResolver: { _ in nil },
            applicationOpener: { url in opened.append(url); return true }
        )

        XCTAssertEqual(control.activateOrMinimizeApplication(appBinding()), .success)
        XCTAssertEqual(opened, [fallback])
    }

    func testOpenApplicationTriesStoredPathAfterResolvedURLFails() {
        let resolved = URL(fileURLWithPath: "/Resolved/Example.app")
        let fallback = URL(fileURLWithPath: "/Applications/Example.app")
        var opened: [URL] = []
        let control = SystemControl(
            applicationURLResolver: { _ in resolved },
            applicationOpener: { url in opened.append(url); return url == fallback }
        )

        XCTAssertEqual(control.activateOrMinimizeApplication(appBinding()), .success)
        XCTAssertEqual(opened, [resolved, fallback])
    }

    func testOpenApplicationFailsSafelyWhenNoCandidateOpens() {
        let control = SystemControl(
            applicationURLResolver: { _ in nil },
            applicationOpener: { _ in false }
        )

        XCTAssertEqual(
            control.activateOrMinimizeApplication(appBinding()),
            .failed("Configured application could not be opened")
        )
    }

    func testOpenApplicationDoesNotUseNonApplicationFallbackPath() {
        var opened: [URL] = []
        let control = SystemControl(
            applicationURLResolver: { _ in nil },
            applicationOpener: { url in opened.append(url); return true }
        )
        let binding = ApplicationBinding(
            bundleIdentifier: "com.example.document",
            displayName: "Document",
            applicationPath: "/tmp/document.txt"
        )

        XCTAssertEqual(
            control.activateOrMinimizeApplication(binding),
            .unsupported("Configured application is unavailable")
        )
        XCTAssertTrue(opened.isEmpty)
    }

    func testOpenApplicationDoesNotUseRelativeFallbackPath() {
        var opened: [URL] = []
        let control = SystemControl(
            applicationURLResolver: { _ in nil },
            applicationOpener: { url in opened.append(url); return true }
        )
        let binding = ApplicationBinding(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            applicationPath: "Applications/Example.app"
        )

        XCTAssertEqual(
            control.activateOrMinimizeApplication(binding),
            .unsupported("Configured application is unavailable")
        )
        XCTAssertTrue(opened.isEmpty)
    }

    func testFrontmostBoundApplicationMinimizesFocusedWindowWithoutOpening() {
        var minimizedProcessIdentifiers: [pid_t] = []
        var resolverCallCount = 0
        var opened: [URL] = []
        let control = SystemControl(
            frontmostApplicationProvider: {
                FrontmostApplicationIdentity(
                    bundleIdentifier: "com.example.app",
                    processIdentifier: 42
                )
            },
            applicationWindowToggler: { processIdentifier in
                minimizedProcessIdentifiers.append(processIdentifier)
                return true
            },
            applicationURLResolver: { _ in resolverCallCount += 1; return nil },
            applicationOpener: { url in opened.append(url); return true }
        )

        XCTAssertEqual(control.activateOrMinimizeApplication(appBinding()), .success)
        XCTAssertEqual(minimizedProcessIdentifiers, [42])
        XCTAssertEqual(resolverCallCount, 0)
        XCTAssertTrue(opened.isEmpty)
    }

    func testWindowToggleFailureDoesNotFallBackToOpeningFrontmostApplication() {
        var opened: [URL] = []
        let control = SystemControl(
            frontmostApplicationProvider: {
                FrontmostApplicationIdentity(
                    bundleIdentifier: "com.example.app",
                    processIdentifier: 42
                )
            },
            applicationWindowToggler: { _ in false },
            applicationURLResolver: { _ in URL(fileURLWithPath: "/Applications/Example.app") },
            applicationOpener: { url in opened.append(url); return true }
        )

        XCTAssertEqual(
            control.activateOrMinimizeApplication(appBinding()),
            .failed("Configured application window could not be toggled")
        )
        XCTAssertTrue(opened.isEmpty)
    }

    func testDifferentFrontmostApplicationStillOpensBoundApplication() {
        var minimizedProcessIdentifiers: [pid_t] = []
        var opened: [URL] = []
        let resolved = URL(fileURLWithPath: "/Applications/Example.app")
        let control = SystemControl(
            frontmostApplicationProvider: {
                FrontmostApplicationIdentity(
                    bundleIdentifier: "com.example.other",
                    processIdentifier: 7
                )
            },
            applicationWindowToggler: { processIdentifier in
                minimizedProcessIdentifiers.append(processIdentifier)
                return true
            },
            applicationURLResolver: { _ in resolved },
            applicationOpener: { url in opened.append(url); return true }
        )

        XCTAssertEqual(control.activateOrMinimizeApplication(appBinding()), .success)
        XCTAssertTrue(minimizedProcessIdentifiers.isEmpty)
        XCTAssertEqual(opened, [resolved])
    }

    private func appBinding() -> ApplicationBinding {
        ApplicationBinding(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            applicationPath: "/Applications/Example.app"
        )
    }
}

private final class MiddleClickEmitterSpy: MiddleClickEmitting {
    let result: SystemActionResult
    var emitCount = 0

    init(result: SystemActionResult) {
        self.result = result
    }

    func emitClick() -> SystemActionResult {
        emitCount += 1
        return result
    }
}
