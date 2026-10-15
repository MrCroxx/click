import Foundation
import IOKit.hid
import ClickCore
import VirtualHID

final class Grabber {
    private struct Device {
        let handle: IOHIDDevice
        let queue: IOHIDQueue
        let identity: DeviceIdentity
    }
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices: [UInt64: Device] = [:]
    private var router = RawInputRouter(configuration: Configuration())
    private var macroKeys = Set<RawInputRouter.Key>()
    private var generation = UUID()
    var onTrigger: (UUID) -> Void = { _ in }
    var onFailure: (String) -> Void = { _ in }
    private(set) var running = false
    private let pages: [UInt32] = [7, 12, 1, 0xff01, 0x00ff]

    func start(_ configuration: Configuration) throws {
        stop()
        guard click_hid_ready() else { throw ClickError("Virtual keyboard unavailable. Install and activate the supported Karabiner virtual HID driver.") }
        router = RawInputRouter(configuration: configuration)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 6] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context else { return }
            let owner = Unmanaged<Grabber>.fromOpaque(context).takeUnretainedValue()
            guard owner.running else { return }
            do { try owner.add(device) } catch { owner.fail(error.localizedDescription) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let owner = Unmanaged<Grabber>.fromOpaque(context).takeUnretainedValue()
            owner.remove(owner.registryID(device))
        }, context)
        // The manager only enumerates. Each configured physical device is opened
        // separately with SeizeDevice, after the virtual keyboard is ready.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        running = true
        if let connected = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            do { for device in connected { try add(device) } }
            catch { stop(); throw error }
        }
    }
    private func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }
    private func add(_ device: IOHIDDevice) throws {
        let id = registryID(device)
        guard devices[id] == nil else { return }
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
        func string(_ key: String) -> String { IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "" }
        // Never feed a virtual keyboard back into itself, including other pqrs clients.
        guard !(number(kIOHIDVendorIDKey) == 0x16c0 && number(kIOHIDProductIDKey) == 0x27db),
              !string(kIOHIDProductKey).localizedCaseInsensitiveContains("virtual") else { return }
        let identity = DeviceIdentity(vendor: number(kIOHIDVendorIDKey), product: number(kIOHIDProductIDKey), serial: string(kIOHIDSerialNumberKey), location: number(kIOHIDLocationIDKey))
        guard router.configuration.profiles.contains(where: { $0.enabled && !$0.bindings.isEmpty && $0.device.matches(identity) }) else { return }
        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] ?? []).filter {
            [kIOHIDElementTypeInput_Misc, kIOHIDElementTypeInput_Button, kIOHIDElementTypeInput_Axis, kIOHIDElementTypeInput_ScanCodes].contains(IOHIDElementGetType($0))
        }
        // Do not seize compound pointer/keyboard interfaces whose input we cannot forward.
        guard !elements.isEmpty, elements.allSatisfy({
            let page = IOHIDElementGetUsagePage($0), usage = IOHIDElementGetUsage($0)
            return pages.contains(page) && (page != 1 || (0x81...0x93).contains(usage))
        }) else { throw ClickError("This keyboard interface contains unsupported HID inputs. It was not captured.") }
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess else {
            throw ClickError("Unable to capture the keyboard. Check Input Monitoring and competing keyboard tools.")
        }
        let initialValue = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
        defer { initialValue.deallocate() }
        for element in elements {
            if IOHIDDeviceGetValue(device, element, initialValue) == kIOReturnSuccess,
               IOHIDValueGetIntegerValue(initialValue.pointee.takeUnretainedValue()) != 0 {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
                throw ClickError("Release all keys before starting Keyboard Service.")
            }
        }
        guard let queue = IOHIDQueueCreate(kCFAllocatorDefault, device, 1024, 0) else {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            throw ClickError("Unable to allocate a keyboard input queue.")
        }
        for element in elements { IOHIDQueueAddElement(queue, element) }
        devices[id] = Device(handle: device, queue: queue, identity: identity)
        IOHIDQueueRegisterValueAvailableCallback(queue, { context, result, sender in
            guard let context else { return }
            let owner = Unmanaged<Grabber>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else { owner.fail("Keyboard input stopped. Mappings paused."); return }
            owner.drain()
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDQueueScheduleWithRunLoop(queue, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDQueueStart(queue)
    }
    private func drain() {
        guard running, click_hid_ready() else { fail("Virtual keyboard disconnected. Mappings paused."); return }
        var pending: [(UInt64, DeviceIdentity, IOHIDValue)] = []
        var more = false
        for (id, device) in devices {
            var count = 0
            while count < 1024, let value = IOHIDQueueCopyNextValueWithTimeout(device.queue, 0) {
                pending.append((id, device.identity, value)); count += 1
            }
            more = more || count == 1024
        }
        // Yield so a busy device cannot starve IPC, stop requests or the watchdog.
        if more { DispatchQueue.main.async { [weak self] in if self?.running == true { self?.drain() } } }
        pending.sort { IOHIDValueGetTimeStamp($0.2) < IOHIDValueGetTimeStamp($1.2) }
        for (id, identity, value) in pending {
            let element = IOHIDValueGetElement(value)
            let usage = IOHIDElementGetUsage(element), page = IOHIDElementGetUsagePage(element)
            guard usage > 0, usage <= UInt16.max else { continue }
            if page == 7 && usage <= 3 { fail("Keyboard reported a rollover error. Mappings paused."); return }
            let key = RawInputRouter.Key(page: page, usage: UInt16(usage))
            let trigger = router.input(device: id, identity: identity, key: key, down: IOHIDValueGetIntegerValue(value) != 0)
            guard publish() else { return }
            if let trigger { onTrigger(trigger) }
        }
    }
    @discardableResult private func publish() -> Bool {
        let keys = router.keys.union(macroKeys)
        // pqrs reports have 32 key slots per page. Never silently drop key-downs.
        for page in pages {
            let usages = keys.filter { $0.page == page }.map(\.usage).sorted()
            let slots = usages.filter { page != 7 || !(224...231).contains($0) }
            guard slots.count <= 32 else { fail("Too many simultaneous keys. Mappings paused."); return false }
            usages.withUnsafeBufferPointer { click_hid_report(page, $0.baseAddress, Int32($0.count)) }
        }
        return true
    }
    func shortcut(_ shortcut: Shortcut, completion: @escaping (String?) -> Void) {
        guard running, click_hid_ready(), macroKeys.isEmpty,
              KeyCatalog.keys.contains(where: { $0.id == shortcut.key }), !KeyCatalog.isModifier(shortcut.key) else {
            completion("Virtual keyboard is not ready for a shortcut."); return
        }
        macroKeys.insert(.init(usage: UInt16(shortcut.key)))
        for (enabled, usage) in [(shortcut.control, 224), (shortcut.shift, 225), (shortcut.option, 226), (shortcut.command, 227)] where enabled {
            macroKeys.insert(.init(usage: UInt16(usage)))
        }
        let token = generation
        guard publish() else { completion("Keyboard output stopped."); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, token == self.generation else { completion("Keyboard output cancelled."); return }
            self.macroKeys.removeAll()
            completion(self.publish() ? nil : "Keyboard output stopped.")
        }
    }
    private func remove(_ id: UInt64) {
        guard let device = devices.removeValue(forKey: id) else { return }
        IOHIDQueueStop(device.queue)
        IOHIDQueueUnscheduleFromRunLoop(device.queue, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device.handle, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        router.disconnect(id)
        _ = publish()
    }
    private func fail(_ message: String) { stop(); onFailure(message) }
    func stop() {
        running = false; generation = UUID()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        router.reset(); macroKeys.removeAll()
        _ = publish()
        for id in Array(devices.keys) { remove(id) }
    }
}
