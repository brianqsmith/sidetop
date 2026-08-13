import AppKit
import SwiftUI

final class SidetopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SidetopPanelController: NSObject, NSWindowDelegate {
    private let model: DesktopModel
    private let panel: SidetopPanel
    private let quickLook = QuickLookController()
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private var isReanchoring = false

    var isVisible: Bool { panel.isVisible }

    init(model: DesktopModel) {
        self.model = model
        let savedWidth = UserDefaults.standard.double(forKey: "panelWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "panelHeight")
        let size = NSSize(width: savedWidth > 0 ? savedWidth : 430,
                          height: savedHeight > 0 ? savedHeight : 760)
        panel = SidetopPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .resizable, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        super.init()
        configurePanel()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = NSSize(width: 320, height: 360)
        panel.contentView = NSHostingView(rootView: SidetopView(model: model,
                                                               close: { [weak self] in self?.hide() },
                                                               settings: { [weak self] in self?.openSettingsFromPanel() }))
        panel.setFrameAutosaveName("SidetopPanelSize")
    }

    func toggle(on screen: NSScreen?) {
        if panel.isVisible { hide() } else if let screen { show(on: screen) }
    }

    func show(on screen: NSScreen) {
        model.refresh()
        let visible = screen.visibleFrame
        var size = panel.frame.size
        size.width = min(max(size.width, panel.minSize.width), visible.width)
        size.height = min(max(size.height, panel.minSize.height), visible.height)
        let origin = NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }

    func hide() {
        quickLook.close()
        panel.orderOut(nil)
        removeEventMonitors()
    }

    func windowDidResize(_ notification: Notification) {
        UserDefaults.standard.set(panel.frame.width, forKey: "panelWidth")
        UserDefaults.standard.set(panel.frame.height, forKey: "panelHeight")
        guard !isReanchoring, let screen = panel.screen else { return }
        isReanchoring = true
        var frame = panel.frame
        frame.origin = NSPoint(x: screen.visibleFrame.maxX - frame.width,
                               y: screen.visibleFrame.maxY - frame.height)
        panel.setFrame(frame, display: true)
        isReanchoring = false
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown { return self.handleKey(event) ? nil : event }
            if event.window !== self.panel { self.hide() }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor); self.globalClickMonitor = nil }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor); self.localEventMonitor = nil }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let url = model.selectedURL else {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" { model.paste(); return true }
            return false
        }
        if event.keyCode == 49 { quickLook.toggle(url: url, sourceWindow: panel); return true }
        if event.keyCode == 51 || event.keyCode == 117 { model.delete(url); return true }
        if event.keyCode == 36 { model.open(url); return true }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "c": model.copy(url); return true
            case "v": model.paste(); return true
            case "d": model.duplicate(url); return true
            default: break
            }
        }
        return false
    }

    private func openSettingsFromPanel() {
        hide()
        (NSApp.delegate as? AppDelegate)?.showSettings()
    }
}
