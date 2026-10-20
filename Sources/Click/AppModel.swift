import AppKit
import SwiftUI
import ServiceManagement
import ClickCore
import ClickIPC
import IOKit.hidsystem

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration = Configuration() {
        didSet { if readyForEdits { updater.submit(configuration) } }
    }
    @Published var devices: [ConnectedDevice] = []
    @Published var running = false
    @Published var message = "Ready"
    @Published var error: String?
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var accessibility = AXIsProcessTrusted()
    @Published var inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @Published var inputMonitoringRequested = false
    @Published var selection = "devices"
    @Published var selectedProfile: UUID?
    @Published var selectedMacro: UUID?
    let demo: Bool
    private let store: ConfigurationStore
    private var hardware: Hardware?
    private let daemon = DaemonClient()
    let driverInstaller = DriverInstaller()
    lazy var runner = MacroRunner(shortcutOutput: { [weak self] shortcut in
        guard let self else { throw CancellationError() }; try await self.daemon.shortcut(shortcut)
    })
    @Published var serviceStatus = SMAppService.daemon(plistName: ClickService.plist).status
    @Published var applying = false
    private var operation = UUID()
    private var timer: Timer?
    private var sleepRecovery = SleepRecovery()
    private var inputRecoveryTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var recoveringFromSleep = false
    private var active = Configuration()
    private var loadFailed = false
    private var readyForEdits = false
    private lazy var updater: ConfigurationUpdater = {
        let updater = ConfigurationUpdater(persist: { [weak self] draft in
            guard let self else { return }
            guard !self.loadFailed else { throw ClickError("Startup recovery failed. Repair the configuration and restart Click before saving.") }
            if !self.demo { try self.store.save(draft) }
        }, apply: { [weak self] draft in
            guard let self else { return }
            self.active = draft
            try await self.start()
        }, stop: { [weak self] in
            guard let self, !self.demo else { return }
            try self.pauseThrowing()
        })
        updater.onState = { [weak self] state in
            guard let self else { return }
            switch state {
            case .saved: self.applying = true; self.error = nil; self.message = "Applying changes…"
            case .applying: self.applying = true
            case .applied: self.applying = false; self.error = nil; self.message = self.demo ? "Preview" : "Ready"
            case .saveFailed(let detail): self.applying = false; self.message = "Changes not saved"; self.error = detail
            case .applyFailed(let detail): self.applying = false; self.message = "Saved. Mappings paused."; self.error = detail
            }
        }
        return updater
    }()
    init(demo: Bool = false) {
        self.demo = demo
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Click")
        store = ConfigurationStore(url: directory.appendingPathComponent("config.json"))
        runner.onStatus = { [weak self] in self?.message = $0 }
        daemon.onTrigger = { [weak self] id in
            DispatchQueue.main.async {
                guard let self, self.running, let macro = self.active.macros.first(where: { $0.id == id }) else { return }
                self.runner.run(macro)
            }
        }
        daemon.onFailure = { [weak self] message in
            guard let self else { return }
            self.pause()
            if KeyboardStartRecovery.canRecover(message) {
                self.message = "Waiting for keys to be released…"
                self.applying = true
                let token = self.operation
                self.inputRecoveryTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                    guard let self, self.operation == token else { return }
                    self.inputRecoveryTask = nil
                    self.updater.submit(self.configuration)
                }
            }
            else { self.error = message }
        }
        driverInstaller.prepareChange = { [weak self] in self?.updater.cancel(); try self?.pauseThrowing() }
        if demo { seedDemo(); readyForEdits = true; return }
        driverInstaller.refresh()
        do {
            hardware = try Hardware(directory: directory)
            try hardware?.restore()
            configuration = try store.load(); active = configuration
            refreshDevices()
        } catch { self.error = error.localizedDescription; loadFailed = true }
        readyForEdits = true
        if !loadFailed && configuration.profiles.contains(where: \.enabled) { updater.submit(configuration) }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForSleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterSleep() }
        }
    }
    private func prepareForSleep() {
        var recovery = sleepRecovery
        recovery.sleep(active: running || applying || recoveringFromSleep)
        pause()
        sleepRecovery = recovery
        daemon.disconnect()
    }
    private func resumeAfterSleep() {
        guard sleepRecovery.shouldResume, wakeTask == nil else { return }
        wakeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            guard let self else { return }
            self.wakeTask = nil
            guard self.sleepRecovery.wake() else { return }
            self.recoveringFromSleep = true
            self.refreshDevices()
            self.updater.submit(self.configuration)
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
        devices = services.reduce(into: []) { result, device in
            if !result.contains(where: { $0.identity.matches(device.identity) && device.identity.matches($0.identity) }) {
                result.append(device)
            }
        }
    }
    func refresh() {
        accessibility = AXIsProcessTrusted(); inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        loginStatus = SMAppService.mainApp.status
        driverInstaller.refresh()
        refreshDevices()
        serviceStatus = SMAppService.daemon(plistName: ClickService.plist).status
        if running && !accessibility && !active.macros.isEmpty { runner.cancel() }
    }
    func addDevice(_ device: ConnectedDevice) {
        if let profile = configuration.profiles.first(where: { $0.device.matches(device.identity) }) { selectedProfile = profile.id; return }
        let profile = DeviceProfile(name: device.name, device: device.identity)
        configuration.profiles.append(profile); selectedProfile = profile.id
    }
    func connected(_ profile: DeviceProfile) -> Bool { demo || devices.contains { profile.device.matches($0.identity) } }
    func start() async throws {
        guard !demo else { return }
        guard !loadFailed else { throw ClickError("Startup recovery failed. Repair the configuration and restart Click before saving.") }
        guard hardware != nil else { throw ClickError("Device service unavailable. Restart Click.") }
        try active.validate()
        guard active.profiles.contains(where: { $0.enabled && !$0.bindings.isEmpty }) else {
            daemon.stop(); running = false; return
        }
        guard SMAppService.daemon(plistName: ClickService.plist).status == .enabled else {
            throw ClickError("Enable Keyboard Service in Settings and approve it in Login Items.")
        }
        let token = UUID(); operation = token
        defer { recoveringFromSleep = false }
        try await KeyboardStartRecovery.run(recoveringFromSleep: recoveringFromSleep, isCurrent: { self.operation == token }, waiting: {
            self.running = false
            self.error = nil
            self.message = "Waiting for keys to be released…"
        }, start: {
            guard SMAppService.daemon(plistName: ClickService.plist).status == .enabled else {
                throw ClickError("Enable Keyboard Service in Settings and approve it in Login Items.")
            }
            try await self.daemon.start(self.active)
        })
        guard operation == token else { throw CancellationError() }
        running = true
    }
    func toggleRunning() {
        if running || applying { pause() }
        else { updater.submit(configuration) }
    }
    func setService(_ enabled: Bool) {
        guard !demo else { return }
        do {
            let service = SMAppService.daemon(plistName: ClickService.plist)
            if enabled { try service.register() }
            else { pause(); try service.unregister() }
            serviceStatus = service.status; error = nil
            if enabled && serviceStatus == .enabled { updater.submit(configuration) }
            if serviceStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = error.localizedDescription }
    }
    private func pauseThrowing() throws {
        inputRecoveryTask?.cancel(); inputRecoveryTask = nil
        runner.cancel()
        operation = UUID()
        daemon.stop()
        running = false
        try hardware?.restore()
    }
    func pause() {
        sleepRecovery.cancel()
        wakeTask?.cancel(); wakeTask = nil
        recoveringFromSleep = false
        updater.cancel()
        applying = false
        do { try pauseThrowing(); message = "Paused. Original mappings restored." }
        catch { self.error = error.localizedDescription }
    }
    func shutdown() -> Bool {
        sleepRecovery.cancel()
        wakeTask?.cancel(); wakeTask = nil
        updater.cancel()
        do { try pauseThrowing(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try Configuration.decode(Data(contentsOf: url))
            configuration = imported; selectedProfile = imported.profiles.first?.id; selectedMacro = imported.macros.first?.id
            // Configuration assignment above persists and schedules application.
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
    func requestInputMonitoring() {
        guard !demo else { return }
        inputMonitoringRequested = true
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    func revealApplication() {
        guard !demo else { return }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
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
