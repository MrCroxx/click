import Foundation

public struct ClickError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { L10n.text(message) }
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
        switch self { case .shortcut: return "Shortcut"; case .application: return "Switch Application"; case .delay: return "Delay"; case .text: return "Type Text" }
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
    public var name = "New Macro"
    public var steps: [MacroStep] = []
    public init(name: String = "New Macro", steps: [MacroStep] = []) { self.name = name; self.steps = steps }
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
        guard version == 1 else { throw ClickError(L10n.format("Unsupported configuration version: %d", version)) }
        guard profiles.count <= 64, macros.count <= 128 else { throw ClickError("Configuration is too large.") }
        guard Set(profiles.map(\.id)).count == profiles.count, Set(macros.map(\.id)).count == macros.count else { throw ClickError("Duplicate configuration IDs.") }
        for (index, profile) in profiles.enumerated() {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClickError("A device name is required.") }
            guard profile.device.vendor >= 0, profile.device.product >= 0, profile.device.location >= 0 else { throw ClickError("Invalid device identity.") }
            if profiles.prefix(index).contains(where: { $0.device.matches(profile.device) || profile.device.matches($0.device) }) { throw ClickError("Only one profile is allowed per device.") }
            guard profile.bindings.count <= 128,
                  Set(profile.bindings.map(\.source)).count == profile.bindings.count,
                  Set(profile.bindings.map(\.id)).count == profile.bindings.count else { throw ClickError("Duplicate keys or too many mappings.") }
            for binding in profile.bindings {
                guard KeyCatalog.keys.contains(where: { $0.id == binding.source }) else { throw ClickError("Invalid source key.") }
                switch binding.kind {
                case .key:
                    guard KeyCatalog.keys.contains(where: { $0.id == binding.destination }) else { throw ClickError("Invalid destination key.") }
                case .macro:
                    guard macros.contains(where: { $0.id == binding.macroID }) else { throw ClickError("The assigned macro no longer exists.") }
                    guard !KeyCatalog.isModifier(binding.source) else { throw ClickError("Modifier keys cannot trigger macros.") }
                }
            }
        }
        for macro in macros {
            guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !macro.steps.isEmpty, macro.steps.count <= 100,
                  Set(macro.steps.map(\.id)).count == macro.steps.count else { throw ClickError("A macro needs a name and 1–100 uniquely identified steps.") }
            for step in macro.steps {
                switch step.kind {
                case .shortcut:
                    guard KeyCatalog.keys.contains(where: { $0.id == step.shortcut.key }), !KeyCatalog.isModifier(step.shortcut.key) else { throw ClickError("A shortcut needs a non-modifier key.") }
                case .application:
                    guard !step.value.isEmpty, step.value.contains("."), !step.value.contains("/") else { throw ClickError("Choose an application or enter its bundle identifier.") }
                case .delay:
                    guard (0...60_000).contains(step.milliseconds) else { throw ClickError("Delay must be between 0 and 60,000 ms.") }
                case .text:
                    guard step.value.utf16.count <= 4096 else { throw ClickError("Text cannot exceed 4,096 UTF-16 units per step.") }
                }
            }
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 2_000_000 else { throw ClickError("Configuration files cannot exceed 2 MB.") }
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
