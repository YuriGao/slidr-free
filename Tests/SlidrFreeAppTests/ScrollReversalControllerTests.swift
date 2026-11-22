import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class ScrollReversalControllerTests: XCTestCase {
    private var scheduled: [(delay: TimeInterval, work: () -> Void)] = []
    private var statuses: [ScrollDirectionTapStatus] = []
    private var taps: [FakeScrollTap] = []
    private var permission = PermissionState.granted

    private func makeController(startResult: Bool = true) -> ScrollReversalController {
        ScrollReversalController(
            makeTap: { [unowned self] settings, statusHandler in
                let tap = FakeScrollTap(settings: settings, statusHandler: statusHandler)
                tap.startResult = startResult
                self.taps.append(tap)
                return tap
            },
            refreshPermission: { [unowned self] in self.permission },
            statusHandler: { [unowned self] in self.statuses.append($0) },
            deliverOnMain: { $0() },
            schedule: { [unowned self] delay, work in
                self.scheduled.append((delay, work))
            }
        )
    }

    private func enabledSettings(invertMouse: Bool = true, invertTrackpad: Bool = false) -> AppSettings {
        var settings = AppSettings.default
        settings.scrollDirection = ScrollDirectionSettings(
            invertTrackpad: invertTrackpad,
            invertMouseWheel: invertMouse
        )
        return settings
    }

    /// Runs queued retries in order, including the ones they enqueue.
    private func drainScheduled() {
        var index = 0
        while index < scheduled.count {
            scheduled[index].work()
            index += 1
        }
    }

    func testStartsTheTapOnlyWhenEnabledActiveAndPermitted() {
        let controller = makeController()

        controller.update(settings: enabledSettings(), permission: .denied)
        XCTAssertTrue(taps.isEmpty)

        var paused = enabledSettings()
        paused.isAppEnabled = false
        controller.update(settings: paused, permission: .granted)
        XCTAssertTrue(taps.isEmpty)

        controller.update(settings: AppSettings.default, permission: .granted)
        XCTAssertTrue(taps.isEmpty)

        controller.update(settings: enabledSettings(), permission: .granted)
        XCTAssertEqual(taps.count, 1)
        XCTAssertTrue(taps[0].didStart)
        XCTAssertEqual(statuses, [.running])
    }

    func testUniformWheelSteppingAloneStartsTheTap() {
        let controller = makeController()
        var settings = AppSettings.default
        settings.scrollDirection = ScrollDirectionSettings(uniformWheel: true)

        controller.update(settings: settings, permission: .granted)

        XCTAssertEqual(taps.count, 1)
        XCTAssertTrue(taps[0].didStart)
        XCTAssertEqual(taps[0].settings.uniformWheel, true)
    }

    func testSettingChangeUpdatesTheExistingTapInsteadOfRestarting() {
        let controller = makeController()
        controller.update(settings: enabledSettings(), permission: .granted)

        controller.update(
            settings: enabledSettings(invertMouse: true, invertTrackpad: true),
            permission: .granted
        )

        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps[0].updates.last, ScrollDirectionSettings(invertTrackpad: true, invertMouseWheel: true))
    }

    func testDisablingEveryDirectionStopsTheTap() {
        let controller = makeController()
        controller.update(settings: enabledSettings(), permission: .granted)

        controller.update(settings: AppSettings.default, permission: .granted)

        XCTAssertEqual(taps.count, 1)
        XCTAssertTrue(taps[0].didStop)
        XCTAssertEqual(statuses, [.running, .stopped])
    }

    func testFailedStartReportsDegradedAndSchedulesARetry() {
        let controller = makeController(startResult: false)
        controller.update(settings: enabledSettings(), permission: .granted)

        XCTAssertEqual(statuses, [.degraded])
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].delay, 2, accuracy: 0.001)

        scheduled[0].work()
        XCTAssertEqual(taps.count, 2)
        XCTAssertEqual(statuses, [.degraded, .degraded])
    }

    func testRetriesStopAfterTheBudgetIsExhausted() {
        let controller = makeController(startResult: false)
        controller.update(settings: enabledSettings(), permission: .granted)

        drainScheduled()

        XCTAssertEqual(taps.count, 1 + 3)
    }

    func testDegradedStatusFromTheTapDropsItAndRetries() {
        let controller = makeController()
        controller.update(settings: enabledSettings(), permission: .granted)
        taps[0].report(.degraded)

        XCTAssertTrue(taps[0].didStop)
        XCTAssertEqual(statuses, [.running, .degraded])
        XCTAssertEqual(scheduled.count, 1)
    }

    func testSleepStopsTheTapAndWakeRestartsIt() {
        let controller = makeController()
        controller.update(settings: enabledSettings(), permission: .granted)

        controller.willSleep()
        XCTAssertTrue(taps[0].didStop)

        controller.didWake()
        XCTAssertEqual(taps.count, 2)
        XCTAssertTrue(taps[1].didStart)
    }

    func testTerminationStopsAndSuppressesFurtherStarts() {
        let controller = makeController()
        controller.update(settings: enabledSettings(), permission: .granted)

        controller.terminate()
        XCTAssertTrue(taps[0].didStop)

        controller.update(settings: enabledSettings(), permission: .granted)
        controller.didWake()
        XCTAssertEqual(taps.count, 1)
    }
}

private final class FakeScrollTap: ScrollDirectionTapLifecycle {
    private let statusHandler: (ScrollDirectionTapStatus) -> Void
    private(set) var settings: ScrollDirectionSettings
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var updates: [ScrollDirectionSettings] = []
    var startResult = true

    init(settings: ScrollDirectionSettings, statusHandler: @escaping (ScrollDirectionTapStatus) -> Void) {
        self.settings = settings
        self.statusHandler = statusHandler
    }

    func start() -> Bool {
        didStart = startResult
        return startResult
    }

    func stop() {
        didStop = true
    }

    func update(_ settings: ScrollDirectionSettings) {
        self.settings = settings
        updates.append(settings)
    }

    func report(_ status: ScrollDirectionTapStatus) {
        statusHandler(status)
    }
}
