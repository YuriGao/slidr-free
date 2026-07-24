import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class GestureTestControllerTests: XCTestCase {
    func testEdgePreviewConsumesEveryEdgeGestureWithoutProducingActions() {
        let controller = GestureTestController()
        let router = GestureDispatchRouter(preview: controller)
        controller.start(.edge)
        let gestures: [RecognizedGesture] = [
            .brightness(direction: .increase, magnitude: 1),
            .volume(direction: .decrease, magnitude: 1),
            .browserTab(direction: .next)
        ]
        for gesture in gestures {
            XCTAssertTrue(router.actions(for: gesture, settings: .default).isEmpty)
        }
        XCTAssertTrue(controller.didRecognizeGesture)
        controller.stop()
    }

    func testMiddleClickPreviewConsumesTapButNotUnrelatedEdgeGesture() {
        let controller = GestureTestController()
        let router = GestureDispatchRouter(preview: controller)
        controller.start(.middleClick)
        XCTAssertTrue(router.actions(for: .middleClickTap, settings: .default).isEmpty)
        XCTAssertTrue(router.actions(for: .volume(direction: .increase, magnitude: 1), settings: .default).isEmpty)
        controller.stop()
        var enabledSettings = AppSettings.default
        enabledSettings.middleClick.isEnabled = true
        XCTAssertEqual(router.actions(for: .middleClickTap, settings: enabledSettings), [.middleClick])
    }

    func testCornerPreviewConsumesDoubleTapWithoutOpeningApplication() {
        let controller = GestureTestController()
        let router = GestureDispatchRouter(preview: controller)
        let binding = ApplicationBinding(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            applicationPath: "/Applications/Example.app"
        )
        var settings = AppSettings.default
        settings.cornerAppBindings.topLeft = binding

        controller.start(.corner)
        XCTAssertTrue(router.actions(for: .cornerDoubleTap(corner: .topLeft), settings: settings).isEmpty)
        XCTAssertTrue(controller.didRecognizeGesture)
        controller.stop()
        XCTAssertEqual(
            router.actions(for: .cornerDoubleTap(corner: .topLeft), settings: settings),
            [.toggleApplication(binding)]
        )
    }

    func testEdgeTimeoutDistinguishesNoFramesMissedEdgeAndThreshold() {
        let controller = GestureTestController()
        controller.start(.edge)
        controller.expire()
        XCTAssertEqual(controller.feedback, NSLocalizedString("gesture_test_timeout_no_frames", comment: ""))

        controller.start(.edge)
        controller.observe(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.5, y: 0.5)], timestamp: 1), settings: .default)
        controller.expire()
        XCTAssertEqual(controller.feedback, NSLocalizedString("gesture_test_timeout_no_edge", comment: ""))

        controller.start(.edge)
        controller.observe(.physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.5)], timestamp: 1), settings: .default)
        controller.expire()
        XCTAssertEqual(controller.feedback, NSLocalizedString("gesture_test_timeout_threshold", comment: ""))
    }

    func testCornerTimeoutDistinguishesMissedCornerFromIncompleteDoubleTap() {
        let controller = GestureTestController()
        controller.start(.corner)
        controller.observe(
            .physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.5, y: 0.5)], timestamp: 1),
            settings: .default
        )
        controller.expire()
        XCTAssertEqual(controller.feedback, NSLocalizedString("gesture_test_timeout_no_corner", comment: ""))

        controller.start(.corner)
        controller.observe(
            .physicalTouchFrame(touches: [PhysicalTouch(id: 1, x: 0.05, y: 0.95)], timestamp: 1),
            settings: .default
        )
        controller.expire()
        XCTAssertEqual(controller.feedback, NSLocalizedString("gesture_test_timeout_threshold", comment: ""))
    }

    func testCornerPreviewUsesDedicatedCornerTriggerPercent() {
        let controller = GestureTestController()
        let touch = PhysicalTouch(id: 1, x: 0.12, y: 0.88)

        var narrowCornerSettings = AppSettings.default
        narrowCornerSettings.gesture.edgeWidthPercent = 0.20
        narrowCornerSettings.gesture.cornerTriggerPercent = 0.05
        controller.start(.corner)
        controller.observe(.physicalTouchFrame(touches: [touch], timestamp: 1), settings: narrowCornerSettings)
        controller.expire()
        XCTAssertEqual(controller.feedback, NSLocalizedString("gesture_test_timeout_no_corner", comment: ""))

        var wideCornerSettings = AppSettings.default
        wideCornerSettings.gesture.edgeWidthPercent = 0.05
        wideCornerSettings.gesture.cornerTriggerPercent = 0.15
        controller.start(.corner)
        controller.observe(.physicalTouchFrame(touches: [touch], timestamp: 2), settings: wideCornerSettings)
        controller.expire()
        XCTAssertEqual(controller.feedback, NSLocalizedString("gesture_test_timeout_threshold", comment: ""))
    }
}
