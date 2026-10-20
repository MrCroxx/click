import XCTest
import ClickCore
@testable import Click

final class KeyboardStartRecoveryTests: XCTestCase {
    @MainActor func testRolloverRecoveryWaitsUntilAllKeysAreReleased() async throws {
        XCTAssertTrue(KeyboardStartRecovery.canRecover("Keyboard reported a rollover error. Mappings paused."))
        XCTAssertFalse(KeyboardStartRecovery.canRecover("Input Monitoring denied"))
        var pressed = true, starts = 0, waits = 0
        try await KeyboardStartRecovery.run(isCurrent: { true }, waiting: { waits += 1 }, delay: { pressed = false }) {
            starts += 1
            if pressed { throw ClickError(KeyboardStartRecovery.heldKeys) }
        }
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(waits, 1)
    }

    @MainActor func testHeldKeysRecoverWithoutManualResume() async throws {
        var attempts = 0, waits = 0
        try await KeyboardStartRecovery.run(isCurrent: { true }, waiting: { waits += 1 }, delay: {}) {
            attempts += 1
            if attempts < 4 { throw ClickError(KeyboardStartRecovery.heldKeys) }
        }
        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(waits, 3)
    }

    @MainActor func testPauseOrNewConfigurationCancelsRetry() async {
        var current = true, attempts = 0
        do {
            try await KeyboardStartRecovery.run(isCurrent: { current }, waiting: {}, delay: { current = false }) {
                attempts += 1
                throw ClickError(KeyboardStartRecovery.heldKeys)
            }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(attempts, 1)
    }

    @MainActor func testRealFailuresAreNotRetried() async {
        var attempts = 0
        do {
            try await KeyboardStartRecovery.run(isCurrent: { true }, waiting: { XCTFail("Must not wait") }, delay: {}) {
                attempts += 1
                throw ClickError("Input Monitoring denied")
            }
            XCTFail("Expected permission failure")
        } catch { XCTAssertEqual(error.localizedDescription, "Input Monitoring denied") }
        XCTAssertEqual(attempts, 1)
    }

    @MainActor func testLateSuccessCannotReactivateCancelledStart() async {
        var current = true
        do {
            try await KeyboardStartRecovery.run(isCurrent: { current }, waiting: {}, delay: {}) { current = false }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
