import XCTest
@testable import ClickCore

final class PointingInputRouterTests: XCTestCase {
    func button(_ usage: UInt32, _ value: Int) -> PointingInputRouter.Value {
        .init(input: .init(page: 9, usage: usage), value: value)
    }
    func axis(_ usage: UInt32, _ value: Int, page: UInt32 = 1) -> PointingInputRouter.Value {
        .init(input: .init(page: page, usage: usage, isRelative: true, reportSize: 16), value: value)
    }
    func testMotionAndBothWheelsPreserveSignAndTotal() {
        var router = PointingInputRouter()
        let reports = router.input(device: 1, values: [button(1, 1), axis(0x30, -300), axis(0x31, 240), axis(0x38, -1), axis(0x238, 3, page: 12)])
        XCTAssertEqual(reports.count, 3)
        XCTAssertEqual(reports.map { Int($0.x) }.reduce(0, +), -300)
        XCTAssertEqual(reports.map { Int($0.y) }.reduce(0, +), 240)
        XCTAssertEqual(reports.map { Int($0.vertical) }.reduce(0, +), -1)
        XCTAssertEqual(reports.map { Int($0.horizontal) }.reduce(0, +), 3)
        XCTAssertTrue(reports.allSatisfy { $0.buttons == 1 })
        // A later report must not replay the previous motion.
        XCTAssertEqual(router.input(device: 1, values: [button(1, 0)]), [.init(buttons: 0, x: 0, y: 0, vertical: 0, horizontal: 0)])
    }
    func testSharedButtonsReleaseOnlyAfterEveryDeviceReleases() {
        var router = PointingInputRouter()
        _ = router.input(device: 1, values: [button(1, 1), button(32, 1)])
        _ = router.input(device: 2, values: [button(1, 1)])
        XCTAssertEqual(router.disconnect(1).buttons, 1)
        XCTAssertEqual(router.reset().buttons, 0)
        XCTAssertEqual(router.buttons, 0)
    }
    func testSystemArraySelectorsAreNotMouseMovement() {
        var router = PointingInputRouter()
        let reports = router.input(device: 1, values: [.init(input: .init(page: 1, usage: 0x30, isArray: true), value: 1)])
        XCTAssertEqual(reports, [.init(buttons: 0, x: 0, y: 0, vertical: 0, horizontal: 0)])
    }
}
