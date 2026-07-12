import XCTest
@testable import SlidrFreeApp

final class SystemControlMiddleClickTests: XCTestCase {
    func testMiddleClickDelegatesToEmitterAndReturnsItsResult() {
        let emitter = MiddleClickEmitterSpy(result: .failed("test failure"))
        let control = SystemControl(middleClickEmitter: emitter)

        XCTAssertEqual(control.middleClick(), .failed("test failure"))
        XCTAssertEqual(emitter.emitCount, 1)
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
