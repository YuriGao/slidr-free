import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class AppHealthResolverTests: XCTestCase {
    private let resolver = AppHealthResolver()

    func testEachUserVisibleState() {
        XCTAssertEqual(resolve { $0.settings.experience.onboardingVersion = 0 }, .setupRequired)
        XCTAssertEqual(resolve { $0.settings.isAppEnabled = false }, .disabledByUser)
        XCTAssertEqual(resolve {
            $0.settings.edgeAssignments = EdgeAssignments(left: .none, right: .none, top: .none)
            $0.settings.middleClick.isEnabled = false
            $0.touchMonitor = .stopped
        }, .noGesturesConfigured)
        XCTAssertEqual(resolve { $0.permission = .denied }, .permissionRequired)
        XCTAssertEqual(resolve { $0.frameworkAvailable = false }, .hardwareUnavailable)
        XCTAssertEqual(resolve { $0.deviceAvailable = false }, .hardwareUnavailable)
        XCTAssertEqual(resolve { $0.touchMonitor = .starting }, .starting)
        XCTAssertEqual(resolve { $0.touchMonitor = .unavailable }, .degraded)
        XCTAssertEqual(resolve { $0.eventTap = .recoveryRequiresPipelineRestart }, .recovering)
        XCTAssertEqual(resolve(), .ready)
    }

    func testPriorityKeepsRecommendedActionDeterministic() {
        XCTAssertEqual(resolve {
            $0.settings.experience.onboardingVersion = 0
            $0.permission = .denied
            $0.deviceAvailable = false
        }, .setupRequired)
        XCTAssertEqual(resolve {
            $0.settings.isAppEnabled = false
            $0.permission = .denied
            $0.deviceAvailable = false
        }, .disabledByUser)
        XCTAssertEqual(resolve {
            $0.settings.edgeAssignments = EdgeAssignments(left: .none, right: .none, top: .none)
            $0.settings.middleClick.isEnabled = false
            $0.permission = .denied
            $0.deviceAvailable = false
        }, .noGesturesConfigured)
        XCTAssertEqual(resolve {
            $0.permission = .denied
            $0.deviceAvailable = false
            $0.touchMonitor = .unavailable
        }, .permissionRequired)
        XCTAssertEqual(resolve {
            $0.deviceAvailable = false
            $0.touchMonitor = .unavailable
        }, .hardwareUnavailable)
    }

    func testDisabledMiddleClickDoesNotMakeStoppedEventTapAFailure() {
        XCTAssertEqual(resolve {
            $0.settings.middleClick.isEnabled = false
            $0.eventTap = .stopped
        }, .ready)
    }

    func testCornerBindingAloneCountsAsConfiguredGesture() {
        XCTAssertEqual(resolve {
            $0.settings.edgeAssignments = EdgeAssignments(left: .none, right: .none, top: .none)
            $0.settings.middleClick.isEnabled = false
            $0.settings.cornerAppBindings.topLeft = ApplicationBinding(
                bundleIdentifier: "com.example.app",
                displayName: "Example",
                applicationPath: "/Applications/Example.app"
            )
        }, .ready)
    }

    private func resolve(_ mutate: (inout AppHealthInput) -> Void = { _ in }) -> AppHealthState {
        var input = AppHealthInput(
            settings: .default,
            permission: .granted,
            frameworkAvailable: true,
            deviceAvailable: true,
            touchMonitor: .running,
            eventTap: .running
        )
        mutate(&input)
        return resolver.resolve(input)
    }
}
