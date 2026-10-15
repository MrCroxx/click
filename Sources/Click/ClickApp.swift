import AppKit
import SwiftUI

@main
struct ClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var window: NSWindow?
    private var item: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = CommandLine.arguments.contains("--demo")
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.mrcroxx.click")
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other, !demo { other.activate(); NSApp.terminate(nil); return }
        model = AppModel(demo: demo)
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "Click")
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Click", action: #selector(showWindow), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "启动 / 暂停", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "停止当前宏", action: #selector(cancelMacro), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Click", action: #selector(quit), keyEquivalent: "q").target = self
        item?.menu = menu
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin && !CommandLine.arguments.contains("--background") { showWindow() }
    }
    @objc func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Click"; window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 960, height: 660); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView(model: model))
            window.delegate = self; window.center(); self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else { return .terminateNow }
        if model.shutdown() { return .terminateNow }
        showWindow(); return .terminateCancel
    }
    @objc private func toggle() { model.toggleRunning() }
    @objc private func cancelMacro() { model.runner.cancel() }
    @objc private func quit() { NSApp.terminate(nil) }
}
