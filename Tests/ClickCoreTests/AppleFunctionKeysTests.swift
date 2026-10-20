import XCTest
@testable import ClickCore

final class AppleFunctionKeysTests: XCTestCase {
    let identity = DeviceIdentity(vendor: 0, product: 0, location: 111)
    let fn = RawInputRouter.Key(page: 0x00ff, usage: 3)
    func testTopRowAndFnRespectSystemPreference() {
        for standard in [false, true] {
            for pressedFn in [false, true] {
                for usage: UInt16 in 58...69 {
                    var router = RawInputRouter(configuration: Configuration())
                    if pressedFn { _ = router.input(device: 1, identity: identity, key: fn, down: true) }
                    let key = RawInputRouter.Key(usage: usage)
                    _ = router.input(device: 1, identity: identity, key: key, down: true, builtInApple: true, standardFunctionKeys: standard)
                    if pressedFn == standard {
                        XCTAssertTrue(router.keys.contains(AppleFunctionKeys.mediaKey(for: usage)))
                        XCTAssertFalse(router.keys.contains(key))
                    } else { XCTAssertTrue(router.keys.contains(key)) }
                    // Fn released before F must still release the original translated key.
                    _ = router.input(device: 1, identity: identity, key: fn, down: false)
                    _ = router.input(device: 1, identity: identity, key: key, down: false)
                    XCTAssertTrue(router.keys.isEmpty)
                }
            }
        }
    }
    func testExplicitBindingAndExternalKeyboardArePreserved() {
        var configuration = Configuration()
        var profile = DeviceProfile(name: "Built in", device: identity)
        profile.enabled = true
        var binding = KeyBinding(); binding.source = 58; binding.destination = 41
        profile.bindings = [binding]; configuration.profiles = [profile]
        var router = RawInputRouter(configuration: configuration)
        _ = router.input(device: 1, identity: identity, key: .init(usage: 58), down: true, builtInApple: true)
        XCTAssertEqual(router.keys, [.init(usage: 41)])
        router.reset()
        _ = router.input(device: 1, identity: identity, key: .init(usage: 59), down: true)
        XCTAssertEqual(router.keys, [.init(usage: 59)])
    }
    func testMediaReportsRemainUntouched() {
        var router = RawInputRouter(configuration: Configuration())
        let volume = RawInputRouter.Key(page: 12, usage: 0xe9)
        _ = router.input(device: 1, identity: identity, key: volume, down: true, builtInApple: true)
        XCTAssertEqual(router.keys, [volume])
    }
}
