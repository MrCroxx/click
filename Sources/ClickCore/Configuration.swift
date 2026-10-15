import Foundation

public struct ClickError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct DeviceIdentity: Codable, Equatable, Hashable, Sendable {
    public var vendor: Int
    public var product: Int
    public var serial: String
    public var location: Int
    public init(vendor: Int, product: Int, serial: String = "", location: Int) {
        self.vendor = vendor; self.product = product; self.serial = serial; self.location = location
    }
    public func matches(_ other: Self) -> Bool {
        vendor == other.vendor && product == other.product &&
        (serial.isEmpty ? location == other.location : serial == other.serial)
    }
}

public struct Shortcut: Codable, Equatable, Sendable {
    public var key: Int
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool
    public init(key: Int = 40, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.key = key; self.command = command; self.option = option; self.control = control; self.shift = shift
    }
    public var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + KeyCatalog.name(key)
    }
}

public enum StepKind: String, Codable, CaseIterable, Sendable {
    case shortcut, application, delay, text
    public var title: String {
        switch self { case .shortcut: return "快捷键"; case .application: return "切换应用"; case .delay: return "等待"; case .text: return "输入文本" }
    }
    public var icon: String {
        switch self { case .shortcut: return "command"; case .application: return "app.badge"; case .delay: return "clock"; case .text: return "text.cursor" }
    }
}
public struct MacroStep: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: StepKind
    public var shortcut = Shortcut()
    public var value = ""
    public var milliseconds = 250
    public init(kind: StepKind) { self.kind = kind }
}
public struct Macro: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name = "新宏"
    public var steps: [MacroStep] = []
    public init(name: String = "新宏", steps: [MacroStep] = []) { self.name = name; self.steps = steps }
}
public enum BindingKind: String, Codable, CaseIterable, Sendable { case key, macro }
public struct KeyBinding: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var source: Int = 57
    public var kind: BindingKind = .key
    public var destination: Int = 41
    public var macroID: UUID?
    public init() {}
}
public struct DeviceProfile: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var device: DeviceIdentity
    public var enabled = false
    public var bindings: [KeyBinding] = []
    public init(name: String, device: DeviceIdentity) { self.name = name; self.device = device }
}
public struct Configuration: Codable, Equatable, Sendable {
    public var version = 1
    public var profiles: [DeviceProfile] = []
    public var macros: [Macro] = []
    public init() {}
    public func validate() throws {
        guard version == 1 else { throw ClickError("不支持的配置版本：\(version)") }
        guard profiles.count <= 64, macros.count <= 128 else { throw ClickError("配置过大。") }
        guard Set(profiles.map(\.id)).count == profiles.count, Set(macros.map(\.id)).count == macros.count else { throw ClickError("配置包含重复 ID。") }
        for (index, profile) in profiles.enumerated() {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClickError("设备名称不能为空。") }
            guard profile.device.vendor >= 0, profile.device.product >= 0, profile.device.location >= 0 else { throw ClickError("设备标识无效。") }
            if profiles.prefix(index).contains(where: { $0.device.matches(profile.device) || profile.device.matches($0.device) }) { throw ClickError("同一设备只能有一个配置。") }
            guard profile.bindings.count <= 128,
                  Set(profile.bindings.map(\.source)).count == profile.bindings.count,
                  Set(profile.bindings.map(\.id)).count == profile.bindings.count else { throw ClickError("设备包含重复按键或过多映射。") }
            for binding in profile.bindings {
                guard KeyCatalog.keys.contains(where: { $0.id == binding.source }) else { throw ClickError("无效的输入键。") }
                switch binding.kind {
                case .key:
                    guard KeyCatalog.keys.contains(where: { $0.id == binding.destination }) else { throw ClickError("无效的输出键。") }
                case .macro:
                    guard macros.contains(where: { $0.id == binding.macroID }) else { throw ClickError("映射引用的宏不存在。") }
                    guard !KeyCatalog.isModifier(binding.source) else { throw ClickError("修饰键不能作为宏触发键。") }
                }
            }
        }
        for macro in macros {
            guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !macro.steps.isEmpty, macro.steps.count <= 100,
                  Set(macro.steps.map(\.id)).count == macro.steps.count else { throw ClickError("宏需要名称和 1–100 个步骤，步骤 ID 不能重复。") }
            for step in macro.steps {
                switch step.kind {
                case .shortcut:
                    guard KeyCatalog.keys.contains(where: { $0.id == step.shortcut.key }), !KeyCatalog.isModifier(step.shortcut.key) else { throw ClickError("快捷键需要一个普通按键。") }
                case .application:
                    guard !step.value.isEmpty, step.value.contains("."), !step.value.contains("/") else { throw ClickError("请选择应用或填写 Bundle ID。") }
                case .delay:
                    guard (0...60_000).contains(step.milliseconds) else { throw ClickError("等待时间应为 0–60000 毫秒。") }
                case .text:
                    guard step.value.utf16.count <= 4096 else { throw ClickError("单步文本不能超过 4096 个 UTF-16 单元。") }
                }
            }
        }
        _ = try MappingPlan(configuration: self)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 2_000_000 else { throw ClickError("配置文件不能超过 2 MB。") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public struct HIDMapping: Codable, Equatable, Sendable {
    public var source: UInt64
    public var destination: UInt64
    public init(source: Int, destination: Int) {
        self.source = 0x700000000 | UInt64(source); self.destination = 0x700000000 | UInt64(destination)
    }
    enum CodingKeys: String, CodingKey {
        case source = "HIDKeyboardModifierMappingSrc", destination = "HIDKeyboardModifierMappingDst"
    }
}
public struct MappingPlan {
    public var maps: [UUID: [HIDMapping]] = [:]
    public var triggers: [Int: UUID] = [:]
    public init(configuration: Configuration) throws {
        // F13–F20 是宏的传输键；按全局配置稳定分配，设备离线不改变编号。
        let active = configuration.profiles.filter(\.enabled)
        let macroBindings = active.flatMap(\.bindings).filter { $0.kind == .macro }
        guard macroBindings.count <= 8 else { throw ClickError("最多同时启用 8 个宏触发键。") }
        let reserved = Set((0..<macroBindings.count).map { 104 + $0 })
        for binding in active.flatMap(\.bindings) {
            if reserved.contains(binding.source) || (binding.kind == .key && reserved.contains(binding.destination)) {
                throw ClickError("F13–F\(12 + macroBindings.count) 已被宏保留，请选择其他按键。")
            }
        }
        var slot = 104
        for profile in active {
            maps[profile.id] = profile.bindings.map { binding in
                if binding.kind == .key { return HIDMapping(source: binding.source, destination: binding.destination) }
                defer { slot += 1 }
                if let id = binding.macroID { triggers[slot] = id }
                return HIDMapping(source: binding.source, destination: slot)
            }
        }
    }
}
