import Foundation
import IOKit.hidsystem
import ClickCore

struct ConnectedDevice: Identifiable {
    let id: UInt64
    let name: String
    let identity: DeviceIdentity
    let transport: String
    let service: IOHIDServiceClient
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
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        return services.compactMap { service in
            guard IOHIDServiceClientConformsTo(service, 1, 6) != 0 else { return nil }
            func number(_ key: String) -> Int { (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue ?? 0 }
            func string(_ key: String) -> String { IOHIDServiceClientCopyProperty(service, key as CFString) as? String ?? "" }
            let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
            return ConnectedDevice(id: id, name: string("Product").isEmpty ? "Keyboard" : string("Product"),
                identity: DeviceIdentity(vendor: number("VendorID"), product: number("ProductID"), serial: string("SerialNumber"), location: number("LocationID")),
                transport: string("Transport"), service: service)
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
            throw ClickError("系统拒绝设备映射。请开启输入监控权限，再重试；某些系统或设备可能限制字母键映射。")
        }
    }
    private func saveJournal() throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
    }
    func restore() throws {
        let connected = devices()
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
    func apply(_ config: Configuration, plan: MappingPlan) throws {
        try restore()
        do {
            for device in devices() {
                guard let profile = config.profiles.first(where: { $0.enabled && $0.device.matches(device.identity) }),
                      let map = plan.maps[profile.id], !map.isEmpty else { continue }
                let original = try read(device.service)
                // 保留不冲突的现有映射，并把恢复日志先写入磁盘。
                let sources = Set(map.map(\.source))
                let merged = original.filter { !sources.contains($0.source) } + map
                journal.append(RecoveryEntry(registryID: device.id, identity: device.identity, original: original, applied: merged))
                try saveJournal()
                try write(merged, to: device.service)
            }
        } catch {
            let failure = error
            do { try restore() } catch { throw ClickError("\(failure.localizedDescription)；恢复也失败：\(error.localizedDescription)") }
            throw failure
        }
    }
}
