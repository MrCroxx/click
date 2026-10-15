import XCTest
import ClickCore
@testable import Click

@MainActor
final class MacroRunnerTests: XCTestCase {
    private func finish(_ runner: MacroRunner) async throws {
        for _ in 0..<200 {
            if !runner.busy { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Macro did not finish")
    }
    func testActivationBeforeShortcut() async throws {
        var focus: String?, events: [String] = []
        let runner = MacroRunner(authorized: { true }, frontmost: { focus }, activate: { id in focus = id; events.append("focus") }, shortcutOutput: { _ in events.append("key") })
        var step = MacroStep(kind: .application); step.value = "com.test.app"
        runner.run(Macro(steps: [step, MacroStep(kind: .shortcut)]))
        try await finish(runner)
        XCTAssertEqual(events, ["focus", "key"])
    }
    func testActivationFailureStopsKeys() async throws {
        var sent = false
        let runner = MacroRunner(authorized: { true }, frontmost: { nil }, activate: { _ in throw ClickError("Missing app") }, shortcutOutput: { _ in sent = true })
        var step = MacroStep(kind: .application); step.value = "com.test.app"
        runner.run(Macro(steps: [step, MacroStep(kind: .shortcut)]))
        try await finish(runner); XCTAssertFalse(sent)
    }
    func testChangedFocusStopsText() async throws {
        var focus: String?, sent = false
        let runner = MacroRunner(authorized: { true }, frontmost: { focus }, activate: { focus = $0 }, textOutput: { _ in sent = true })
        var app = MacroStep(kind: .application); app.value = "com.test.app"
        var delay = MacroStep(kind: .delay); delay.milliseconds = 100
        runner.run(Macro(steps: [app, delay, MacroStep(kind: .text)]))
        try await Task.sleep(nanoseconds: 60_000_000); focus = "com.other.app"
        try await finish(runner); XCTAssertFalse(sent)
    }
    func testCancelDoesNotReleaseNewRunOwnership() async throws {
        var sent = 0
        let runner = MacroRunner(authorized: { true }, shortcutOutput: { _ in sent += 1 })
        var delay = MacroStep(kind: .delay); delay.milliseconds = 100
        let macro = Macro(steps: [delay, MacroStep(kind: .shortcut)])
        runner.run(macro)
        try await Task.sleep(nanoseconds: 5_000_000)
        runner.cancel(); runner.run(macro)
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(runner.busy)
        try await finish(runner); XCTAssertEqual(sent, 1)
    }
    func testBusyTriggersAreIgnored() async throws {
        var sent = 0
        let runner = MacroRunner(authorized: { true }, shortcutOutput: { _ in sent += 1 })
        let macro = Macro(steps: [MacroStep(kind: .shortcut)])
        runner.run(macro); runner.run(macro)
        try await finish(runner); XCTAssertEqual(sent, 1)
    }
    func testNoPermissionDoesNotEmit() async throws {
        var sent = false
        let runner = MacroRunner(authorized: { false }, shortcutOutput: { _ in sent = true })
        runner.run(Macro(steps: [MacroStep(kind: .shortcut)]))
        try await finish(runner); XCTAssertFalse(sent)
    }
}
