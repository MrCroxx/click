import AppKit
import SwiftUI
import ServiceManagement
import ClickCore

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration = Configuration()
    @Published var devices: [ConnectedDevice] = []
    @Published var running = false
    @Published var message = "准备就绪"
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
                self?.pause(); self?.error = "系统停止了宏监听，已暂停映射。请检查权限并重新启动。"
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
        var macro = Macro(name: "专注写作")
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
        message = "预览模式 · 不接管键盘"
    }
    func refreshDevices() {
        devices = hardware?.devices() ?? []
        lastDeviceIDs = devices.map(\.id)
    }
    func refresh() {
        accessibility = AXIsProcessTrusted(); inputMonitoring = CGPreflightListenEventAccess()
        loginStatus = SMAppService.mainApp.status
        let previous = lastDeviceIDs
        refreshDevices()
        if running && (!accessibility && !tap.triggers.isEmpty) { pause(); error = "辅助功能权限已撤销，映射已暂停。" }
        if running && previous != lastDeviceIDs {
            do { try hardware?.apply(active, plan: MappingPlan(configuration: active)); message = "已同步连接的设备" }
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
            if demo { active = configuration; message = "预览配置已更新"; return }
            guard !loadFailed else { throw ClickError("启动时恢复或读取失败。请先修复配置文件并重启，避免覆盖原配置。") }
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
            message = "配置已保存"; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func start() throws {
        guard !demo else { return }
        guard hardware != nil else { throw ClickError("设备服务不可用，请重启 Click。") }
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
        else { do { try start(); message = "后台服务已启动"; error = nil } catch { self.error = error.localizedDescription } }
    }
    private func pauseThrowing() throws {
        runner.cancel()
        // 先恢复 HID，再撤掉吞键监听，防止宏通道键漏出。
        try hardware?.restore()
        tap.stop(); running = false
    }
    func pause() {
        do { try pauseThrowing(); message = "已暂停 · 原始键位已恢复" }
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
            message = "已载入配置 · 保存后生效"; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func exportConfiguration() {
        do {
            let data = try configuration.encoded()
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Click.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic); message = "配置已导出"
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
        let macro = Macro(steps: [MacroStep(kind: .shortcut)])
        configuration.macros.append(macro); selectedMacro = macro.id
    }
    func deleteMacro(_ id: UUID) {
        guard !configuration.profiles.flatMap(\.bindings).contains(where: { $0.kind == .macro && $0.macroID == id }) else {
            error = "这个宏仍被设备使用，请先移除对应映射。"; return
        }
        configuration.macros.removeAll { $0.id == id }; selectedMacro = configuration.macros.first?.id
    }
}
