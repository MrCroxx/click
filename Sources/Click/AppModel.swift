import AppKit
import SwiftUI
import ServiceManagement
import ClickCore

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration = Configuration()
    @Published var devices: [ConnectedDevice] = []
    @Published var running = false
    @Published var message = "Ready"
    @Published var error: String?
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var accessibility = AXIsProcessTrusted()
    @Published var inputMonitoring = CGPreflightListenEventAccess()
    @Published var selection = "devices"
    @Published var selectedProfile: UUID?
    @Published var selectedMacro: UUID?
    let demo: Bool
    private let store: ConfigurationStore
    private var hardware: Hardware?
    private let tap = MacroTap()
    let runner = MacroRunner()
    private var timer: Timer?
    private var active = Configuration()
    private var lastDeviceIDs: [UInt64] = []
    private var loadFailed = false
    var dirty: Bool { configuration != active }
    init(demo: Bool = false) {
        self.demo = demo
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Click")
        store = ConfigurationStore(url: directory.appendingPathComponent("config.json"))
        runner.onStatus = { [weak self] in self?.message = $0 }
        tap.onTrigger = { [weak self] id in
            DispatchQueue.main.async {
                guard let self, self.running, let macro = self.active.macros.first(where: { $0.id == id }) else { return }
                self.runner.run(macro)
            }
        }
        tap.onFailure = { [weak self] in
            DispatchQueue.main.async {
                self?.pause(); self?.error = "The macro listener stopped. Mappings are paused. Check permissions and resume."
            }
        }
        if demo { seedDemo(); return }
        do {
            hardware = try Hardware(directory: directory)
            try hardware?.restore()
            configuration = try store.load(); active = configuration
            refreshDevices()
        } catch { self.error = error.localizedDescription; loadFailed = true }
        if !loadFailed && configuration.profiles.contains(where: \.enabled) {
            do { try start() } catch { self.error = error.localizedDescription }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.runner.cancel() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                do { try self.hardware?.apply(self.active, plan: MappingPlan(configuration: self.active)) }
                catch { self.pause(); self.error = error.localizedDescription }
            }
        }
    }
    private func seedDemo() {
        var macro = Macro(name: "New Note")
        var app = MacroStep(kind: .application); app.value = "com.apple.Notes"
        var delay = MacroStep(kind: .delay); delay.milliseconds = 300
        var shortcut = MacroStep(kind: .shortcut); shortcut.shortcut = Shortcut(key: 17, command: true)
        macro.steps = [app, delay, shortcut]
        configuration.macros = [macro]
        var profile = DeviceProfile(name: "Studio Keyboard", device: .init(vendor: 0, product: 0, location: 0))
        var escape = KeyBinding(); escape.source = 57; escape.destination = 41
        var focus = KeyBinding(); focus.source = 62; focus.kind = .macro; focus.macroID = macro.id
        profile.bindings = [escape, focus]; profile.enabled = true
        configuration.profiles = [profile]; active = configuration
        selectedProfile = profile.id; selectedMacro = macro.id
        message = "Preview"
    }
    func refreshDevices() {
        let services = hardware?.devices() ?? []
        lastDeviceIDs = services.map(\.id)
        devices = services.reduce(into: []) { result, device in
            if !result.contains(where: { $0.identity.matches(device.identity) && device.identity.matches($0.identity) }) {
                result.append(device)
            }
        }
    }
    func refresh() {
        accessibility = AXIsProcessTrusted(); inputMonitoring = CGPreflightListenEventAccess()
        loginStatus = SMAppService.mainApp.status
        let previous = lastDeviceIDs
        refreshDevices()
        if running && (!accessibility && !tap.triggers.isEmpty) { pause(); error = "Accessibility permission was revoked. Mappings are paused." }
        if running && previous != lastDeviceIDs {
            do { try hardware?.apply(active, plan: MappingPlan(configuration: active)); message = "Connected devices updated" }
            catch { pause(); self.error = error.localizedDescription }
        }
    }
    func addDevice(_ device: ConnectedDevice) {
        if let profile = configuration.profiles.first(where: { $0.device.matches(device.identity) }) { selectedProfile = profile.id; return }
        let profile = DeviceProfile(name: device.name, device: device.identity)
        configuration.profiles.append(profile); selectedProfile = profile.id
    }
    func connected(_ profile: DeviceProfile) -> Bool { demo || devices.contains { profile.device.matches($0.identity) } }
    func save() {
        do {
            try configuration.validate()
            if demo { active = configuration; message = "Preview updated"; return }
            guard !loadFailed else { throw ClickError("Startup recovery failed. Repair the configuration and restart Click before saving.") }
            try pauseThrowing()
            let previous = active
            active = configuration
            do {
                try start()
                try store.save(configuration)
            } catch {
                try? pauseThrowing(); active = previous
                throw error
            }
            message = "Saved"; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func start() throws {
        guard !demo else { return }
        guard hardware != nil else { throw ClickError("Device service unavailable. Restart Click.") }
        try active.validate()
        let plan = try MappingPlan(configuration: active)
        if !plan.triggers.isEmpty {
            try tap.start()
            tap.triggers = Dictionary(uniqueKeysWithValues: plan.triggers.compactMap { usage, id in KeyCatalog.virtual(usage).map { ($0, id) } })
        }
        do { try hardware?.apply(active, plan: plan) }
        catch { tap.stop(); throw error }
        running = true
    }
    func toggleRunning() {
        if running { pause() }
        else { do { try start(); message = "Service started"; error = nil } catch { self.error = error.localizedDescription } }
    }
    private func pauseThrowing() throws {
        runner.cancel()
        // 先恢复 HID，再撤掉吞键监听，防止宏通道键漏出。
        try hardware?.restore()
        tap.stop(); running = false
    }
    func pause() {
        do { try pauseThrowing(); message = "Paused. Original mappings restored." }
        catch { self.error = error.localizedDescription }
    }
    func shutdown() -> Bool {
        do { try pauseThrowing(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try Configuration.decode(Data(contentsOf: url))
            configuration = imported; selectedProfile = imported.profiles.first?.id; selectedMacro = imported.macros.first?.id
            message = "Configuration imported. Save to apply."; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func exportConfiguration() {
        do {
            let data = try configuration.encoded()
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Click.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic); message = "Configuration exported"
        } catch { self.error = error.localizedDescription }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func requestInputMonitoring() { _ = CGRequestListenEventAccess() }
    func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
    func addMacro() {
        let macro = Macro(name: L10n.text("New Macro"), steps: [MacroStep(kind: .shortcut)])
        configuration.macros.append(macro); selectedMacro = macro.id
    }
    func deleteMacro(_ id: UUID) {
        guard !configuration.profiles.flatMap(\.bindings).contains(where: { $0.kind == .macro && $0.macroID == id }) else {
            error = "This macro is assigned to a device. Remove its mappings first."; return
        }
        configuration.macros.removeAll { $0.id == id }; selectedMacro = configuration.macros.first?.id
    }
}
