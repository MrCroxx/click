import Foundation

/// A physical keyboard may expose several independent HID interfaces. Only
/// interfaces whose entire input can be forwarded are eligible for seizure.
public enum HIDInterfacePolicy {
    public static let pages: [UInt32] = [0x00ff, 0xff01, 7, 12, 1]
    public static func reportsKeyboardError(page: UInt32, usage: UInt32, value: Int) -> Bool {
        page == 7 && (1...3).contains(usage) && value != 0
    }
    /// IOHID also exposes array containers and an opaque 64-byte Apple report.
    /// These are not individual key values. Keep unknown interfaces rejected.
    public static func isKeyValue(vendor: Int, isBuiltInApple: Bool = false, page: UInt32, usage: UInt32, reportSize: UInt32) -> Bool {
        guard usage > 0, usage <= UInt16.max else { return false }
        return !((vendor == 0x05ac || isBuiltInApple) && page == 0xff00 && usage == 6 && reportSize == 512)
    }
    public struct Input {
        public let page: UInt32
        public let usage: UInt32
        public init(page: UInt32, usage: UInt32) { self.page = page; self.usage = usage }
    }
    public static func supports(_ inputs: [Input]) -> Bool {
        !inputs.isEmpty && inputs.allSatisfy {
            pages.contains($0.page) && ($0.page != 1 || (0x81...0x93).contains($0.usage))
        }
    }
    public struct Interface {
        public let id: UInt64
        public let identity: DeviceIdentity
        public let supported: Bool
        public init(id: UInt64, identity: DeviceIdentity, supported: Bool) {
            self.id = id; self.identity = identity; self.supported = supported
        }
    }
    /// An unsupported sibling stays with macOS. A configured device with no
    /// supported interface is an error, rather than a silently ignored profile.
    public static func select(_ interfaces: [Interface]) throws -> Set<UInt64> {
        let eligible = interfaces.filter(\.supported)
        for interface in interfaces where !interface.supported {
            guard eligible.contains(where: {
                interface.identity.matches($0.identity) && $0.identity.matches(interface.identity)
            }) else { throw ClickError("This keyboard interface contains unsupported HID inputs. It was not captured.") }
        }
        return Set(eligible.map(\.id))
    }
}
