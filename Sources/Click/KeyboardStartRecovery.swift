import Foundation
import ClickCore

/// Retry only the service's transient held-key refusal. Permission, driver and
/// transport failures remain actionable errors; pause/new edits cancel this run.
@MainActor
enum KeyboardStartRecovery {
    static let heldKeys = "Release all keys before starting Keyboard Service."

    static func run(isCurrent: () -> Bool,
                    waiting: () -> Void,
                    delay: () async throws -> Void = { try await Task.sleep(nanoseconds: 1_000_000_000) },
                    start: () async throws -> Void) async throws {
        while true {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            do {
                try await start()
                guard isCurrent() else { throw CancellationError() }
                return
            } catch {
                guard isCurrent() else { throw CancellationError() }
                guard error.localizedDescription == heldKeys else { throw error }
                waiting()
                try await delay()
            }
        }
    }
}
