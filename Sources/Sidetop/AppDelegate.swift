import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var model: DesktopModel!
    private let desktopVisibility = DesktopVisibilityManager()
    private var panelController: SidetopPanelController!
    private var edgeMonitor: EdgeMonitor!
    private var ownsDesktopVisibilityChange = false
    private var sidetopIsOn = true
    private let hideDesktopIconsKey = "hideDesktopIcons"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.brianqsmith.Sidetop")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = otherInstances.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            "closeWindowMode": "auto",
            "sidetopTheme": "light",
            "menuIconMode": "always",
            "animationSpeed": "slow"
        ])
        if UserDefaults.standard.object(forKey: "closeModeDefaultV2") == nil {
            UserDefaults.standard.set("auto", forKey: "closeWindowMode")
            UserDefaults.standard.set(true, forKey: "closeModeDefaultV2")
        } else if UserDefaults.standard.string(forKey: "closeWindowMode") == "onClick" {
            UserDefaults.standard.set("focus", forKey: "closeWindowMode")
        }
        if UserDefaults.standard.object(forKey: "desktopHidingDefaultV4") == nil {
            UserDefaults.standard.set(true, forKey: hideDesktopIconsKey)
            UserDefaults.standard.set(true, forKey: "desktopHidingDefaultV4")
        }
        if !UserDefaults.standard.bool(forKey: hideDesktopIconsKey) {
            desktopVisibility.recoverInterruptedSessionIfNeeded()
        }

        let defaultFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let savedFolder = UserDefaults.standard.string(forKey: "displayFolderPath").map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        var isDirectory: ObjCBool = false
        let displayFolder = savedFolder.flatMap { folder -> URL? in
            FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue
                ? folder : nil
        } ?? defaultFolder
        model = DesktopModel(desktopURL: displayFolder)
        panelController = SidetopPanelController(model: model) { [weak self] hidden in
            self?.setDesktopIconsHidden(hidden)
        }
        edgeMonitor = EdgeMonitor { [weak self] screen in
            self?.panelController.show(on: screen)
        }
        configureStatusItem()
        model.startMonitoring()
        edgeMonitor.start()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showPanel()
            if UserDefaults.standard.bool(forKey: self.hideDesktopIconsKey) {
                self.setDesktopIconsHidden(true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUp()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanUp()
        return .terminateNow
    }

    private func cleanUp() {
        edgeMonitor?.stop()
        model?.stopMonitoring()
        if ownsDesktopVisibilityChange {
            desktopVisibility.forceDesktopIconsVisible()
            ownsDesktopVisibilityChange = false
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "rectangle.righthalf.inset.filled", accessibilityDescription: "Sidetop")
            ?? NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Sidetop")
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = "Show or hide Sidetop"
        button.target = self
        button.action = #selector(showStatusMenu)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Sidetop", action: #selector(openSidetop), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Sidetop", action: #selector(quitSidetop), keyEquivalent: "q")
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

    @objc private func openSidetop() {
        if !sidetopIsOn {
            sidetopIsOn = true
            model.startMonitoring()
            edgeMonitor.start()
            if UserDefaults.standard.bool(forKey: hideDesktopIconsKey) { setDesktopIconsHidden(true) }
        }
        showPanel()
    }

    func setDesktopIconsHidden(_ hidden: Bool) {
        if hidden {
            desktopVisibility.hideDesktopIcons()
            ownsDesktopVisibilityChange = true
        } else {
            // Turning the setting off means "show icons now", even if Sidetop
            // recovered stale state from a prior interrupted session.
            desktopVisibility.forceDesktopIconsVisible()
            ownsDesktopVisibilityChange = false
        }
    }

    @objc func quitSidetop() {
        if UserDefaults.standard.string(forKey: "menuIconMode") == "remove" {
            NSApp.terminate(nil)
            return
        }
        panelController.hide()
        edgeMonitor.stop()
        model.stopMonitoring()
        if ownsDesktopVisibilityChange {
            desktopVisibility.forceDesktopIconsVisible()
            ownsDesktopVisibilityChange = false
        }
        sidetopIsOn = false
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    func isPointOverStatusItem(_ point: NSPoint) -> Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow).contains(point)
    }
}
