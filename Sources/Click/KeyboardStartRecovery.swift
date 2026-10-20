import Foundation
import ClickCore

/// Retry only the service's transient held-key refusal. Permission, driver and
/// transport failures remain actionable errors; pause/new edits cancel this run.
@MainActor
enum KeyboardStartRecovery {
    static let rollover = "Keyboard reported a rollover error. Mappings paused."
    static func canRecover(_ message: String) -> Bool { message == heldKeys || message == rollover }

    static let heldKeys = "Release all keys before starting Keyboard Service."

    static func run(recoveringFromSleep: Bool = false, isCurrent: () -> Bool,
                    waiting: () -> Void,
                    delay: () async throws -> Void = { try await Task.sleep(nanoseconds: 1_000_000_000) },
                    start: () async throws -> Void) async throws {
        var wakeRetries = 0
        while true {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            do {
                try await start()
                guard isCurrent() else { throw CancellationError() }
                return
            } catch {
                guard isCurrent() else { throw CancellationError() }
                if error.localizedDescription != heldKeys {
                    let transient = ["Virtual keyboard unavailable. Install and activate the supported Karabiner virtual HID driver.",
                                     "Keyboard service disconnected. Mappings paused."]
                    let nsError = error as NSError
                    let interrupted = nsError.domain == NSCocoaErrorDomain && [4097, 4099].contains(nsError.code)
                    guard recoveringFromSleep, wakeRetries < 10, transient.contains(error.localizedDescription) || interrupted else { throw error }
                    wakeRetries += 1
                }
                waiting()
                try await delay()
            }
        }
    }
}
