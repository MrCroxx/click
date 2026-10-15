import XCTest
@testable import ClickCore
final class MappingRestorationTests: XCTestCase {
    let a = HIDMapping(source: 57, destination: 41)
    let b = HIDMapping(source: 57, destination: 40)
    let thirdParty = HIDMapping(source: 58, destination: 59)
    func testRestoreReplacedMapping() {
        XCTAssertEqual(MappingRestoration.restore(current: [b], original: [a], applied: [b]), [a])
    }
    func testRemoveNewMapping() {
        XCTAssertEqual(MappingRestoration.restore(current: [a], original: [], applied: [a]), [])
    }
    func testPreserveUnrelatedChanges() {
        XCTAssertEqual(MappingRestoration.restore(current: [a, thirdParty], original: [], applied: [a]), [thirdParty])
    }
    func testDoNotOverwriteSameSourceChangedByOtherApp() {
        XCTAssertEqual(MappingRestoration.restore(current: [b], original: [], applied: [a]), [b])
    }
    func testDoNotResurrectRemovedMapping() {
        XCTAssertEqual(MappingRestoration.restore(current: [], original: [a], applied: [b]), [])
    }
    func testPreservePreexistingIdenticalMapping() {
        XCTAssertEqual(MappingRestoration.restore(current: [a], original: [a], applied: [a]), [a])
    }
}
