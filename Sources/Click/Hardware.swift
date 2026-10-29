import Foundation
import IOKit.hidsystem
import IOKit.hid
import ClickCore

struct ConnectedDevice: Identifiable {
    let id: UInt64
    let name: String
    let identity: DeviceIdentity
    let transport: String
}
struct RecoveryEntry: Codable {
    let registryID: UInt64
    let identity: DeviceIdentity
    let original: [HIDMapping]
    let applied: [HIDMapping]
}

final class Hardware {
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private let journalURL: URL
    private var journal: [RecoveryEntry] = []
    init(directory: URL) throws {
        journalURL = directory.appendingPathComponent("recovery.json")
        if FileManager.default.fileExists(atPath: journalURL.path) {
            journal = try JSONDecoder().decode([RecoveryEntry].self, from: Data(contentsOf: journalURL))
        }
    }
    func devices() -> [ConnectedDevice] {
        // Enumerate the same physical HID identities as the daemon. Event-system
        // services can cache a USB identity after a keyboard switches to BLE.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary)
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).compactMap { device in
            func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
            func string(_ key: String) -> String { IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "" }
            guard !(number("VendorID") == 0x16c0 && number("ProductID") == 0x27db),
                  !string("Product").localizedCaseInsensitiveContains("virtual") else { return nil }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
            return ConnectedDevice(id: id, name: string("Product").isEmpty ? "Keyboard" : string("Product"),
                identity: DeviceIdentity(vendor: number("VendorID"), product: number("ProductID"), serial: string("SerialNumber"), location: number("LocationID")),
                transport: string("Transport"))
        }.sorted { $0.id < $1.id }
    }
    private struct LegacyDevice {
        let id: UInt64
        let identity: DeviceIdentity
        let service: IOHIDServiceClient
    }
    private func legacyDevices() -> [LegacyDevice] {
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.compactMap { service in
            guard IOHIDServiceClientConformsTo(service, 1, 6) != 0 else { return nil }
            func number(_ key: String) -> Int { (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue ?? 0 }
            func string(_ key: String) -> String { IOHIDServiceClientCopyProperty(service, key as CFString) as? String ?? "" }
            guard !(number("VendorID") == 0x16c0 && number("ProductID") == 0x27db),
                  !string("Product").localizedCaseInsensitiveContains("virtual") else { return nil }
            let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
            return LegacyDevice(id: id,
                identity: DeviceIdentity(vendor: number("VendorID"), product: number("ProductID"), serial: string("SerialNumber"), location: number("LocationID")),
                service: service)
        }.sorted { $0.id < $1.id }
    }
    private func read(_ service: IOHIDServiceClient) throws -> [HIDMapping] {
        guard let raw = IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString) else { return [] }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode([HIDMapping].self, from: data)
    }
    private func write(_ mappings: [HIDMapping], to service: IOHIDServiceClient) throws {
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mappings)) as! NSArray
        guard IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, raw), try read(service) == mappings else {
            throw ClickError("macOS rejected the mapping. Enable Input Monitoring and retry. Some devices or system versions restrict letter-key mappings.")
        }
    }
    private func saveJournal() throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
    }
    func restore() throws {
        let connected = legacyDevices()
        var failures: [String] = []
        for entry in journal {
            guard let device = connected.first(where: { $0.id == entry.registryID && entry.identity.matches($0.identity) }) else { continue }
            do {
                // 其他程序改过映射时，不覆盖它；只有仍属于本次运行的值才恢复。
                let current = try read(device.service)
                let restored = MappingRestoration.restore(current: current, original: entry.original, applied: entry.applied)
                if restored != current { try write(restored, to: device.service) }
            } catch { failures.append(error.localizedDescription); continue }
        }
        if !failures.isEmpty { throw ClickError(failures.joined(separator: "\n")) }
        journal = []; try saveJournal()
    }
}
