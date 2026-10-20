import XCTest
@testable import Click
import ClickCore

final class SleepRecoveryTests: XCTestCase {
    func testResumeOnlyOnceAndOnlyIfPreviouslyActive() {
        var recovery = SleepRecovery()
        recovery.sleep(active: false)
        XCTAssertFalse(recovery.wake())
        recovery.sleep(active: true)
        recovery.sleep(active: false)
        XCTAssertTrue(recovery.wake())
        XCTAssertFalse(recovery.wake())
        recovery.sleep(active: true)
        recovery.cancel()
        XCTAssertFalse(recovery.wake())
    }
    @MainActor func testWakeWaitsForDriverReconnect() async throws {
        var attempts = 0
        try await KeyboardStartRecovery.run(recoveringFromSleep: true, isCurrent: { true }, waiting: {}, delay: {}) {
            attempts += 1
            if attempts < 3 { throw ClickError("Virtual keyboard unavailable. Install and activate the supported Karabiner virtual HID driver.") }
        }
        XCTAssertEqual(attempts, 3)
    }
    @MainActor func testWakeRetryIsBounded() async {
        var attempts = 0
        do {
            try await KeyboardStartRecovery.run(recoveringFromSleep: true, isCurrent: { true }, waiting: {}, delay: {}) {
                attempts += 1
                throw ClickError("Keyboard service disconnected. Mappings paused.")
            }
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(attempts, 11) }
    }
}
