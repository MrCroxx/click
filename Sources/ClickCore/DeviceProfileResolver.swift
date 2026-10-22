import Foundation

/// Resolve profiles against the whole connected keyboard inventory. Keep strict
/// identity matching for recovery records and HID interface grouping.
public struct DeviceProfileResolver {
    private let profiles: [DeviceProfile]
    private let connected: Set<DeviceIdentity>

    public init(profiles: [DeviceProfile], connected: [DeviceIdentity]) {
        self.profiles = profiles
        self.connected = Set(connected)
    }

    public func profile(for device: DeviceIdentity) -> DeviceProfile? {
        guard connected.contains(device) else { return nil }
        let exact = profiles.filter { $0.device.matches(device) }
        if !exact.isEmpty { return exact.count == 1 ? exact[0] : nil }

        // A location is only a port hint for an anonymous USB keyboard. Fall
        // back to its model only when both the saved and live sides are unique.
        // Disabled profiles still count: their intent must not be overridden.
        guard device.serial.isEmpty, device.vendor != 0, device.product != 0 else { return nil }
        let sameModel: (DeviceIdentity) -> Bool = {
            $0.vendor == device.vendor && $0.product == device.product
        }
        let candidates = profiles.filter { sameModel($0.device) }
        guard candidates.count == 1, candidates[0].device.serial.isEmpty,
              connected.filter(sameModel).count == 1 else { return nil }
        return candidates[0]
    }
}
