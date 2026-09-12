import AppKit
import KeyboardShortcuts
import SwiftUI
import UserNotifications

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", initial: .init(.backtick, modifiers: [.option]))
}

@main
enum OpenPad {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private var settingsWindow: NSWindow?
    private let model = ChatModel()

    func applicationDidFinishLaunching(_: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "OpenPad")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Panel", action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Keyboard Shortcut…", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenPad", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        panel = PanelController(model: model)
        model.onEscape = { [weak self] in self?.panel.hide() }
        model.onIdleWhileHidden = { [weak self] preview in self?.notifyFinished(preview) }

        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.toggle() }
    }

    @objc private func toggle() { panel.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = Form {
                KeyboardShortcuts.Recorder("Toggle panel:", name: .togglePanel)
            }
            .padding()
            .frame(width: 320)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "OpenPad Settings"
            w.styleMask = [.titled, .closable]
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: notifications + URL scheme

    private func notifyFinished(_ preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "OpenPad"
        content.body = preview
        if let dir = model.directory, let sid = model.sessionID {
            content.userInfo = ["directory": dir, "sessionID": sid]
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // Deep link: opencodepad://session/<dir-as-path>?id=<sid> — for now any
    // notification click just shows the panel; session routing lands with the
    // sessions view.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void
    ) {
        Task { @MainActor in self.panel.show() }
        completion()
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "opencodepad" {
            panel.show()
        }
    }

    // MARK: panel visibility tracking

    func applicationDidResignActive(_: Notification) {
        if let visible = panel?.isVisible { model.panelVisible = visible }
    }
}
