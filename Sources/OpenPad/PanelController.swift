import AppKit
import SwiftUI

/// Spotlight-style floating panel: borderless, centered top-third, closes on
/// outside click / Esc via the view.
@MainActor
final class PanelController {
    private var panel: NSPanel?
    private let model: ChatModel

    init(model: ChatModel) {
        self.model = model
        let view = NSHostingView(rootView: ChatView(model: model))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak model, weak panel] _ in
                MainActor.assumeIsolated {
                    model?.panelVisible = panel?.isKeyWindow ?? false
                }
            }
        }
    }

    func toggle() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let panel else { return }
        model.start() // connect to the home-dir server on first summon
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w = panel.frame.width
            panel.setFrameOrigin(NSPoint(
                x: f.midX - w / 2,
                y: f.maxY - f.height / 3 - panel.frame.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
    var isVisible: Bool { panel?.isVisible ?? false }
}
