import XCTest
@testable import ClickCore

final class HIDInterfacePolicyTests: XCTestCase {
    let keyboard = DeviceIdentity(vendor: 1, product: 2, location: 3)
    func testClearingKeyboardErrorDoesNotPauseCapture() {
        for usage: UInt32 in 1...3 {
            XCTAssertFalse(HIDInterfacePolicy.reportsKeyboardError(page: 7, usage: usage, value: 0))
            XCTAssertTrue(HIDInterfacePolicy.reportsKeyboardError(page: 7, usage: usage, value: 1))
        }
        XCTAssertFalse(HIDInterfacePolicy.reportsKeyboardError(page: 0xff, usage: 3, value: 1))
        XCTAssertFalse(HIDInterfacePolicy.reportsKeyboardError(page: 7, usage: 111, value: 1))
    }
    func testBuiltInAppleKeyboardWithoutUSBVendorID() {
        XCTAssertFalse(HIDInterfacePolicy.isKeyValue(vendor: 0, isBuiltInApple: true, page: 0xff00, usage: 6, reportSize: 512))
        XCTAssertTrue(HIDInterfacePolicy.isKeyValue(vendor: 0, page: 0xff00, usage: 6, reportSize: 512))
        XCTAssertTrue(HIDInterfacePolicy.isKeyValue(vendor: 0, isBuiltInApple: true, page: 0xff, usage: 3, reportSize: 1))
        XCTAssertTrue(HIDInterfacePolicy.isKeyValue(vendor: 0, isBuiltInApple: true, page: 0xff00, usage: 7, reportSize: 512))
    }
    func testAppleOpaqueReportAndArrayContainersAreNotKeys() {
        XCTAssertFalse(HIDInterfacePolicy.isKeyValue(vendor: 0x05ac, page: 0xff00, usage: 6, reportSize: 512))
        XCTAssertFalse(HIDInterfacePolicy.isKeyValue(vendor: 1, page: 7, usage: UInt32.max, reportSize: 48))
        XCTAssertFalse(HIDInterfacePolicy.isKeyValue(vendor: 1, page: 7, usage: 0, reportSize: 1))
        XCTAssertTrue(HIDInterfacePolicy.isKeyValue(vendor: 0x05ac, page: 0xff, usage: 3, reportSize: 1))
        // Unknown vendor data and mouse axes must still reach compatibility
        // validation; they cannot be silently discarded to allow seizure.
        XCTAssertTrue(HIDInterfacePolicy.isKeyValue(vendor: 1, page: 0xff00, usage: 6, reportSize: 512))
        XCTAssertTrue(HIDInterfacePolicy.isKeyValue(vendor: 0x05ac, page: 1, usage: 0x30, reportSize: 16))
    }
    func testCompoundSiblingDoesNotBlockKeyboardInEitherOrder() throws {
        let pure = HIDInterfacePolicy.Interface(id: 1, identity: keyboard, supported: true)
        let compound = HIDInterfacePolicy.Interface(id: 2, identity: keyboard, supported: false)
        XCTAssertEqual(try HIDInterfacePolicy.select([pure, compound]), [1])
        XCTAssertEqual(try HIDInterfacePolicy.select([compound, pure]), [1])
    }
    func testUnsupportedDeviceIsNotHiddenByAnUnrelatedKeyboard() {
        let other = DeviceIdentity(vendor: 1, product: 2, location: 4)
        XCTAssertThrowsError(try HIDInterfacePolicy.select([
            .init(id: 1, identity: keyboard, supported: false),
            .init(id: 2, identity: other, supported: true)
        ]))
    }
    func testOnlyUnsupportedInterfaceFails() {
        XCTAssertThrowsError(try HIDInterfacePolicy.select([.init(id: 1, identity: keyboard, supported: false)]))
    }
    func testPointerInputsAreNotPartiallyCaptured() {
        XCTAssertTrue(HIDInterfacePolicy.supports([.init(page: 7, usage: 4), .init(page: 7, usage: UInt32.max)]))
        XCTAssertFalse(HIDInterfacePolicy.supports([.init(page: 7, usage: 4), .init(page: 9, usage: 1)]))
        XCTAssertFalse(HIDInterfacePolicy.supports([.init(page: 7, usage: 4), .init(page: 1, usage: 0x30)]))
        XCTAssertFalse(HIDInterfacePolicy.supports([]))
    }
}
