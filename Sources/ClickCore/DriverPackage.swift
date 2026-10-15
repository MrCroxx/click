import Foundation
import CryptoKit

public enum DriverPackage {
    public static let version = "8.6.0"
    public static let fileName = "Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg"
    public static let downloadURL = URL(string: "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v8.6.0/\(fileName)")!
    public static let releaseURL = URL(string: "https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v8.6.0")!
    // GitHub's release-asset digest, independently checked against the signed pkg.
    public static let sha256 = "ff8c7fdc5e25387c7805fc7509a0fa9cf98f69ba582704f717fddcae47424387"
    public static let byteCount = 2_089_875
    public static let teamID = "G43BCU2T37"
    public static let daemonPlist = "org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist"
    public static let managerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
    public static let daemonPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app"
    public static func supports(_ version: String?) -> Bool { version == "8.5.0" || version == "8.6.0" }
    public static func verify(_ data: Data) throws {
        guard data.count == byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw ClickError("Driver download verification failed. Try again.")
        }
    }
}
