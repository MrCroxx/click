import Foundation

/// A device's original usage is resolved once, on key-down. No keycodes, layouts,
/// event taps, or input-method state participate in routing.
public struct RawInputRouter {
    public struct Key: Hashable, Sendable {
        public let page: UInt32
        public let usage: UInt16
        public init(page: UInt32 = 7, usage: UInt16) { self.page = page; self.usage = usage }
    }
    private enum Output { case key(Key), macro(UUID) }
    private var held: [UInt64: [Key: Output]] = [:]
    public let configuration: Configuration
    public init(configuration: Configuration) { self.configuration = configuration }
    public mutating func input(device: UInt64, identity: DeviceIdentity, key: Key, down: Bool) -> UUID? {
        if !down { held[device]?[key] = nil; return nil }
        guard held[device]?[key] == nil else { return nil }
        var output = Output.key(key)
        if key.page == 7,
           let profile = configuration.profiles.first(where: { $0.enabled && $0.device.matches(identity) }),
           let binding = profile.bindings.first(where: { $0.source == Int(key.usage) }) {
            if binding.kind == .macro, let id = binding.macroID { output = .macro(id) }
            else { output = .key(Key(usage: UInt16(binding.destination))) }
        }
        held[device, default: [:]][key] = output
        if case .macro(let id) = output { return id }
        return nil
    }
    public var keys: Set<Key> {
        Set(held.values.flatMap { $0.values }.compactMap { if case .key(let key) = $0 { return key }; return nil })
    }
    public mutating func disconnect(_ device: UInt64) { held[device] = nil }
    public mutating func reset() { held.removeAll() }
}
