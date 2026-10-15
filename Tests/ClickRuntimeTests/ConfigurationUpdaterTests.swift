import XCTest
import ClickCore
@testable import Click

final class ConfigurationUpdaterTests: XCTestCase {
    @MainActor func testEnabledPersistsEvenWhenHardwareFails() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigurationStore(url: url)
        var config = Configuration()
        var profile = DeviceProfile(name: "Keyboard", device: .init(vendor: 1, product: 2, location: 3))
        profile.enabled = true; profile.bindings = [KeyBinding()]; config.profiles = [profile]
        let failed = expectation(description: "hardware failure reported")
        let updater = ConfigurationUpdater(delay: 0, persist: { try store.save($0) }, apply: { _ in throw ClickError("unavailable") }, stop: {})
        updater.onState = { if case .applyFailed = $0 { failed.fulfill() } }
        updater.submit(config)
        XCTAssertEqual(try store.load(), config)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(try store.load().profiles[0].enabled)
    }
    @MainActor func testEditsDuringApplyAreSerializedAndLatestWins() async throws {
        var applied: [Configuration] = []
        var saved: [Configuration] = []
        var release: CheckedContinuation<Void, Never>?
        let began = expectation(description: "first apply")
        let done = expectation(description: "latest applied")
        let updater = ConfigurationUpdater(delay: 0, persist: { saved.append($0) }, apply: { config in
            applied.append(config)
            if applied.count == 1 { await withCheckedContinuation { release = $0; began.fulfill() } }
        }, stop: {})
        updater.onState = { if case .applied = $0 { done.fulfill() } }
        let first = Configuration()
        var second = first; second.macros = [Macro(name: "Second", steps: [MacroStep(kind: .delay)])]
        var third = first; third.macros = [Macro(name: "Third", steps: [MacroStep(kind: .delay)])]
        updater.submit(first)
        await fulfillment(of: [began], timeout: 2)
        updater.submit(second); updater.submit(third)
        XCTAssertEqual(saved, [first, second, third])
        release?.resume()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(applied, [first, third])
    }
    @MainActor func testPauseCancelsPendingApplicationButKeepsSavedConfig() async throws {
        var persisted = false
        let updater = ConfigurationUpdater(delay: 30_000_000, persist: { _ in persisted = true }, apply: { _ in XCTFail("Applied after pause") }, stop: {})
        updater.submit(Configuration()); updater.cancel()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(persisted)
    }
    @MainActor func testSaveFailureNeverApplies() async throws {
        let updater = ConfigurationUpdater(delay: 0, persist: { _ in throw ClickError("disk full") }, apply: { _ in XCTFail("Applied unsaved data") }, stop: {})
        var failure: String?
        updater.onState = { if case .saveFailed(let message) = $0 { failure = message } }
        updater.submit(Configuration())
        XCTAssertEqual(failure, "disk full")
    }
    func testTimeoutAndLateReplyCompleteOnlyOnce() async {
        let done = expectation(description: "timed out")
        done.assertForOverFulfill = true
        let reply = ServiceReply(timeout: 0.01) { result in
            if case .success = result { XCTFail("Expected timeout") }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)
        reply.finish(.success(()))
    }
}
