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
    lazy var coordinator = InputPipelineCoordinator(
        factory: factory,
        status: status,
        refreshPermission: { [weak self] in self?.permissionRefreshes += 1 },
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
        let value = FakePipeline(generation: generation, tapEnabled: settings.middleClick.tapEnabled, tapStartSucceeds: nextTapStartSucceeds, deferQuiesce: deferQuiesce, statusHandler: eventTapStatus)
        nextTapStartSucceeds = true
        instances.append(value)
        return value
    }
}

private final class FakePipeline: InputPipelineInstance {
    let generation: UInt64
    let componentGenerations: [UInt64]
    let tapEnabled: Bool
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

    init(generation: UInt64, tapEnabled: Bool, tapStartSucceeds: Bool, deferQuiesce: Bool, statusHandler: @escaping (MouseButtonEventTapStatus) -> Void) {
        self.generation = generation; self.componentGenerations = [generation, generation, generation, generation]
        self.tapEnabled = tapEnabled; self.tapStartSucceeds = tapStartSucceeds; self.deferQuiesce = deferQuiesce; self.statusHandler = statusHandler
    }

    func startTouchMonitor() -> Bool { touchRequested = true; return true }
    func startEventTap(completion: @escaping (Bool) -> Void) { eventTapRequested = true; completion(tapStartSucceeds) }
    func updateEdgeSettings(_ settings: AppSettings) { edgeUpdates += 1 }
    func quiesce(completion: @escaping () -> Void) { didQuiesce = true; if hasPending { releaseCount += 1; hasPending = false }; if deferQuiesce { pendingCompletion = completion } else { completion() } }
    func completeQuiesce() { pendingCompletion?(); pendingCompletion = nil }
    func report(_ status: MouseButtonEventTapStatus) { statusHandler(status) }
}
