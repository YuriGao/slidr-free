import XCTest
@testable import SlidrFreeApp

final class MediaKeyEventFactoryTests: XCTestCase {
    func testVolumeUpUsesSystemDefinedAuxControlMediaKeyEvents() throws {
        let events = try XCTUnwrap(MediaKeyEventFactory.events(for: .volumeUp))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.systemDefined, .systemDefined])
        XCTAssertEqual(events.map(\.subtype.rawValue), [8, 8])
        XCTAssertEqual(events.map(\.data1), [0x0000_0A00, 0x0000_0B00])
        XCTAssertEqual(events.map(\.data2), [-1, -1])
        XCTAssertEqual(events.map { $0.cgEvent != nil }, [true, true])
    }

    func testVolumeDownUsesSystemDefinedAuxControlMediaKeyEvents() throws {
        let events = try XCTUnwrap(MediaKeyEventFactory.events(for: .volumeDown))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.systemDefined, .systemDefined])
        XCTAssertEqual(events.map(\.subtype.rawValue), [8, 8])
        XCTAssertEqual(events.map(\.data1), [0x0001_0A00, 0x0001_0B00])
        XCTAssertEqual(events.map(\.data2), [-1, -1])
        XCTAssertEqual(events.map { $0.cgEvent != nil }, [true, true])
    }
}
