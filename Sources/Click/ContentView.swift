import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers
import ClickCore

private let accent = Color(red: 0.30, green: 0.36, blue: 0.90)
private let surface = Color(nsColor: .controlBackgroundColor)

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Label(model.demo ? "预览模式" : (model.running ? "后台运行中" : "已暂停"), systemImage: "circle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(model.running ? .green : .secondary)
                    Spacer()
                    if model.dirty { Text("未保存").foregroundStyle(.secondary) }
                    Button("保存并应用") { model.save() }.buttonStyle(.borderedProminent).tint(accent).keyboardShortcut("s")
                }.padding(.horizontal, 32).padding(.vertical, 18)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let error = model.error {
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                                Text(error).textSelection(.enabled)
                                Spacer()
                                Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }.padding(16).background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                        }
                        switch model.selection {
                        case "macros": macros
                        case "settings": settings
                        default: devices
                        }
                    }.padding(32).frame(maxWidth: 1050, alignment: .leading)
                }
                Divider()
                HStack {
                    Text(model.message).lineLimit(2).foregroundStyle(.secondary)
                    Spacer()
                    Button("停止宏") { model.runner.cancel() }.buttonStyle(.plain)
                }.font(.system(size: 13)).padding(.horizontal, 32).padding(.vertical, 12)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.tint(accent).font(.system(size: 14)).frame(minWidth: 960, minHeight: 660)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 12) {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 27, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(accent.gradient, in: RoundedRectangle(cornerRadius: 14))
                Text("Click").font(.system(size: 28, weight: .bold, design: .rounded))
            }.padding(.top, 38)
            VStack(spacing: 8) {
                navigation("devices", "设备与按键", "keyboard")
                navigation("macros", "宏编排", "square.stack.3d.up")
                navigation("settings", "设置", "slider.horizontal.3")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text("你的按键，\n你的工作方式。").font(.system(size: 20, weight: .semibold)).lineSpacing(5)
                HStack {
                    Button { model.importConfiguration() } label: { Label("载入", systemImage: "square.and.arrow.down") }
                    Button { model.exportConfiguration() } label: { Label("导出", systemImage: "square.and.arrow.up") }
                }.buttonStyle(.borderless)
            }.padding(.bottom, 25)
        }.padding(.horizontal, 20).background(.ultraThinMaterial)
    }
    private func navigation(_ key: String, _ title: String, _ icon: String) -> some View {
        Button { model.selection = key } label: {
            HStack(spacing: 12) { Image(systemName: icon).frame(width: 23); Text(title); Spacer() }
                .fontWeight(model.selection == key ? .semibold : .medium).padding(13)
                .foregroundStyle(model.selection == key ? accent : .primary)
                .background(model.selection == key ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }
    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 34, weight: .bold))
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }
    private var devices: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("每一把键盘，都顺手。", "为不同设备安排独立的按键和动作。")
            HStack(spacing: 14) {
                metric("keyboard", "\(model.demo ? 1 : model.devices.count)", "已连接")
                metric("arrow.triangle.branch", "\(model.configuration.profiles.reduce(0) { $0 + $1.bindings.count })", "按键映射")
                metric("square.stack.3d.up", "\(model.configuration.macros.count)", "可用宏")
            }
            HStack {
                Text("设备").font(.title3.bold())
                Spacer()
                Menu {
                    if model.devices.isEmpty { Text("没有检测到键盘") }
                    ForEach(model.devices) { device in Button(device.name) { model.addDevice(device) } }
                } label: { Label("添加设备", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            if model.configuration.profiles.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 46)).foregroundStyle(accent)
                    Text("从一把键盘开始").font(.title2.bold())
                    Text("选择已连接的设备，添加第一条映射。").foregroundStyle(.secondary)
                    ForEach(model.devices) { device in
                        Button { model.addDevice(device) } label: { Label(device.name, systemImage: "plus.circle.fill") }.buttonStyle(.bordered)
                    }
                    if model.devices.isEmpty { Text("连接 USB 或蓝牙键盘后点刷新。").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity).padding(36).card()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.configuration.profiles) { profile in
                            Button { model.selectedProfile = profile.id } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "keyboard").font(.title2)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(profile.name).fontWeight(.semibold).lineLimit(1)
                                        Text(model.connected(profile) ? "已连接" : "离线").foregroundStyle(.secondary)
                                    }
                                }.padding(16).frame(minWidth: 190, alignment: .leading)
                                    .background(model.selectedProfile == profile.id ? accent.opacity(0.09) : surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.selectedProfile == profile.id ? accent.opacity(0.5) : .clear))
                            }.buttonStyle(.plain)
                        }
                    }.padding(2)
                }
                if let index = model.configuration.profiles.firstIndex(where: { $0.id == model.selectedProfile }) {
                    DeviceEditor(profile: $model.configuration.profiles[index], macros: model.configuration.macros) {
                        model.configuration.profiles.remove(at: index); model.selectedProfile = model.configuration.profiles.first?.id
                    }
                } else {
                    Text("选择设备开始编辑。").foregroundStyle(.secondary)
                }
            }
        }.onAppear { if model.selectedProfile == nil { model.selectedProfile = model.configuration.profiles.first?.id } }
    }
    private func metric(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 23)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 3) { Text(value).font(.system(size: 25, weight: .semibold)); Text(label).foregroundStyle(.secondary) }
            Spacer()
        }.padding(20).card()
    }
    private var macros: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                heading("一个按键，一段流程。", "按顺序组合动作，交给 Click 执行。")
                Spacer()
                Button { model.addMacro() } label: { Label("新建宏", systemImage: "plus") }.buttonStyle(.bordered)
            }
            if model.configuration.macros.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 44)).foregroundStyle(accent)
                    Text("把重复的事，连成一步。").font(.title2.bold())
                    Text("切换应用 → 等待 → 发送快捷键").foregroundStyle(.secondary)
                    Button("创建第一个宏") { model.addMacro() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(40).card()
            } else {
                Picker("宏", selection: $model.selectedMacro) {
                    ForEach(model.configuration.macros) { macro in Text(macro.name).tag(Optional(macro.id)) }
                }.pickerStyle(.menu).frame(maxWidth: 350)
                if let index = model.configuration.macros.firstIndex(where: { $0.id == model.selectedMacro }) {
                    MacroEditor(macro: $model.configuration.macros[index], demo: model.demo,
                        run: {
                            do { try model.configuration.validate(); model.runner.run(model.configuration.macros[index]) }
                            catch { model.error = error.localizedDescription }
                        }, delete: { model.deleteMacro(model.configuration.macros[index].id) })
                }
            }
        }.onAppear { if model.selectedMacro == nil { model.selectedMacro = model.configuration.macros.first?.id } }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("安静运行，随时就绪。", "关闭窗口后，Click 会留在菜单栏。")
            VStack(spacing: 22) {
                HStack {
                    Label("后台服务", systemImage: "waveform.path").font(.headline)
                    Spacer()
                    Button(model.running ? "暂停" : "启动") { model.toggleRunning() }.disabled(model.demo)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 6) { Text("登录时启动").font(.headline); Text("登录 Mac 后自动在后台运行。").foregroundStyle(.secondary) }
                    Spacer()
                    Toggle("登录时启动", isOn: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval }, set: { model.setLogin($0) }))
                        .labelsHidden().toggleStyle(.switch).disabled(model.demo)
                }
                if model.loginStatus == .requiresApproval {
                    Button("在系统设置中允许登录项") { SMAppService.openSystemSettingsLoginItems() }
                }
            }.padding(24).card()
            VStack(alignment: .leading, spacing: 20) {
                Text("系统权限").font(.title3.bold())
                permission("辅助功能", "拦截宏触发键、发送快捷键和文本。", model.accessibility) { model.requestAccessibility(); model.openSettings("Privacy_Accessibility") }
                Divider()
                permission("输入监控", "允许系统应用键盘映射。", model.inputMonitoring) { model.requestInputMonitoring(); model.openSettings("Privacy_ListenEvent") }
            }.padding(24).card()
            VStack(alignment: .leading, spacing: 12) {
                Text("配置文件").font(.title3.bold())
                Text("JSON 文件包含设备、映射和宏；载入后可检查，保存后生效。").foregroundStyle(.secondary)
                HStack { Button("载入配置…") { model.importConfiguration() }; Button("导出配置…") { model.exportConfiguration() } }
            }.padding(24).card()
            Text("宏通道使用 F13–F20，最多 8 个触发键。启用后，对应功能键在所有键盘上都会触发宏。Fn、媒体键和鼠标按钮暂不支持。").foregroundStyle(.secondary)
        }
    }
    private func permission(_ title: String, _ description: String, _ enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle.dashed").font(.title2).foregroundStyle(enabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 5) { Text(title).fontWeight(.semibold); Text(description).foregroundStyle(.secondary) }
            Spacer()
            if !enabled { Button("授权", action: action).disabled(model.demo) }
        }
    }
}

private extension View {
    func card() -> some View { background(surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.04))) }
}

struct DeviceEditor: View {
    @Binding var profile: DeviceProfile
    let macros: [Macro]
    let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                TextField("设备名称", text: $profile.name).font(.title2.bold()).textFieldStyle(.plain)
                Toggle("启用映射", isOn: $profile.enabled).toggleStyle(.switch)
            }
            if profile.bindings.isEmpty {
                Text("还没有映射。添加按键，选择它的新动作。").foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach($profile.bindings) { $binding in
                HStack(spacing: 14) {
                    KeyPicker(selection: $binding.source).frame(width: 160)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Picker("类型", selection: $binding.kind) { Text("按键").tag(BindingKind.key); Text("宏").tag(BindingKind.macro) }
                        .labelsHidden().frame(width: 85)
                        .onChange(of: binding.kind) { _, kind in if kind == .macro && binding.macroID == nil { binding.macroID = macros.first?.id } }
                    if binding.kind == .key {
                        KeyPicker(selection: $binding.destination).frame(maxWidth: .infinity)
                    } else {
                        Picker("宏", selection: $binding.macroID) {
                            Text("选择宏").tag(Optional<UUID>.none)
                            ForEach(macros) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden().frame(maxWidth: .infinity)
                    }
                    Button { profile.bindings.removeAll { $0.id == binding.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button {
                    var binding = KeyBinding()
                    binding.source = ([57,58,59,60,61,62] + KeyCatalog.keys.map(\.id)).first { candidate in !profile.bindings.contains { $0.source == candidate } } ?? 57
                    profile.bindings.append(binding)
                } label: { Label("添加映射", systemImage: "plus") }.buttonStyle(.borderless)
                Spacer()
                Button("移除设备", role: .destructive, action: delete).buttonStyle(.borderless)
            }
        }.padding(24).card()
    }
}

struct KeyPicker: View {
    @Binding var selection: Int
    var body: some View {
        Picker("按键", selection: $selection) {
            ForEach(KeyCatalog.keys) { key in Text(key.name).tag(key.id) }
        }.labelsHidden().pickerStyle(.menu)
    }
}

struct MacroEditor: View {
    @Binding var macro: Macro
    let demo: Bool
    let run: () -> Void
    let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TextField("宏名称", text: $macro.name).font(.title2.bold()).textFieldStyle(.plain)
                Button(action: run) { Label("运行", systemImage: "play.fill") }.disabled(demo)
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 16) {
                    Text(String(format: "%02d", index + 1)).font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(accent).frame(width: 32).padding(.top, 16)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Image(systemName: step.kind.icon).foregroundStyle(accent)
                            Text(step.kind.title).font(.headline)
                            Spacer()
                            Button { macro.steps.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                            Button { macro.steps.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }.disabled(index == macro.steps.count - 1)
                            Button { macro.steps.removeAll { $0.id == step.id } } label: { Image(systemName: "xmark") }
                        }.buttonStyle(.borderless)
                        StepEditor(step: $macro.steps[index])
                    }.padding(20).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            Menu {
                ForEach(StepKind.allCases, id: \.self) { kind in Button(kind.title, systemImage: kind.icon) { macro.steps.append(MacroStep(kind: kind)) } }
            } label: { Label("添加步骤", systemImage: "plus.circle") }.menuStyle(.borderlessButton).fixedSize().padding(.leading, 48)
        }.padding(24).card()
    }
}
struct StepEditor: View {
    @Binding var step: MacroStep
    var body: some View {
        switch step.kind {
        case .shortcut:
            HStack(spacing: 10) {
                Toggle("⌃", isOn: $step.shortcut.control)
                Toggle("⌥", isOn: $step.shortcut.option)
                Toggle("⇧", isOn: $step.shortcut.shift)
                Toggle("⌘", isOn: $step.shortcut.command)
                KeyPicker(selection: $step.shortcut.key)
            }.toggleStyle(.button)
        case .application:
            HStack {
                TextField("com.apple.Notes", text: $step.value).textFieldStyle(.roundedBorder)
                Button("选择应用…") {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { step.value = id }
                }
            }
        case .delay:
            HStack { TextField("时间", value: $step.milliseconds, format: .number).textFieldStyle(.roundedBorder).frame(width: 110); Text("毫秒").foregroundStyle(.secondary) }
        case .text:
            TextEditor(text: $step.value).font(.body).frame(minHeight: 80).padding(6).background(surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
