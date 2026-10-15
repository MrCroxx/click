import XCTest
@testable import ClickCore

final class RawInputRouterTests: XCTestCase {
    let first = DeviceIdentity(vendor: 1, product: 2, location: 1)
    let second = DeviceIdentity(vendor: 1, product: 2, location: 2)
    func configuration() -> Configuration {
        var config = Configuration()
        config.macros = [Macro(steps: [MacroStep(kind: .shortcut)])]
        var profile = DeviceProfile(name: "Keyboard", device: first)
        profile.enabled = true
        var remap = KeyBinding(); remap.source = 57; remap.destination = 41
        var trigger = KeyBinding(); trigger.source = 58; trigger.kind = .macro; trigger.macroID = config.macros[0].id
        profile.bindings = [remap, trigger]; config.profiles = [profile]
        return config
    }
    func testPhysicalDeviceIdentityAndNoRecursiveRemapping() {
        var config = configuration()
        var binding = KeyBinding(); binding.source = 41; binding.destination = 40
        config.profiles[0].bindings.append(binding)
        var router = RawInputRouter(configuration: config)
        _ = router.input(device: 1, identity: first, key: .init(usage: 57), down: true)
        _ = router.input(device: 2, identity: second, key: .init(usage: 57), down: true)
        XCTAssertEqual(router.keys, [.init(usage: 41), .init(usage: 57)])
    }
    func testMacroConsumedAndTriggeredOnlyOnFirstDown() {
        let config = configuration()
        var router = RawInputRouter(configuration: config)
        XCTAssertEqual(router.input(device: 1, identity: first, key: .init(usage: 58), down: true), config.macros[0].id)
        XCTAssertNil(router.input(device: 1, identity: first, key: .init(usage: 58), down: true))
        XCTAssertTrue(router.keys.isEmpty)
        XCTAssertNil(router.input(device: 1, identity: first, key: .init(usage: 58), down: false))
        XCTAssertEqual(router.input(device: 1, identity: first, key: .init(usage: 58), down: true), config.macros[0].id)
    }
    func testOtherKeyboardCannotTriggerMacroAndF13IsNotReserved() throws {
        var config = configuration()
        config.profiles[0].bindings[0].destination = 104
        try config.validate()
        var router = RawInputRouter(configuration: config)
        XCTAssertNil(router.input(device: 2, identity: second, key: .init(usage: 58), down: true))
        XCTAssertNil(router.input(device: 1, identity: first, key: .init(usage: 104), down: true))
        XCTAssertEqual(router.keys, [.init(usage: 58), .init(usage: 104)])
    }
    func testNoEightMacroBindingLimit() throws {
        var config = configuration()
        config.profiles[0].bindings = (4..<24).map { usage in
            var binding = KeyBinding(); binding.source = usage; binding.kind = .macro; binding.macroID = config.macros[0].id; return binding
        }
        try config.validate()
        var router = RawInputRouter(configuration: config)
        for usage in 4..<24 { XCTAssertNotNil(router.input(device: 1, identity: first, key: .init(usage: UInt16(usage)), down: true)) }
        XCTAssertTrue(router.keys.isEmpty)
    }
    func testSharedDestinationRemainsHeldUntilEverySourceReleased() {
        var router = RawInputRouter(configuration: configuration())
        _ = router.input(device: 1, identity: first, key: .init(usage: 57), down: true)
        _ = router.input(device: 2, identity: second, key: .init(usage: 41), down: true)
        _ = router.input(device: 1, identity: first, key: .init(usage: 57), down: false)
        XCTAssertEqual(router.keys, [.init(usage: 41)])
        router.disconnect(2)
        XCTAssertTrue(router.keys.isEmpty)
    }
    func testNonKeyboardPagesPassThroughAndResetReleasesAllKeys() {
        var router = RawInputRouter(configuration: configuration())
        let media = RawInputRouter.Key(page: 12, usage: 58)
        XCTAssertNil(router.input(device: 1, identity: first, key: media, down: true))
        _ = router.input(device: 1, identity: first, key: .init(usage: 224), down: true)
        XCTAssertEqual(router.keys, [media, .init(usage: 224)])
        router.reset(); XCTAssertTrue(router.keys.isEmpty)
    }
    func testDisabledProfilePassesThrough() {
        var config = configuration(); config.profiles[0].enabled = false
        var router = RawInputRouter(configuration: config)
        XCTAssertNil(router.input(device: 1, identity: first, key: .init(usage: 58), down: true))
        XCTAssertEqual(router.keys, [.init(usage: 58)])
    }
}
