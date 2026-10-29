import XCTest
@testable import ClickCore

final class DeviceProfileResolverTests: XCTestCase {
    let original = DeviceIdentity(vendor: 10, product: 20, location: 100)
    let moved = DeviceIdentity(vendor: 10, product: 20, location: 200)

    func profile(_ identity: DeviceIdentity) -> DeviceProfile {
        var profile = DeviceProfile(name: "Keyboard", device: identity)
        profile.enabled = true
        var fn = KeyBinding(); fn.source = 111; fn.destination = 3; fn.destinationPage = 0xff
        profile.bindings = [fn]
        return profile
    }

    func testMovedAnonymousKeyboardKeepsFnMappingWithoutChangingConfiguration() throws {
        var config = Configuration(); config.profiles = [profile(original)]
        let saved = try config.encoded()
        // Multiple HID interfaces at one location are one physical keyboard.
        let resolver = DeviceProfileResolver(profiles: config.profiles, connected: [moved, moved])
        let resolved = try XCTUnwrap(resolver.profile(for: moved))
        XCTAssertEqual(resolved.id, config.profiles[0].id)
        var router = RawInputRouter(configuration: config)
        _ = router.input(device: 1, identity: resolved.device, key: .init(usage: 111), down: true)
        XCTAssertEqual(router.keys, [.init(page: 0xff, usage: 3)])
        _ = router.input(device: 1, identity: resolved.device, key: .init(usage: 111), down: false)
        XCTAssertTrue(router.keys.isEmpty)
        XCTAssertEqual(try config.encoded(), saved)
        // Strict identities remain suitable for recovery journals and grouping.
        XCTAssertFalse(original.matches(moved))
    }

    func testExactPortWinsAndOtherSameModelDeviceDoesNotInheritMapping() {
        let saved = profile(original)
        let resolver = DeviceProfileResolver(profiles: [saved], connected: [original, moved])
        XCTAssertEqual(resolver.profile(for: original)?.id, saved.id)
        XCTAssertNil(resolver.profile(for: moved))
    }

    func testHotPlugAmbiguityCancelsFallbackAndRemovalAllowsItAgain() {
        let saved = profile(original)
        let second = DeviceIdentity(vendor: 10, product: 20, location: 300)
        for inventory in [[moved], [moved, second], [moved]] {
            let resolver = DeviceProfileResolver(profiles: [saved], connected: inventory)
            XCTAssertEqual(resolver.profile(for: moved)?.id, inventory.count == 1 ? saved.id : nil)
            XCTAssertNil(resolver.profile(for: second))
        }
    }

    func testMultipleSavedProfilesIncludingDisabledPreventFallback() {
        let first = profile(original)
        var second = profile(DeviceIdentity(vendor: 10, product: 20, location: 300))
        second.enabled = false
        let resolver = DeviceProfileResolver(profiles: [first, second], connected: [moved])
        XCTAssertNil(resolver.profile(for: moved))
        let exact = DeviceProfileResolver(profiles: [first, second], connected: [second.device])
        XCTAssertEqual(exact.profile(for: second.device)?.id, second.id)
        XCTAssertFalse(exact.profile(for: second.device)!.enabled)
    }

    func testSingleDisabledProfileRemainsDisabledAfterMoving() {
        var saved = profile(original); saved.enabled = false
        let resolver = DeviceProfileResolver(profiles: [saved], connected: [moved])
        XCTAssertEqual(resolver.profile(for: moved)?.id, saved.id)
        XCTAssertEqual(resolver.profile(for: moved)?.enabled, false)
    }

    func testSerialIdentityRemainsAuthoritative() {
        let saved = profile(DeviceIdentity(vendor: 10, product: 20, serial: "test-a", location: 100))
        let same = DeviceIdentity(vendor: 10, product: 20, serial: "test-a", location: 200)
        let different = DeviceIdentity(vendor: 10, product: 20, serial: "test-b", location: 200)
        XCTAssertEqual(DeviceProfileResolver(profiles: [saved], connected: [same]).profile(for: same)?.id, saved.id)
        for device in [different, moved] {
            XCTAssertNil(DeviceProfileResolver(profiles: [saved], connected: [device]).profile(for: device))
        }
        XCTAssertNil(DeviceProfileResolver(profiles: [profile(original)], connected: [same]).profile(for: same))
    }

    func testUnrelatedReceiverDoesNotPreventFallbackOrReceiveKeyboardMapping() {
        let receiver = DeviceIdentity(vendor: 30, product: 40, location: 100)
        let saved = profile(original)
        let resolver = DeviceProfileResolver(profiles: [saved], connected: [moved, receiver])
        XCTAssertEqual(resolver.profile(for: moved)?.id, saved.id)
        XCTAssertNil(resolver.profile(for: receiver))
        XCTAssertNil(resolver.profile(for: original))
    }

    func testUnknownVendorOrProductCannotFallback() {
        for identity in [DeviceIdentity(vendor: 0, product: 0, location: 1),
                         DeviceIdentity(vendor: 10, product: 0, location: 1),
                         DeviceIdentity(vendor: 0, product: 20, location: 1)] {
            var relocated = identity; relocated.location = 2
            let resolver = DeviceProfileResolver(profiles: [profile(identity)], connected: [relocated])
            XCTAssertNil(resolver.profile(for: relocated))
        }
    }
}
