import Foundation

/// A device's original usage is resolved once, on key-down. No keycodes, layouts,
/// event taps, or input-method state participate in routing.
public struct RawInputRouter {
    public struct Key: Hashable, Sendable {
        public let page: UInt32
        public let usage: UInt16
        public init(page: UInt32 = 7, usage: UInt16) { self.page = page; self.usage = usage }
    }
    private enum Output { case keys(Set<Key>), macro(UUID) }
    private var held: [UInt64: [Key: Output]] = [:]
    public let configuration: Configuration
    public init(configuration: Configuration) { self.configuration = configuration }
    public mutating func input(device: UInt64, identity: DeviceIdentity, key: Key, down: Bool, builtInApple: Bool = false, standardFunctionKeys: Bool = false) -> UUID? {
        if !down { held[device]?[key] = nil; return nil }
        guard held[device]?[key] == nil else { return nil }
        var output = Output.keys([key])
        if key.page == 7,
           let profile = configuration.profiles.first(where: { $0.enabled && $0.device.matches(identity) }),
           let binding = profile.bindings.first(where: { $0.source == Int(key.usage) }) {
            if binding.kind == .macro, let id = binding.macroID { output = .macro(id) }
            else {
                var keys: Set<Key> = [Key(page: binding.destinationPage ?? 7, usage: UInt16(binding.destination))]
                if binding.fn == true { keys.insert(Key(page: 0x00ff, usage: 3)) }
                output = .keys(keys)
            }
        }
        else if builtInApple, key.page == 7, (58...69).contains(key.usage) {
            let fnDown = held.values.contains { inputs in
                inputs.contains { source, output in
                    // Synthetic Fn attached to another F key is not a physical Fn press.
                    guard !(source.page == 7 && (58...69).contains(source.usage)), case .keys(let keys) = output else { return false }
                    return keys.contains(Key(page: 0x00ff, usage: 3)) || keys.contains(Key(page: 0xff01, usage: 3))
                }
            }
            if fnDown == standardFunctionKeys {
                output = .keys([AppleFunctionKeys.mediaKey(for: key.usage)])
            } else {
                // macOS interprets virtual F keys using the same system preference.
                output = .keys(standardFunctionKeys ? [key] : [key, Key(page: 0x00ff, usage: 3)])
            }
        }
        held[device, default: [:]][key] = output
        if case .macro(let id) = output { return id }
        return nil
    }
    public var keys: Set<Key> {
        Set(held.values.flatMap { $0.values }.flatMap { output -> Set<Key> in
            if case .keys(let keys) = output { return keys }; return []
        })
    }
    public mutating func disconnect(_ device: UInt64) { held[device] = nil }
    public mutating func reset() { held.removeAll() }
}
