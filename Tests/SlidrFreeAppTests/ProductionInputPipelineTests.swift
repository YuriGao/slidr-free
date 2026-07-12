import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class ProductionInputPipelineTests: XCTestCase {
    func testConfiguredFourFingerCountIsSharedByTapAndPhysicalClick() {
        let monitor = PipelineMonitorSpy()
        var actions: [RecognizedGesture] = []
        var tap: PipelineEventTapSpy?
        let pipeline = makePipeline(
            settings: enabledSettingsForProduction(fingerCount: 4),
            monitor: monitor,
            eventTapFactory: { reducer in
                let value = PipelineEventTapSpy(reducer: reducer)
                tap = value
                return value
            },
            actionHandler: { actions.append($0) }
        )
        pipeline.startEventTap { XCTAssertTrue($0) }

        pipeline.receiveMiddleClick(.frame(generation: 7, sequence: 1, timestamp: 1.00, receivedAt: 1.00, touches: touches(count: 3)))
        XCTAssertEqual(
            tap?.reducer.reduce(.init(kind: .down, sourceButton: 0, eventNumber: 66, marker: 0)),
            .passUnchanged
        )
        pipeline.receiveMiddleClick(.empty(generation: 7, sequence: 2, timestamp: 1.10, receivedAt: 1.10))
        XCTAssertTrue(actions.isEmpty)

        pipeline.receiveMiddleClick(.frame(generation: 7, sequence: 3, timestamp: 1.20, receivedAt: 1.20, touches: touches(count: 4)))
        pipeline.receiveMiddleClick(.empty(generation: 7, sequence: 4, timestamp: 1.30, receivedAt: 1.30))
        XCTAssertEqual(actions, [.middleClickTap])

        pipeline.receiveMiddleClick(.frame(generation: 7, sequence: 5, timestamp: 1.40, receivedAt: 1.05, touches: touches(count: 4)))
        XCTAssertEqual(
            tap?.reducer.reduce(.init(kind: .down, sourceButton: 0, eventNumber: 77, marker: 0)),
            .transform(.init(kind: .down, targetButton: 2, eventNumber: 77, clickState: 1))
        )
        XCTAssertEqual(
            tap?.reducer.reduce(.init(kind: .dragged, sourceButton: 0, eventNumber: 77, marker: 0)),
            .transform(.init(kind: .dragged, targetButton: 2, eventNumber: 77, clickState: 1))
        )
        XCTAssertEqual(
            tap?.reducer.reduce(.init(kind: .up, sourceButton: 0, eventNumber: 77, marker: 0)),
            .transform(.init(kind: .up, targetButton: 2, eventNumber: 77, clickState: 1))
        )
        XCTAssertEqual(
            tap?.reducer.reduce(.init(kind: .up, sourceButton: 0, eventNumber: 77, marker: 0)),
            .passUnchanged
        )
    }

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

    func testOutOfOrderFrameAfterNewerEmptyCannotOpenTapSession() {
        let monitor = PipelineMonitorSpy()
        var actions: [RecognizedGesture] = []
        let pipeline = makePipeline(monitor: monitor, actionHandler: { actions.append($0) })

        pipeline.receiveMiddleClick(.empty(generation: 7, sequence: 2, timestamp: 1.1, receivedAt: 1.1))
        pipeline.receiveMiddleClick(.frame(generation: 7, sequence: 1, timestamp: 1.2, receivedAt: 1.2, touches: touches()))
        pipeline.receiveMiddleClick(.empty(generation: 7, sequence: 3, timestamp: 1.3, receivedAt: 1.3))

        XCTAssertTrue(actions.isEmpty)
    }

    func testOlderGenerationWithHigherSequenceCannotInvalidateCurrentTapSession() {
        let monitor = PipelineMonitorSpy()
        var actions: [RecognizedGesture] = []
        let pipeline = makePipeline(monitor: monitor, actionHandler: { actions.append($0) })

        pipeline.receiveMiddleClick(.frame(generation: 7, sequence: 1, timestamp: 1.0, receivedAt: 1.0, touches: touches()))
        pipeline.receiveMiddleClick(.frame(
            generation: 6,
            sequence: 999,
            timestamp: 1.05,
            receivedAt: 1.05,
            touches: touches() + [PhysicalTouch(id: 4, x: 0.7, y: 0.4, pressure: 0, state: 1)]
        ))
        pipeline.receiveMiddleClick(.empty(generation: 7, sequence: 2, timestamp: 1.1, receivedAt: 1.1))

        XCTAssertEqual(actions, [.middleClickTap])
    }

    private func makePipeline(
        bridge: MiddleClickSessionBridge = MiddleClickSessionBridge(generation: 7, now: { 1.1 }),
        settings: AppSettings = enabledSettingsForProduction(fingerCount: 3),
        monitor: PipelineMonitorSpy,
        emitter: ReleaseEmitterSpy = ReleaseEmitterSpy(),
        eventTapFactory: @escaping (MouseButtonEventReducer) -> any InputEventTapLifecycle = { PipelineEventTapSpy(reducer: $0) },
        deliverAction: @escaping (@escaping () -> Void) -> Void = { $0() },
        actionHandler: @escaping (RecognizedGesture) -> Void = { _ in }
    ) -> ProductionInputPipeline {
        ProductionInputPipeline(
            generation: 7,
            settings: settings,
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

    private func touches(count: Int = 3) -> [PhysicalTouch] {
        (1...count).map { index in
            PhysicalTouch(id: index, x: 0.3 + Double(index) * 0.1, y: 0.4, pressure: 0, state: 1)
        }
    }
}

private func enabledSettingsForProduction(fingerCount: Int) -> AppSettings {
    var settings = AppSettings.default
    settings.middleClick.isEnabled = true
    settings.middleClick.fingerCount = fingerCount
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
