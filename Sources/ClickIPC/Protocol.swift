import Foundation

public enum ClickService {
    public static let name = "com.mrcroxx.click.daemon"
    public static let plist = name + ".plist"
}

@objc public protocol ClickDaemonProtocol {
    func configure(_ data: Data, standardFunctionKeys: Bool, withReply reply: @escaping (String?) -> Void)
    func stop(withReply reply: @escaping () -> Void)
    func heartbeat(withReply reply: @escaping (Bool) -> Void)
    func shortcut(_ data: Data, withReply reply: @escaping (String?) -> Void)
}
@objc public protocol ClickAgentProtocol {
    func trigger(_ id: String)
    func failed(_ message: String)
}
