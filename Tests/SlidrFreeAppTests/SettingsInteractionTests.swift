import XCTest
@testable import SlidrFreeApp

final class SettingsInteractionTests: XCTestCase {
    func testDeferredSliderCommitsOnlyOnceWhenEditingEnds() {
        var value = DeferredSliderValue(persisted: 0.1)

        value.beginEditing()
        value.updateDraft(0.2)
        value.updateDraft(0.3)

        XCTAssertEqual(value.finishEditing(), 0.3)
        XCTAssertNil(value.finishEditing())
    }

    func testDeferredSliderTracksExternalChangesOnlyWhileIdle() {
        var value = DeferredSliderValue(persisted: 0.1)
        value.synchronizePersistedValue(0.2)
        XCTAssertEqual(value.draft, 0.2)

        value.beginEditing()
        value.updateDraft(0.3)
        value.synchronizePersistedValue(0.4)
        XCTAssertEqual(value.draft, 0.3)
    }

    func testRecentTouchDescriptionUsesBoundedNonnegativeAge() {
        XCTAssertEqual(RecentTouchDescription.age(lastFrameReceivedAt: nil, now: 10), nil)
        XCTAssertEqual(RecentTouchDescription.age(lastFrameReceivedAt: 7.2, now: 10), 2)
        XCTAssertEqual(RecentTouchDescription.age(lastFrameReceivedAt: 11, now: 10), 0)
    }
}
