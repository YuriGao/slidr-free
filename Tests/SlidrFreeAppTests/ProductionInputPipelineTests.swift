import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class ProductionInputPipelineTests: XCTestCase {
    func testQuiesceWithEventTapStopAdvancesBridgeOnceAndEmitsPendingReleaseOnce() {
        let bridge = MiddleClickSessionBridge(generation: 7, now: { 1 })
        let monitor = PipelineMonitorSpy()
        let emitter = ReleaseEmitterSpy()
        var tap: PipelineEventTapSpy?
        let pipeline = makePipeline(
            bridge: bridge,
            monitor: monitor,
            emitter: emitter,
            eventTapFactory: { reducer in
                let value = PipelineEventTapSpy(reducer: reducer)
                tap = value
                return value
            }
        )
        pipeline.startEventTap { XCTAssertTrue($0) }
        pipeline.receiveMiddleClick(.frame(generation: 7, sequence: 1, timestamp: 1, receivedAt: 1, touches: touches()))
        XCTAssertEqual(tap?.reducer.reduce(.init(kind: .down, sourceButton: 0, eventNumber: 55, marker: 0)), .transform(.init(kind: .down, targetButton: 2, eventNumber: 55, clickState: 1)))

        pipeline.quiesce {}

        XCTAssertEqual(bridge.generation, 8)
        XCTAssertEqual(emitter.eventNumbers, [55])
        XCTAssertEqual(tap?.stopCount, 1)
    }

    func testQueuedTapIsDroppedWhenPipelineQuiescesBeforeMainDelivery() {
        let monitor = PipelineMonitorSpy()
        var queued: [() -> Void] = []
        var actions: [RecognizedGesture] = []
        let pipeline = makePipeline(monitor: monitor, deliverAction: { queued.append($0) }, actionHandler: { actions.append($0) })
        pipeline.receiveMiddleClick(.frame(generation: 7, sequence: 1, timestamp: 1, receivedAt: 1, touches: touches()))
        pipeline.receiveMiddleClick(.empty(generation: 7, sequence: 2, timestamp: 1.1, receivedAt: 1.1))
        XCTAssertEqual(queued.count, 1)

        pipeline.quiesce {}
        queued.removeFirst()()

        XCTAssertTrue(actions.isEmpty)
    }

    func testTouchCallbackArrivingAfterQuiesceCannotMutateOrQueueAction() {
        let monitor = PipelineMonitorSpy()
        var queued: [() -> Void] = []
        let pipeline = makePipeline(monitor: monitor, deliverAction: { queued.append($0) })
        XCTAssertTrue(pipeline.startTouchMonitor())
        pipeline.quiesce {}
        monitor.middleHandler?(.frame(generation: 7, sequence: 1, timestamp: 1, receivedAt: 1, touches: touches()))
        monitor.middleHandler?(.empty(generation: 7, sequence: 2, timestamp: 1.1, receivedAt: 1.1))
        XCTAssertTrue(queued.isEmpty)
        XCTAssertEqual(monitor.stopCount, 1)
    }

    private func makePipeline(
        bridge: MiddleClickSessionBridge = MiddleClickSessionBridge(generation: 7, now: { 1.1 }),
        monitor: PipelineMonitorSpy,
        emitter: ReleaseEmitterSpy = ReleaseEmitterSpy(),
        eventTapFactory: @escaping (MouseButtonEventReducer) -> any InputEventTapLifecycle = { PipelineEventTapSpy(reducer: $0) },
        deliverAction: @escaping (@escaping () -> Void) -> Void = { $0() },
        actionHandler: @escaping (RecognizedGesture) -> Void = { _ in }
    ) -> ProductionInputPipeline {
        ProductionInputPipeline(
            generation: 7,
            settings: enabledSettingsForProduction(),
            status: InputPipelineStatus(),
            bridge: bridge,
            releaseEmitter: emitter,
            actionHandler: actionHandler,
            eventTapStatus: { _ in },
            monitorFactory: { _, middle, edge in
                monitor.middleHandler = middle
                monitor.edgeHandler = edge
                return monitor
            },
            eventTapFactory: { reducer, _, _ in eventTapFactory(reducer) },
            deliverAction: deliverAction
        )
    }

    private func touches() -> [PhysicalTouch] {
        [
            PhysicalTouch(id: 1, x: 0.4, y: 0.4, pressure: 0, state: 1),
            PhysicalTouch(id: 2, x: 0.5, y: 0.4, pressure: 0, state: 1),
            PhysicalTouch(id: 3, x: 0.6, y: 0.4, pressure: 0, state: 1)
        ]
    }
}

private func enabledSettingsForProduction() -> AppSettings {
    var settings = AppSettings.default
    settings.middleClick.isEnabled = true
    return settings
}

private final class PipelineMonitorSpy: InputTouchMonitoring {
    var middleHandler: ((MiddleClickInputUpdate) -> Void)?
    var edgeHandler: ((NormalizedInputEvent) -> Void)?
    var stopCount = 0
    func start() -> Bool { true }
    func stop() { stopCount += 1 }
}

private final class PipelineEventTapSpy: InputEventTapLifecycle {
    let reducer: MouseButtonEventReducer
    var stopCount = 0
    init(reducer: MouseButtonEventReducer) { self.reducer = reducer }
    func start(completion: @escaping (Bool) -> Void) { completion(true) }
    func stop(completion: @escaping () -> Void) {
        stopCount += 1
        _ = reducer.quiesce()
        completion()
    }
}

private final class ReleaseEmitterSpy: MiddleClickReleaseEmitting {
    var eventNumbers: [Int64] = []
    func emitRelease(eventNumber: Int64) -> SystemActionResult {
        eventNumbers.append(eventNumber)
        return .success
    }
}
