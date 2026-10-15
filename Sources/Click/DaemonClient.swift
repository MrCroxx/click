import Foundation
import ClickCore
import ClickIPC

@MainActor final class DaemonClient: NSObject, ClickAgentProtocol {
    var onTrigger: (UUID) -> Void = { _ in }
    var onFailure: (String) -> Void = { _ in }
    private var connection: NSXPCConnection?
    private var heartbeatTimer: Timer?
    private var active = false
    private var generation = UUID()
    private func connect() -> NSXPCConnection {
        if let connection { return connection }
        let value = NSXPCConnection(machServiceName: ClickService.name, options: .privileged)
        value.remoteObjectInterface = NSXPCInterface(with: ClickDaemonProtocol.self)
        value.exportedInterface = NSXPCInterface(with: ClickAgentProtocol.self)
        value.exportedObject = self
        value.invalidationHandler = { [weak self, weak value] in
            DispatchQueue.main.async {
                guard let self, let value, self.connection === value else { return }
                self.connection = nil
                if self.active { self.failed("Keyboard service disconnected. Mappings paused.") }
            }
        }
        value.interruptionHandler = { [weak self, weak value] in
            DispatchQueue.main.async {
                guard let self, let value, self.connection === value else { return }
                self.failed("Keyboard service disconnected. Mappings paused.")
            }
        }
        value.resume(); connection = value
        return value
    }
    func start(_ configuration: Configuration) async throws {
        let token = UUID(); generation = token
        let data = try configuration.encoded()
        let connection = connect()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let reply = ServiceReply { continuation.resume(with: $0) }
                let proxy = connection.remoteObjectProxyWithErrorHandler { reply.finish(.failure($0)) } as! ClickDaemonProtocol
                proxy.configure(data) { message in
                    if let message { reply.finish(.failure(ClickError(message))) }
                    else { reply.finish(.success(())) }
                }
            }
        } catch {
            stop()
            connection.invalidate()
            if self.connection === connection { self.connection = nil }
            throw error
        }
        guard generation == token else { stop(); throw CancellationError() }
        active = true
        heartbeatTimer?.invalidate()
        heartbeatTimer = ServiceHeartbeat.schedule { [weak self] in self?.heartbeat() }
    }
    private func heartbeat() {
        guard active, let connection else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in self?.failed("Keyboard service disconnected. Mappings paused.") } as? ClickDaemonProtocol
        proxy?.heartbeat { [weak self] running in
            if !running { self?.failed("Keyboard service disconnected. Mappings paused.") }
        }
    }
    func stop() {
        generation = UUID()
        active = false; heartbeatTimer?.invalidate(); heartbeatTimer = nil
        (connection?.remoteObjectProxy as? ClickDaemonProtocol)?.stop {}
    }
    func shortcut(_ shortcut: Shortcut) async throws {
        guard active, let connection else { throw ClickError("Keyboard service is not running.") }
        let data = try JSONEncoder().encode(shortcut)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { continuation.resume(throwing: $0) } as! ClickDaemonProtocol
            proxy.shortcut(data) { message in
                if let message { continuation.resume(throwing: ClickError(message)) } else { continuation.resume() }
            }
        }
    }
    nonisolated func trigger(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, let id = UUID(uuidString: id) else { return }
            self.onTrigger(id)
        }
    }
    nonisolated func failed(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active else { return }
            self.stop(); self.onFailure(message)
        }
    }
}
