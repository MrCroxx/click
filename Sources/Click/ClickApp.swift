import AppKit
import SwiftUI
import ClickCore

@main
enum ClickApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
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
        if let iconURL = Bundle.main.url(forResource: "Click", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        model = AppModel(demo: demo)
        installMenu()
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.image = SwitchSymbol.image
        item?.button?.target = self
        item?.button?.action = #selector(showWindow)
        item?.button?.setAccessibilityLabel("Click")
        NotificationCenter.default.addObserver(forName: L10n.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.installMenu() }
        }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin && !CommandLine.arguments.contains("--background") { showWindow() }
    }
    private func installMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: L10n.text("Open Click"), action: #selector(showWindow), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("Quit Click"), action: #selector(quit), keyEquivalent: "q").target = self
        let fileItem = NSMenuItem(); bar.addItem(fileItem)
        let file = NSMenu(title: L10n.text("File")); fileItem.submenu = file
        file.addItem(withTitle: L10n.text("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(); bar.addItem(editItem)
        let edit = NSMenu(title: L10n.text("Edit")); editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: L10n.text(title), action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = bar
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Click"; window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 860, height: 560); window.isReleasedWhenClosed = false
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
    @objc private func quit() { NSApp.terminate(nil) }
}
