import Foundation

/// Forward one physical report at a time, keeping buttons held by other devices
/// and preserving signed motion when splitting into the driver's 8-bit reports.
public struct PointingInputRouter {
    public struct Value {
        public let input: HIDInterfacePolicy.Input
        public let value: Int
        public init(input: HIDInterfacePolicy.Input, value: Int) { self.input = input; self.value = value }
    }
    public struct Report: Equatable {
        public let buttons: UInt32
        public let x: Int8
        public let y: Int8
        public let vertical: Int8
        public let horizontal: Int8
    }
    private var held: [UInt64: UInt32] = [:]
    public init() {}
    public var buttons: UInt32 { held.values.reduce(0, |) }
    public mutating func input(device: UInt64, values: [Value]) -> [Report] {
        var motion = [0, 0, 0, 0]
        for entry in values {
            let input = entry.input
            switch input.kind {
            case .button:
                let mask = UInt32(1) << (input.usage - 1)
                if entry.value == 0 { held[device, default: 0] &= ~mask }
                else { held[device, default: 0] |= mask }
            case .motion:
                let index = input.page == 12 ? 3 : (input.usage == 0x30 ? 0 : (input.usage == 0x31 ? 1 : 2))
                motion[index] += entry.value
            default: break
            }
        }
        var reports: [Report] = []
        repeat {
            let part = motion.map { Int8(max(-127, min(127, $0))) }
            reports.append(Report(buttons: buttons, x: part[0], y: part[1], vertical: part[2], horizontal: part[3]))
            for i in motion.indices { motion[i] -= Int(part[i]) }
        } while motion.contains(where: { $0 != 0 })
        return reports
    }
    public mutating func disconnect(_ device: UInt64) -> Report {
        held[device] = nil
        return Report(buttons: buttons, x: 0, y: 0, vertical: 0, horizontal: 0)
    }
    public mutating func reset() -> Report {
        held.removeAll()
        return Report(buttons: 0, x: 0, y: 0, vertical: 0, horizontal: 0)
    }
}
