import XCTest
@testable import ClickCore

final class FnMappingTests: XCTestCase {
    let identity = DeviceIdentity(vendor: 1, product: 2, location: 3)
    func configuration() -> Configuration {
        var config = Configuration()
        var profile = DeviceProfile(name: "Keyboard", device: identity); profile.enabled = true
        var binding = KeyBinding(); binding.source = 111; binding.destinationSelection = KeyCatalog.fnOutputID
        profile.bindings = [binding]; config.profiles = [profile]; return config
    }
    func testFnIsHeldUntilSourceReleased() throws {
        let config = configuration(); try config.validate()
        var router = RawInputRouter(configuration: config)
        _ = router.input(device: 1, identity: identity, key: .init(usage: 111), down: true)
        XCTAssertEqual(router.keys, [.init(page: 0xff, usage: 3)])
        _ = router.input(device: 1, identity: identity, key: .init(usage: 111), down: false)
        XCTAssertTrue(router.keys.isEmpty)
    }
    func testFunctionKeyChordPreservesOtherFnOwners() throws {
        var config = configuration()
        var binding = KeyBinding(); binding.source = 58; binding.destination = 58; binding.fn = true
        config.profiles[0].bindings.append(binding); try config.validate()
        var router = RawInputRouter(configuration: config)
        _ = router.input(device: 1, identity: identity, key: .init(usage: 111), down: true)
        _ = router.input(device: 1, identity: identity, key: .init(usage: 58), down: true)
        XCTAssertEqual(router.keys, [.init(page: 0xff, usage: 3), .init(usage: 58)])
        _ = router.input(device: 1, identity: identity, key: .init(usage: 58), down: false)
        XCTAssertEqual(router.keys, [.init(page: 0xff, usage: 3)])
        router.disconnect(1); XCTAssertTrue(router.keys.isEmpty)
    }
    func testRoundTripAndLegacyMissingFields() throws {
        let config = configuration()
        XCTAssertEqual(try Configuration.decode(config.encoded()), config)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(KeyBinding())) as? [String: Any])
        json.removeValue(forKey: "destinationPage"); json.removeValue(forKey: "fn")
        let binding = try JSONDecoder().decode(KeyBinding.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(binding.destinationPage); XCTAssertNil(binding.fn)
    }
    func testUnknownVendorDestinationIsRejected() {
        var config = configuration(); config.profiles[0].bindings[0].destination = 4
        XCTAssertThrowsError(try config.validate())
    }
    func testFnReportPrecedesKeyboardReport() throws {
        XCTAssertLessThan(try XCTUnwrap(HIDInterfacePolicy.pages.firstIndex(of: 0xff)), try XCTUnwrap(HIDInterfacePolicy.pages.firstIndex(of: 7)))
    }
}
