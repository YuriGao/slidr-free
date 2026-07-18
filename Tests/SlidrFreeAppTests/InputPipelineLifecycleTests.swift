import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class InputPipelineLifecycleTests: XCTestCase {
    func testSingleGenerationAuthorityIsPassedToEveryFreshPipeline() {
        let harness = Harness()
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        XCTAssertEqual(harness.permissionRefreshes, 1)
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1])
        XCTAssertEqual(harness.factory.instances[0].componentGenerations, [1, 1, 1, 1])

        var changed = enabledSettings(); changed.middleClick.tapEnabled = false
        harness.coordinator.update(settings: changed, permission: .granted)
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1, 2])
        XCTAssertEqual(harness.factory.instances[1].componentGenerations, [2, 2, 2, 2])
    }

    func testEligibilityAndTapPreference() {
        let harness = Harness()
        var settings = AppSettings.default
        settings.middleClick = MiddleClickSettings(isEnabled: true, tapEnabled: false)
        harness.coordinator.update(settings: settings, permission: .granted)
        XCTAssertTrue(harness.factory.last!.touchRequested)
        XCTAssertTrue(harness.factory.last!.eventTapRequested)
        XCTAssertFalse(harness.factory.last!.tapEnabled)

        settings.isAppEnabled = false
        harness.coordinator.update(settings: settings, permission: .granted)
        XCTAssertTrue(harness.factory.instances.last!.didQuiesce)
        XCTAssertNil(harness.coordinator.activeGeneration)
    }

    func testMonitorStartsForEdgeOnlyButEventTapDoesNot() {
        let harness = Harness()
        var settings = AppSettings.default
        settings.middleClick.isEnabled = false
        harness.coordinator.update(settings: settings, permission: .granted)
        XCTAssertTrue(harness.factory.last!.touchRequested)
        XCTAssertFalse(harness.factory.last!.eventTapRequested)
    }

    func testMonitorStartsForCornerBindingOnlyButEventTapDoesNot() {
        let harness = Harness()
        var settings = AppSettings.default
        settings.edgeAssignments = EdgeAssignments(left: .none, right: .none, top: .none)
        settings.middleClick.isEnabled = false
        settings.cornerAppBindings.bottomRight = ApplicationBinding(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            applicationPath: "/Applications/Example.app"
        )

        harness.coordinator.update(settings: settings, permission: .granted)

        XCTAssertTrue(harness.factory.last!.touchRequested)
        XCTAssertFalse(harness.factory.last!.eventTapRequested)
    }

    func testPermissionLossQuiescesAndFactoryFailureRefreshesPermission() {
        let harness = Harness()
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        harness.coordinator.update(settings: enabledSettings(), permission: .denied)
        XCTAssertTrue(harness.factory.instances[0].didQuiesce)

        harness.factory.nextTapStartSucceeds = false
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        XCTAssertEqual(harness.permissionRefreshes, 3)
        XCTAssertEqual(harness.status.eventTap, .degraded)
    }

    func testMiddleClickChangeQuiescesPendingButUnrelatedSettingsOnlyUpdatesEdgeRecognizer() {
        let harness = Harness()
        var settings = enabledSettings()
        harness.coordinator.update(settings: settings, permission: .granted)
        let first = harness.factory.last!
        first.hasPending = true

        settings.gesture.edgeWidthPercent = 0.16
        harness.coordinator.update(settings: settings, permission: .granted)
        XCTAssertFalse(first.didQuiesce)
        XCTAssertEqual(first.edgeUpdates, 1)
        XCTAssertEqual(harness.factory.instances.count, 1)

        settings.middleClick.tapEnabled = false
        harness.coordinator.update(settings: settings, permission: .granted)
        XCTAssertTrue(first.didQuiesce)
        XCTAssertEqual(first.releaseCount, 1)
        XCTAssertEqual(harness.factory.instances.count, 2)
    }

    func testFingerCountChangeQuiescesPendingAndBuildsFreshPipeline() {
        let harness = Harness()
        var settings = enabledSettings()
        harness.coordinator.update(settings: settings, permission: .granted)
        let first = harness.factory.last!
        first.hasPending = true

        settings.middleClick.fingerCount = 3
        harness.coordinator.update(settings: settings, permission: .granted)

        XCTAssertTrue(first.didQuiesce)
        XCTAssertEqual(first.releaseCount, 1)
        XCTAssertEqual(harness.factory.instances.map(\.fingerCount), [4, 3])
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1, 2])
    }

    func testSleepWakeSchedulesFreshGenerationAfterTwoSeconds() {
        let harness = Harness()
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        harness.coordinator.willSleep()
        XCTAssertTrue(harness.factory.instances[0].didQuiesce)
        harness.coordinator.didWake()
        XCTAssertEqual(harness.scheduledDelays, [2.0])
        XCTAssertEqual(harness.factory.instances.count, 1)
        harness.runScheduled()
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1, 2])
    }

    func testWakeIsIgnoredWhileAwakeAndCoalescedWhilePending() {
        let harness = Harness()
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)

        harness.coordinator.didWake()
        XCTAssertTrue(harness.scheduledDelays.isEmpty)

        harness.coordinator.willSleep()
        harness.coordinator.didWake()
        harness.coordinator.didWake()
        XCTAssertEqual(harness.scheduledDelays, [2.0])
        harness.runScheduled()
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1, 2])
    }

    func testStaleWakeTimerCannotRestartAfterAnotherWillSleep() {
        let harness = Harness()
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        harness.coordinator.willSleep()
        harness.coordinator.didWake()
        harness.coordinator.willSleep()
        harness.runScheduled()
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1])
        XCTAssertNil(harness.coordinator.activeGeneration)
    }

    func testLatestMiddleClickSettingsWinWhilePreviousPipelineIsQuiescing() {
        let harness = Harness()
        harness.factory.deferQuiesce = true
        var settings = enabledSettings()
        harness.coordinator.update(settings: settings, permission: .granted)
        let first = harness.factory.last!
        settings.middleClick.tapEnabled = false
        harness.coordinator.update(settings: settings, permission: .granted)
        settings.middleClick.tapEnabled = true
        harness.coordinator.update(settings: settings, permission: .granted)
        first.completeQuiesce()
        XCTAssertEqual(harness.factory.instances.map(\.tapEnabled), [true, true])

        settings.middleClick.tapEnabled = false
        harness.coordinator.update(settings: settings, permission: .granted)
        harness.factory.last!.completeQuiesce()
        XCTAssertEqual(harness.factory.instances.last?.tapEnabled, false)
    }

    func testSettingsChangedDuringFreshPermissionQueryAreNotLost() {
        let harness = Harness()
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        var changed = enabledSettings(); changed.middleClick.tapEnabled = false
        harness.onRefresh = {
            var latest = changed; latest.middleClick.tapEnabled = true
            harness.coordinator.update(settings: latest, permission: .granted)
        }
        harness.coordinator.update(settings: changed, permission: .granted)
        XCTAssertEqual(harness.factory.instances.last?.tapEnabled, true)
    }

    func testTerminationWaitsForStopCompletion() {
        let harness = Harness()
        harness.factory.deferQuiesce = true
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        var completed = false
        harness.coordinator.terminate { completed = true }
        XCTAssertFalse(completed)
        harness.factory.last!.completeQuiesce()
        XCTAssertTrue(completed)
    }

    func testRecoveryRequiresFreshPipelineAndDegradedDoesNotReuseBridge() {
        let harness = Harness()
        harness.coordinator.update(settings: enabledSettings(), permission: .granted)
        harness.factory.last!.report(.recoveryRequiresPipelineRestart)
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1, 2])
        harness.factory.last!.report(.degraded)
        XCTAssertEqual(harness.status.eventTap, .degraded)
        XCTAssertEqual(harness.permissionRefreshes, 4)
    }

    func testRecheckRestartsUnavailableTouchMonitor() {
        let harness = Harness()
        let settings = enabledSettings()
        harness.coordinator.update(settings: settings, permission: .granted)
        let failedPipeline = harness.factory.last!
        harness.status.update(touchMonitor: .unavailable)

        harness.coordinator.update(settings: settings, permission: .granted)

        XCTAssertTrue(failedPipeline.didQuiesce)
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1, 2])
        XCTAssertEqual(harness.status.touchMonitor, .running)
    }

    func testRecheckRestartsDegradedEventTap() {
        let harness = Harness()
        let settings = enabledSettings()
        harness.coordinator.update(settings: settings, permission: .granted)
        let failedPipeline = harness.factory.last!
        failedPipeline.report(.degraded)

        harness.coordinator.update(settings: settings, permission: .granted)

        XCTAssertTrue(failedPipeline.didQuiesce)
        XCTAssertEqual(harness.factory.instances.map(\.generation), [1, 2])
        XCTAssertEqual(harness.status.eventTap, .stopped)
    }

    func testTerminationWaiterSucceedsAndTimesOutWithoutUnboundedBlocking() {
        let success = PipelineTerminationWaiter(timeout: 2) { semaphore, _ in
            semaphore.wait(timeout: .now()) == .success
        }
        XCTAssertTrue(success.waitForStop { completion in completion() })

        var observedTimeout: TimeInterval?
        let timeout = PipelineTerminationWaiter(timeout: 2) { _, seconds in
            observedTimeout = seconds
            return false
        }
        XCTAssertFalse(timeout.waitForStop { _ in })
        XCTAssertEqual(observedTimeout, 2)

        let status = InputPipelineStatus()
        status.update(failure: String(repeating: "x", count: 300))
        XCTAssertEqual(status.lastFailureReason?.count, 160)
    }

    func testQueuedOldGenerationFrameCannotOverwriteFreshStatus() {
        var queued: [() -> Void] = []
        let status = InputPipelineStatus(deliverOnMain: { queued.append($0) })
        status.update(generation: 1)
        queued.removeFirst()()
        status.update(frameReceivedAt: 10, frameGeneration: 1)
        status.update(generation: 2)
        let oldFrame = queued.removeFirst()
        queued.removeFirst()()
        oldFrame()
        XCTAssertEqual(status.generation, 2)
        XCTAssertNil(status.lastFrameReceivedAt)
    }

    func testQueuedOldMonitorStatusCannotOverwriteFreshGeneration() {
        var queued: [() -> Void] = []
        let status = InputPipelineStatus(deliverOnMain: { queued.append($0) })
        status.update(generation: 1)
        queued.removeFirst()()
        status.update(frameworkAvailable: true, deviceAvailable: true, touchMonitor: .running, sourceGeneration: 1)
        queued.removeFirst()()
        status.update(
            frameworkAvailable: false,
            deviceAvailable: false,
            touchMonitor: .unavailable,
            failure: "old failure",
            sourceGeneration: 1
        )
        status.update(generation: 2)
        let oldMonitorStatus = queued.removeFirst()
        queued.removeFirst()()
        oldMonitorStatus()

        XCTAssertEqual(status.generation, 2)
        XCTAssertNil(status.frameworkAvailable)
        XCTAssertNil(status.deviceAvailable)
        XCTAssertEqual(status.touchMonitor, .stopped)
        XCTAssertNil(status.lastFailureReason)

        status.update(frameworkAvailable: true, deviceAvailable: true, touchMonitor: .running, sourceGeneration: 2)
        queued.removeFirst()()
        XCTAssertEqual(status.frameworkAvailable, true)
        XCTAssertEqual(status.deviceAvailable, true)
        XCTAssertEqual(status.touchMonitor, .running)

        status.update(touchMonitor: .stopped)
        queued.removeFirst()()
        XCTAssertEqual(status.touchMonitor, .stopped)
    }

    func testPreviewCanProbeWhilePermissionDeniedAndNeverStartsPhysicalClickTap() {
        let harness = Harness()
        var settings = enabledSettings()
        settings.isAppEnabled = false
        harness.freshPermission = .denied

        harness.coordinator.update(settings: settings, permission: .denied, previewMode: true)

        XCTAssertTrue(harness.factory.last?.touchRequested == true)
        XCTAssertFalse(harness.factory.last?.eventTapRequested == true)
        XCTAssertNotNil(harness.coordinator.activeGeneration)

        harness.coordinator.update(settings: settings, permission: .denied, previewMode: false)
        XCTAssertNil(harness.coordinator.activeGeneration)
        XCTAssertTrue(harness.factory.instances[0].didQuiesce)
    }
}

private func enabledSettings() -> AppSettings {
    var value = AppSettings.default
    value.middleClick.isEnabled = true
    return value
}

private final class Harness {
    let factory = FakePipelineFactory()
    let status = InputPipelineStatus()
    var permissionRefreshes = 0
    var scheduledDelays: [TimeInterval] = []
    var scheduled: [() -> Void] = []
    var freshPermission: PermissionState = .granted
    var onRefresh: (() -> Void)?
    lazy var coordinator = InputPipelineCoordinator(
        factory: factory,
        status: status,
        refreshPermission: { [weak self] in
            guard let self else { return .denied }
            self.permissionRefreshes += 1
            let action = self.onRefresh
            self.onRefresh = nil
            action?()
            return self.freshPermission
        },
        schedule: { [weak self] delay, work in self?.scheduledDelays.append(delay); self?.scheduled.append(work) }
    )

    func runScheduled() { let work = scheduled; scheduled.removeAll(); work.forEach { $0() } }
}

private final class FakePipelineFactory: InputPipelineFactory {
    var instances: [FakePipeline] = []
    var nextTapStartSucceeds = true
    var deferQuiesce = false
    var last: FakePipeline? { instances.last }

    func make(generation: UInt64, settings: AppSettings, status: InputPipelineStatus, eventTapStatus: @escaping (MouseButtonEventTapStatus) -> Void) -> any InputPipelineInstance {
        let value = FakePipeline(
            generation: generation,
            tapEnabled: settings.middleClick.tapEnabled,
            fingerCount: settings.middleClick.fingerCount,
            tapStartSucceeds: nextTapStartSucceeds,
            deferQuiesce: deferQuiesce,
            statusHandler: eventTapStatus
        )
        nextTapStartSucceeds = true
        instances.append(value)
        return value
    }
}

private final class FakePipeline: InputPipelineInstance {
    let generation: UInt64
    let componentGenerations: [UInt64]
    let tapEnabled: Bool
    let fingerCount: Int
    let tapStartSucceeds: Bool
    let deferQuiesce: Bool
    let statusHandler: (MouseButtonEventTapStatus) -> Void
    var touchRequested = false
    var eventTapRequested = false
    var didQuiesce = false
    var hasPending = false
    var releaseCount = 0
    var edgeUpdates = 0
    var pendingCompletion: (() -> Void)?

    init(generation: UInt64, tapEnabled: Bool, fingerCount: Int, tapStartSucceeds: Bool, deferQuiesce: Bool, statusHandler: @escaping (MouseButtonEventTapStatus) -> Void) {
        self.generation = generation; self.componentGenerations = [generation, generation, generation, generation]
        self.tapEnabled = tapEnabled; self.fingerCount = fingerCount; self.tapStartSucceeds = tapStartSucceeds; self.deferQuiesce = deferQuiesce; self.statusHandler = statusHandler
    }

    func startTouchMonitor() -> Bool { touchRequested = true; return true }
    func startEventTap(completion: @escaping (Bool) -> Void) { eventTapRequested = true; completion(tapStartSucceeds) }
    func updateEdgeSettings(_ settings: AppSettings) { edgeUpdates += 1 }
    func quiesce(completion: @escaping () -> Void) { didQuiesce = true; if hasPending { releaseCount += 1; hasPending = false }; if deferQuiesce { pendingCompletion = completion } else { completion() } }
    func completeQuiesce() { pendingCompletion?(); pendingCompletion = nil }
    func report(_ status: MouseButtonEventTapStatus) { statusHandler(status) }
}
