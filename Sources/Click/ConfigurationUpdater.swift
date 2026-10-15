import Foundation
import ClickCore

/// Persist immediately, then serialize and coalesce hardware updates.
@MainActor
final class ConfigurationUpdater {
    enum State { case saved, applying, applied, saveFailed(String), applyFailed(String) }
    var onState: (State) -> Void = { _ in }
    private let persist: (Configuration) throws -> Void
    private let apply: (Configuration) async throws -> Void
    private let stop: () throws -> Void
    private let delay: UInt64
    private var pending: Configuration?
    private var revision = 0
    private var worker: Task<Void, Never>?

    init(delay: UInt64 = 250_000_000, persist: @escaping (Configuration) throws -> Void,
         apply: @escaping (Configuration) async throws -> Void, stop: @escaping () throws -> Void) {
        self.delay = delay; self.persist = persist; self.apply = apply; self.stop = stop
    }
    func submit(_ configuration: Configuration) {
        revision += 1
        pending = nil
        do {
            try configuration.validate()
            try persist(configuration)
        } catch {
            try? stop()
            onState(.saveFailed(error.localizedDescription)); return
        }
        onState(.saved)
        do { try stop() }
        catch { onState(.applyFailed(error.localizedDescription)); return }
        pending = configuration
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            defer { self.worker = nil }
            while let draft = self.pending {
                let token = self.revision
                try? await Task.sleep(nanoseconds: self.delay)
                guard token == self.revision else { continue }
                self.pending = nil
                self.onState(.applying)
                do {
                    try await self.apply(draft)
                    if token == self.revision { self.onState(.applied) }
                } catch {
                    if token == self.revision {
                        try? self.stop()
                        self.onState(.applyFailed(error.localizedDescription))
                    }
                }
            }
        }
    }
    func cancel() { revision += 1; pending = nil }
}
