import AppKit
import ClickCore

@MainActor
final class MacroRunner {
    nonisolated static let marker: Int64 = 0x434C49434B
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let authorized: () -> Bool
    private let frontmost: () -> String?
    private let activate: (String) async throws -> Void
    private let shortcutOutput: ((Shortcut) async throws -> Void)?
    private let textOutput: ((String) throws -> Void)?
    init(authorized: @escaping () -> Bool = { AXIsProcessTrusted() },
         frontmost: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
         activate: @escaping (String) async throws -> Void = { try await MacroRunner.activateApplication($0) },
         shortcutOutput: ((Shortcut) async throws -> Void)? = nil,
         textOutput: ((String) throws -> Void)? = nil) {
        self.authorized = authorized; self.frontmost = frontmost; self.activate = activate
        self.shortcutOutput = shortcutOutput; self.textOutput = textOutput
    }
    var onStatus: (String) -> Void = { _ in }
    private(set) var busy = false
    func cancel() { generation = UUID(); task?.cancel(); task = nil; busy = false }
    func run(_ macro: Macro) {
        guard !busy else { onStatus("A macro is already running."); return }
        guard authorized() else { onStatus("Accessibility permission is required to run macros."); return }
        busy = true
        let token = UUID(); generation = token
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.busy = false; self.task = nil } }
            do {
                var expected: String?
                for step in macro.steps {
                    try Task.checkCancellation()
                    if let expected, frontmost() != expected {
                        throw ClickError("The foreground application changed. Macro stopped.")
                    }
                    switch step.kind {
                    case .application:
                        try await activate(step.value)
                        try Task.checkCancellation()
                        guard frontmost() == step.value else { throw ClickError("The application did not gain focus. Macro stopped.") }
                        expected = step.value
                    case .delay: try await Task.sleep(nanoseconds: UInt64(step.milliseconds) * 1_000_000)
                    case .shortcut:
                        if let shortcutOutput { try await shortcutOutput(step.shortcut) } else { try emit(step.shortcut) }
                    case .text:
                        if let textOutput { try textOutput(step.value) } else { try emitText(step.value) }
                    }
                    // 给应用留出处理事件的时间，同时允许取消。
                    try await Task.sleep(nanoseconds: 30_000_000)
                }
                self.onStatus(L10n.format("Completed: %@", macro.name))
            } catch is CancellationError { self.onStatus("Macro cancelled") }
            catch { self.onStatus(error.localizedDescription) }
        }
    }
    private static func activateApplication(_ identifier: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { throw ClickError(L10n.format("Application not found: %@", identifier)) }
        let options = NSWorkspace.OpenConfiguration(); options.activates = true
        // 回调写入状态，等待循环可取消且有明确截止时间。
        var launchResult: Result<NSRunningApplication, Error>?
        NSWorkspace.shared.openApplication(at: url, configuration: options) { app, error in
            Task { @MainActor in
                if let app { launchResult = .success(app) }
                else { launchResult = .failure(error ?? ClickError("Application launch failed.")) }
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            try Task.checkCancellation()
            if let launchResult {
                let app = try launchResult.get()
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw ClickError("The application did not gain focus. Macro stopped.")
    }
    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }
    private func emit(_ shortcut: Shortcut) throws {
        throw ClickError("Keyboard service is not running.")
    }
    private func emitText(_ text: String) throws {
        guard let source = CGEventSource(stateID: .privateState) else { throw ClickError("Unable to create a keyboard event source.") }
        // 按 Character 分块，避免切开 surrogate pair 或组合字符。
        for character in text {
            let units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { throw ClickError("Unable to create a text event.") }
            down.flags = []; up.flags = []
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            post(down); post(up)
        }
    }
}
