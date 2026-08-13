import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let model = DesktopModel()
    private let desktopVisibility = DesktopVisibilityManager()
    private var panelController: SidetopPanelController!
    private var edgeMonitor: EdgeMonitor!
    private var settingsWindow: NSWindow?
    private var ownsDesktopVisibilityChange = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.brianqsmith.Sidetop")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = otherInstances.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        desktopVisibility.hideDesktopIcons()
        ownsDesktopVisibilityChange = true

        panelController = SidetopPanelController(model: model)
        edgeMonitor = EdgeMonitor { [weak self] screen in
            self?.panelController.show(on: screen)
        }
        configureStatusItem()
        model.startMonitoring()
        edgeMonitor.start()
        LaunchAtLoginManager.shared.applyPreferredState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUp()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanUp()
        return .terminateNow
    }

    private func cleanUp() {
        edgeMonitor?.stop()
        model.stopMonitoring()
        if ownsDesktopVisibilityChange {
            desktopVisibility.restoreDesktopIcons()
            ownsDesktopVisibilityChange = false
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Sidetop")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func togglePanel() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            panelController.toggle(on: screenUnderPointer() ?? NSScreen.main)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Sidetop", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sidetop", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showPanel() {
        if let screen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first {
            panelController.show(on: screen)
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Sidetop Settings"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
