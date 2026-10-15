import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import ClickCore

private func tr(_ key: String) -> String { L10n.text(key) }

struct ContentView: View {
    @ObservedObject var model: AppModel
    @AppStorage(L10n.preferenceKey) private var language = AppLanguage.english.rawValue
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 208)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = model.error {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                Text(tr(error)).textSelection(.enabled)
                                Spacer()
                                IconButton("Dismiss", icon: "xmark") { model.error = nil }
                            }.padding(12).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                        }
                        switch model.selection {
                        case "macros": macros
                        case "settings": settings
                        case "permissions": PermissionsView(model: model)
                        default: mappings
                        }
                    }.padding(32).frame(maxWidth: 880, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if !["Ready", "Preview"].contains(model.message) {
                    HStack { Text(tr(model.message)).foregroundStyle(.secondary).lineLimit(2); Spacer() }
                        .font(.system(size: 12)).padding(.horizontal, 32).padding(.vertical, 10)
                }
            }.background(Color(nsColor: .textBackgroundColor))
        }
        .font(.system(size: 13)).tint(.primary)
        .frame(minWidth: 860, minHeight: 560)
        .environment(\.locale, Locale(identifier: language))
        .id(language)
        .onChange(of: language) { _, _ in NotificationCenter.default.post(name: L10n.didChange, object: nil) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: SwitchSymbol.image).accessibilityLabel("Click")
                Text("Click").font(.system(size: 17, weight: .semibold))
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 27)
            navigation("devices", "Mappings", "keyboard")
            navigation("macros", "Macros", "list.bullet.rectangle")
            Divider().padding(.horizontal, 20).padding(.vertical, 18)
            if model.selection == "macros" {
                listHeading("Macros") { model.addMacro() }
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.configuration.macros) { macro in
                            item(macro.name, selected: model.selectedMacro == macro.id) { model.selectedMacro = macro.id }
                        }
                    }.padding(.horizontal, 10)
                }
            } else if model.selection == "devices" {
                HStack {
                    Text(tr("Devices")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    deviceMenu.labelStyle(.iconOnly)
                }.padding(.horizontal, 20).padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.configuration.profiles) { profile in
                            item(profile.name, selected: model.selectedProfile == profile.id) { model.selectedProfile = profile.id }
                        }
                    }.padding(.horizontal, 10)
                }
            } else { Spacer() }
            Spacer(minLength: 12)
            navigation("permissions", "Permissions", "lock.shield")
            navigation("settings", "Settings", "gearshape")
            HStack(spacing: 7) {
                Circle().fill(model.running ? Color.green.opacity(0.8) : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                Text(tr(model.demo ? "Preview" : model.running ? "Running" : "Paused")).foregroundStyle(.secondary)
                Spacer()
            }.font(.system(size: 11)).padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 18)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func navigation(_ key: String, _ title: String, _ icon: String) -> some View {
        Button {
            model.selection = key
            if model.selectedProfile == nil { model.selectedProfile = model.configuration.profiles.first?.id }
            if model.selectedMacro == nil { model.selectedMacro = model.configuration.macros.first?.id }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 20)
                Text(tr(title)).fontWeight(model.selection == key ? .medium : .regular)
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 9)
                .background(model.selection == key ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
    }
    private func item(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if selected { Circle().fill(.primary.opacity(0.5)).frame(width: 4, height: 4) }
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(selected ? .primary : .secondary)
                .background(selected ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func listHeading(_ title: String, add: @escaping () -> Void) -> some View {
        HStack { Text(tr(title)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary); Spacer(); IconButton("New Macro", icon: "plus", action: add) }
            .padding(.horizontal, 20).padding(.bottom, 10)
    }
    private var toolbar: some View {
        HStack(spacing: 16) {
            Text(tr(model.selection == "macros" ? "Macros" : model.selection == "settings" ? "Settings" : model.selection == "permissions" ? "Permissions" : "Mappings"))
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Menu {
                Button(tr("Import…")) { model.importConfiguration() }
                Button(tr("Export…")) { model.exportConfiguration() }
                Divider()
                Button(tr("Stop Macro")) { model.runner.cancel() }
                Button(tr(model.running ? "Pause" : "Resume")) { model.toggleRunning() }.disabled(model.demo)
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(tr("Options"))
        }.padding(.horizontal, 26).frame(height: 52)
    }
    private var deviceMenu: some View {
        Menu {
            if model.devices.isEmpty { Text(tr("No keyboards connected")) }
            ForEach(model.devices) { device in Button(device.name) { model.addDevice(device) } }
        } label: { Label(tr("Add Device"), systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize().help(tr("Add Device"))
    }
    private var mappings: some View {
        Group {
            if let index = model.configuration.profiles.firstIndex(where: { $0.id == model.selectedProfile }) {
                DeviceEditor(profile: $model.configuration.profiles[index], macros: model.configuration.macros,
                    connected: model.connected(model.configuration.profiles[index])) {
                        model.configuration.profiles.remove(at: index); model.selectedProfile = model.configuration.profiles.first?.id
                    }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    Text(tr("Devices")).font(.system(size: 24, weight: .semibold))
                    if model.devices.isEmpty {
                        HStack { Text(tr("No keyboards connected")).foregroundStyle(.secondary); Spacer(); Button(tr("Refresh")) { model.refresh() } }
                    }
                    ForEach(model.devices) { device in
                        HStack(spacing: 14) {
                            Image(systemName: "keyboard").font(.system(size: 20)).foregroundStyle(.secondary)
                            Text(device.name); Spacer()
                            Button { model.addDevice(device) } label: { Image(systemName: "plus") }.help(tr("Add Device"))
                        }
                        Divider()
                    }
                }
            }
        }.onAppear { if model.selectedProfile == nil { model.selectedProfile = model.configuration.profiles.first?.id } }
    }
    private var macros: some View {
        Group {
            if let index = model.configuration.macros.firstIndex(where: { $0.id == model.selectedMacro }) {
                MacroEditor(macro: $model.configuration.macros[index], demo: model.demo,
                    run: {
                        do { try model.configuration.validate(); model.runner.run(model.configuration.macros[index]) }
                        catch { model.error = error.localizedDescription }
                    }, delete: { model.deleteMacro(model.configuration.macros[index].id) })
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Text(tr("Macros")).font(.system(size: 24, weight: .semibold))
                    Text(tr("No macros")).foregroundStyle(.secondary)
                    Button(tr("New Macro")) { model.addMacro() }
                }
            }
        }.onAppear { if model.selectedMacro == nil { model.selectedMacro = model.configuration.macros.first?.id } }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(tr("Settings")).font(.system(size: 24, weight: .semibold))
            settingsSection("General") {
                settingsRow("Language") {
                    Picker(tr("Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { Text($0.name).tag($0.rawValue) }
                    }.labelsHidden().frame(width: 170)
                }
                Divider()
                settingsRow("Launch at login") {
                    if model.loginStatus == .requiresApproval {
                        Button(tr("Open Login Items")) { SMAppService.openSystemSettingsLoginItems() }.disabled(model.demo)
                    }
                    Toggle(tr("Launch at login"), isOn: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval }, set: { model.setLogin($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.demo)
                }
            }
            settingsSection("Keyboard") {
                settingsRow("Keyboard Service") {
                    if model.serviceStatus == .requiresApproval {
                        Button(tr("Open Login Items")) { SMAppService.openSystemSettingsLoginItems() }.disabled(model.demo)
                    }
                    Toggle(tr("Keyboard Service"), isOn: Binding(get: { model.serviceStatus == .enabled || model.serviceStatus == .requiresApproval }, set: { model.setService($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(model.demo)
                }
                Divider()
                settingsRow("Mapping Status") {
                    Text(tr(model.running ? "Running" : "Paused")).foregroundStyle(.secondary)
                    Button(tr(model.running ? "Pause" : "Resume")) { model.toggleRunning() }.disabled(model.demo)
                }
            }
            settingsSection("Driver") {
                DriverSettings(installer: model.driverInstaller, demo: model.demo)
            }
            settingsSection("Configuration") {
                settingsRow("Import Configuration") { Button(tr("Import…")) { model.importConfiguration() } }
                Divider()
                settingsRow("Export Configuration") { Button(tr("Export…")) { model.exportConfiguration() } }
            }
        }.frame(maxWidth: 620, alignment: .leading)
    }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr(title)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 14)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(tr(title)); Spacer(); content() }.frame(minHeight: 46)
    }

}

struct IconButton: View {
    let title: String
    let icon: String
    let destructive: Bool
    let action: () -> Void
    init(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) { self.title = title; self.icon = icon; self.destructive = destructive; self.action = action }
    var body: some View {
        Button(role: destructive ? .destructive : nil, action: action) { Image(systemName: icon).frame(width: 20, height: 20).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(destructive ? Color.red : Color.secondary).help(tr(title)).accessibilityLabel(tr(title))
    }
}

struct DeviceEditor: View {
    @Binding var profile: DeviceProfile
    let macros: [Macro]
    let connected: Bool
    let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(tr("Device name"), text: $profile.name).textFieldStyle(.plain).font(.system(size: 24, weight: .semibold))
                    Text(tr(connected ? "Connected" : "Offline")).foregroundStyle(.secondary).font(.system(size: 12))
                }
                Toggle(tr("Enabled"), isOn: $profile.enabled).toggleStyle(.switch).controlSize(.small)
            }
            VStack(spacing: 0) {
                HStack {
                    Text(tr("From")).frame(width: 160, alignment: .leading)
                    Text(tr("Action")).frame(width: 100, alignment: .leading)
                    Text(tr("To")).frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 20, height: 1)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 12)
                Divider()
                ForEach($profile.bindings) { $binding in
                    HStack(spacing: 8) {
                        KeyPicker(selection: $binding.source).frame(width: 160)
                        ValueMenu(title: tr(binding.kind == .key ? "Key" : "Macro")) {
                            Button(tr("Key")) { binding.kind = .key }
                            Button(tr("Macro")) { binding.kind = .macro; if binding.macroID == nil { binding.macroID = macros.first?.id } }
                        }.frame(width: 100)
                        if binding.kind == .key {
                            KeyPicker(selection: $binding.destinationSelection, allowsFn: true).frame(maxWidth: .infinity)
                        }
                        else {
                            ValueMenu(title: macros.first(where: { $0.id == binding.macroID })?.name ?? tr("Choose a macro")) {
                                ForEach(macros) { macro in Button(macro.name) { binding.macroID = macro.id } }
                            }.frame(maxWidth: .infinity)
                        }
                        IconButton("Remove Mapping", icon: "trash", destructive: true) { profile.bindings.removeAll { $0.id == binding.id } }
                    }.padding(.horizontal, 12).frame(height: 56)
                    Divider()
                }
                if profile.bindings.isEmpty { Text(tr("No mappings")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24) }
            }
            HStack {
                Button {
                    var binding = KeyBinding()
                    binding.source = ([57,58,59,60,61,62] + KeyCatalog.keys.map(\.id)).first { candidate in !profile.bindings.contains { $0.source == candidate } } ?? 57
                    profile.bindings.append(binding)
                } label: { Label(tr("Add Mapping"), systemImage: "plus") }
                Spacer()
                Menu { Button(tr("Remove Device"), role: .destructive, action: delete) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(tr("Options"))
            }
        }
    }
}

struct ValueMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        Menu(content: content) {
            HStack {
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 9).padding(.vertical, 7)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
    }
}

struct KeyPicker: View {
    @Binding var selection: Int
    var allowsFn = false
    var body: some View {
        ValueMenu(title: tr(KeyCatalog.name(selection))) {
            ForEach(KeyCatalog.groups(allowsFn: allowsFn)) { group in
                Menu(tr(group.id)) {
                    ForEach(group.keys) { key in
                        Button { selection = key.id } label: {
                            if selection == key.id { Label(tr(key.name), systemImage: "checkmark") }
                            else { Text(tr(key.name)) }
                        }
                    }
                }
            }
        }.accessibilityLabel(tr("Key") + ": " + tr(KeyCatalog.name(selection)))
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro
    let demo: Bool
    let run: () -> Void
    let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                TextField(tr("Macro name"), text: $macro.name).textFieldStyle(.plain).font(.system(size: 24, weight: .semibold))
                Button(action: run) { Label(tr("Run"), systemImage: "play") }.disabled(demo)
                Menu { Button(tr("Delete Macro"), role: .destructive, action: delete) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(tr("Options"))
            }
            VStack(spacing: 0) {
                ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 18) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 24).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(tr(step.kind.title)).fontWeight(.medium)
                                Spacer()
                                IconButton("Move Up", icon: "chevron.up") { macro.steps.swapAt(index, index - 1) }.disabled(index == 0)
                                IconButton("Move Down", icon: "chevron.down") { macro.steps.swapAt(index, index + 1) }.disabled(index == macro.steps.count - 1)
                                IconButton("Remove Step", icon: "trash", destructive: true) { macro.steps.removeAll { $0.id == step.id } }
                            }
                            StepEditor(step: $macro.steps[index])
                        }
                    }.padding(.vertical, 20)
                    Divider()
                }
            }
            Menu {
                ForEach(StepKind.allCases, id: \.self) { kind in Button(tr(kind.title), systemImage: kind.icon) { macro.steps.append(MacroStep(kind: kind)) } }
            } label: { Label(tr("Add Step"), systemImage: "plus") }.fixedSize()
        }
    }
}

struct StepEditor: View {
    @Binding var step: MacroStep
    var body: some View {
        switch step.kind {
        case .shortcut:
            HStack(spacing: 6) {
                Toggle("⌃", isOn: $step.shortcut.control).help("Control")
                Toggle("⌥", isOn: $step.shortcut.option).help("Option")
                Toggle("⇧", isOn: $step.shortcut.shift).help("Shift")
                Toggle("⌘", isOn: $step.shortcut.command).help("Command")
                KeyPicker(selection: $step.shortcut.key).frame(maxWidth: 200)
            }.toggleStyle(.button)
        case .application:
            HStack(spacing: 12) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: step.value) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                    Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                } else { Text(step.value.isEmpty ? tr("Application") : step.value).foregroundStyle(.secondary) }
                Spacer()
                Button(tr("Choose…")) {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { step.value = id }
                }
            }
        case .delay:
            HStack(spacing: 8) {
                TextField(tr("Duration"), value: $step.milliseconds, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
                Text(tr("ms")).foregroundStyle(.secondary)
            }
        case .text:
            TextEditor(text: $step.value).font(.body).frame(minHeight: 76).padding(6)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.primary.opacity(0.12)))
                .accessibilityLabel(tr("Text"))
        }
    }
}


private struct DriverSettings: View {
    @ObservedObject var installer: DriverInstaller
    let demo: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(tr("Virtual HID Driver"))
                Spacer()
                Text(tr(installer.packageStatus) + (installer.version.map { " · " + $0 } ?? "")).foregroundStyle(.secondary)
                if installer.version == nil {
                    Button(tr("Install…")) { installer.install() }.disabled(installer.busy || demo)
                } else {
                    Menu {
                        Button(tr("Install 8.6.0…")) { installer.install() }
                        Button(tr("Official download")) { NSWorkspace.shared.open(DriverPackage.releaseURL) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(installer.busy || demo)
                    .accessibilityLabel(tr("Driver options"))
                }
            }.frame(minHeight: 46)
            if installer.supported {
                HStack {
                    Text(tr("Driver extension")); Spacer()
                    if installer.extensionActive { Text(tr("Active")).foregroundStyle(.secondary) }
                    else { Button(tr("Activate…")) { installer.activate() }.disabled(installer.busy || demo) }
                }.frame(minHeight: 46)
                HStack {
                    Text(tr("Driver service")); Spacer()
                    if installer.serviceAvailable { Text(tr("Running")).foregroundStyle(.secondary) }
                    else if installer.serviceStatus == .requiresApproval {
                        Button(tr("Open Login Items")) { SMAppService.openSystemSettingsLoginItems() }.disabled(demo)
                    } else { Button(tr("Enable…")) { installer.enableService() }.disabled(installer.busy || demo) }
                }.frame(minHeight: 46)
            }
            if let activity = installer.activity {
                HStack {
                    if installer.busy { ProgressView().controlSize(.small) }
                    Text(tr(activity)).foregroundStyle(.secondary)
                    if installer.activity == "Downloading driver…" { Button(tr("Cancel")) { installer.cancelDownload() } }
                }.padding(.vertical, 8)
            }
            if let error = installer.error {
                HStack(alignment: .top) {
                    Text(tr(error)).foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    IconButton("Dismiss", icon: "xmark") { installer.error = nil }
                }.padding(.vertical, 8)
            }
        }
    }
}
