import Foundation
import SystemConfiguration
import Security
import ClickCore
import ClickIPC
import VirtualHID
import MachO

func consoleUID() -> uid_t? {
    var uid: uid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, nil), name as String != "loginwindow", uid != 0 else { return nil }
    return uid
}

final class Session: NSObject, ClickDaemonProtocol {
    let connection: NSXPCConnection
    let grabber = Grabber()
    var lastHeartbeat = Date()
    private var operation = UUID()
    init(_ connection: NSXPCConnection) {
        self.connection = connection
        super.init()
        grabber.onTrigger = { [weak self] id in self?.agent?.trigger(id.uuidString) }
        grabber.onFailure = { [weak self] message in self?.agent?.failed(message) }
    }
    var agent: ClickAgentProtocol? { connection.remoteObjectProxy as? ClickAgentProtocol }
    var authorized: Bool { consoleUID() == connection.effectiveUserIdentifier }
    func configure(_ data: Data, standardFunctionKeys: Bool, withReply reply: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard self.authorized else { reply("The active user session changed."); return }
            do {
                let configuration = try Configuration.decode(data)
                self.grabber.stop()
                self.grabber.standardFunctionKeys = standardFunctionKeys
                let token = UUID(); self.operation = token; self.lastHeartbeat = Date()
                self.configureWhenReady(configuration, token: token, deadline: Date().addingTimeInterval(3), reply: reply)
            } catch { reply(error.localizedDescription) }
        }
    }
    private func configureWhenReady(_ configuration: Configuration, token: UUID, deadline: Date, reply: @escaping (String?) -> Void) {
        guard operation == token, authorized else { reply("Keyboard output cancelled."); return }
        if !click_hid_ready() && Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.configureWhenReady(configuration, token: token, deadline: deadline, reply: reply)
            }
            return
        }
        do { try grabber.start(configuration); reply(nil) }
        catch { reply(error.localizedDescription) }
    }
    func stop(withReply reply: @escaping () -> Void) { DispatchQueue.main.async { self.operation = UUID(); self.grabber.stop(); reply() } }
    func invalidate() { operation = UUID(); grabber.stop() }
    func heartbeat(withReply reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard self.authorized else { self.grabber.stop(); reply(false); return }
            self.lastHeartbeat = Date(); reply(self.grabber.running && click_hid_ready())
        }
    }
    func shortcut(_ data: Data, withReply reply: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard self.authorized, data.count <= 1024, let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else { reply("Invalid shortcut request."); return }
            self.grabber.shortcut(shortcut, completion: reply)
        }
    }
}
final class Listener: NSObject, NSXPCListenerDelegate {
    var session: Session?
    private let requirement: SecRequirement?
    override init() {
        // Capture the enclosing, signed application's designated requirement once.
        // Ad-hoc builds bind to its exact code hash; Developer ID builds bind to
        // the app identifier and signing team. Unsigned/bare daemon runs are denied.
        // launchd supplies a bundle-relative argv[0]. Resolve the actual loaded
        // executable instead of interpreting that argument relative to `/`.
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var path = [CChar](repeating: 0, count: Int(size))
        let resolved = _NSGetExecutablePath(&path, &size) == 0
        let app = URL(fileURLWithPath: resolved ? String(cString: path) : "/").resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var code: SecStaticCode?
        var expected: SecRequirement?
        if app.pathExtension == "app",
           SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
           let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess {
            _ = SecCodeCopyDesignatedRequirement(code, [], &expected)
        }
        requirement = expected
        super.init()
    }
    var hasValidApplicationSignature: Bool { requirement != nil }
    private func validPeer(_ connection: NSXPCConnection) -> Bool {
        guard let requirement else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the active graphical user's UID may control input. No filesystem,
        // shell, arbitrary IOKit, or executable-path operations cross this boundary.
        guard let uid = consoleUID(), connection.effectiveUserIdentifier == uid, validPeer(connection) else { return false }
        var accepted = false
        DispatchQueue.main.sync {
            guard self.session == nil else { return }
            let session = Session(connection)
            self.session = session
            connection.exportedInterface = NSXPCInterface(with: ClickDaemonProtocol.self)
            connection.exportedObject = session
            connection.remoteObjectInterface = NSXPCInterface(with: ClickAgentProtocol.self)
            connection.invalidationHandler = { [weak self, weak session] in
                DispatchQueue.main.async {
                    guard let self, let session, self.session === session else { return }
                    session.invalidate(); self.session = nil
                    click_hid_stop(); click_hid_start()
                }
            }
            connection.resume(); accepted = true
        }
        return accepted
    }
    func check() {
        guard let session else { return }
        if !session.authorized || Date().timeIntervalSince(session.lastHeartbeat) > 5 || (session.grabber.running && !click_hid_ready()) {
            session.invalidate(); session.agent?.failed("Keyboard service disconnected. Mappings paused.")
            session.connection.invalidate()
        }
    }
}
if CommandLine.arguments.contains("--check") {
    guard Listener().hasValidApplicationSignature else {
        fputs("ClickDaemon: enclosing application signature is invalid.\n", stderr); exit(1)
    }
    print("ClickDaemon: enclosing app signature valid; raw IOHIDQueue capture; pqrs client protocol 7; no event-tap fallback")
    exit(0)
}
guard geteuid() == 0 else { fputs("ClickDaemon must be started by its registered LaunchDaemon.\n", stderr); exit(1) }
let delegate = Listener()
let listener = NSXPCListener(machServiceName: ClickService.name)
listener.delegate = delegate
click_hid_start()
listener.resume()
let watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in delegate.check() }
// launchd terminates us at logout/unregister; close the driver connection and
// release physical devices explicitly before exiting when SIGTERM is delivered.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { delegate.session?.grabber.stop(); click_hid_stop(); exit(0) }
termination.resume()
RunLoop.main.run()
