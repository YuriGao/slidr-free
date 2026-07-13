import XCTest
@testable import SlidrFreeApp

final class MiddleClickHapticFeedbackTests: XCTestCase {
    func testPerformSuccessAlwaysEnqueuesBeforeReadingEnablement() {
        var enabledReadCount = 0
        var queued: [() -> Void] = []
        var performCount = 0
        let feedback = AppKitMiddleClickHapticFeedback(
            isEnabled: {
                enabledReadCount += 1
                return true
            },
            deliverOnMain: { queued.append($0) },
            perform: { performCount += 1 }
        )

        feedback.performSuccess()

        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(enabledReadCount, 0)
        XCTAssertEqual(performCount, 0)

        queued.removeFirst()()
        XCTAssertEqual(enabledReadCount, 1)
        XCTAssertEqual(performCount, 1)
    }

    func testQueuedRequestReadsLatestEnablementAtDeliveryTime() {
        var enabled = true
        var queued: [() -> Void] = []
        var performCount = 0
        let feedback = AppKitMiddleClickHapticFeedback(
            isEnabled: { enabled },
            deliverOnMain: { queued.append($0) },
            perform: { performCount += 1 }
        )

        feedback.performSuccess()
        enabled = false
        queued.removeFirst()()
        XCTAssertEqual(performCount, 0)

        feedback.performSuccess()
        enabled = true
        queued.removeFirst()()
        XCTAssertEqual(performCount, 1)
    }

    func testEnabledDeliveryPerformsExactlyOncePerRequest() {
        var queued: [() -> Void] = []
        var performCount = 0
        let feedback = AppKitMiddleClickHapticFeedback(
            isEnabled: { true },
            deliverOnMain: { queued.append($0) },
            perform: { performCount += 1 }
        )

        feedback.performSuccess()
        feedback.performSuccess()
        XCTAssertEqual(queued.count, 2)

        queued.forEach { $0() }
        XCTAssertEqual(performCount, 2)
    }

    func testDisabledDeliveryDoesNotInvokePerformer() {
        var queued: [() -> Void] = []
        var performCount = 0
        let feedback = AppKitMiddleClickHapticFeedback(
            isEnabled: { false },
            deliverOnMain: { queued.append($0) },
            perform: { performCount += 1 }
        )

        feedback.performSuccess()
        queued.removeFirst()()

        XCTAssertEqual(performCount, 0)
    }
}
