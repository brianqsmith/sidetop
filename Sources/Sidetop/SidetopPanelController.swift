import AppKit
import SwiftUI

final class SidetopPanel: NSPanel {
    var slideAnimationDuration: TimeInterval = 0.50

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        slideAnimationDuration
    }
}

@MainActor
final class SidetopPanelController: NSObject, NSWindowDelegate {
    private let model: DesktopModel
    private let panel: SidetopPanel
    private let quickLook = QuickLookController()
    private let setDesktopIconsHidden: (Bool) -> Void
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private var isReanchoring = false
    private var isPresented = false
    private var animationGeneration = 0
    private var autoCloseTimer: Timer?
    private var autoCloseArmed = false
    private var scrollbarHideWorkItem: DispatchWorkItem?
    private var menuTrackingDepth = 0
    private var menuTrackingObservers: [NSObjectProtocol] = []

    var isVisible: Bool { isPresented }

    init(model: DesktopModel, setDesktopIconsHidden: @escaping (Bool) -> Void) {
        self.model = model
        self.setDesktopIconsHidden = setDesktopIconsHidden
        let savedWidth = UserDefaults.standard.double(forKey: "panelWidthCompact")
        let savedHeight = UserDefaults.standard.double(forKey: "panelHeight")
        let size = NSSize(width: savedWidth > 0 ? savedWidth : 310,
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 260, height: 360)
        panel.contentView = NSHostingView(rootView: SidetopView(model: model,
                                                               close: { [weak self] in self?.hide() },
                                                               setDesktopIconsHidden: setDesktopIconsHidden))
        panel.setFrameAutosaveName("SidetopPanelSize")
        installMenuTrackingObservers()
        DispatchQueue.main.async { [weak self] in self?.setScrollbarsVisible(false) }
    }

    func toggle(on screen: NSScreen?) {
        if isPresented { hide() } else if let screen { show(on: screen) }
    }

    func show(on screen: NSScreen) {
        guard !isPresented else { return }
        // The panel may have been hidden while Finder, a screenshot utility,
        // or another app changed the displayed folder. Always rescan before
        // presenting so reopening Sidetop never shows a stale snapshot even
        // if a filesystem notification was missed or coalesced.
        model.refresh()
        isPresented = true
        autoCloseArmed = false
        animationGeneration += 1
        let generation = animationGeneration
        let visible = screen.visibleFrame
        var size = panel.frame.size
        size.width = min(max(size.width, panel.minSize.width), visible.width)
        size.height = min(max(size.height, panel.minSize.height), visible.height)
        let targetFrame = NSRect(x: visible.maxX - size.width,
                                 y: visible.maxY - size.height,
                                 width: size.width,
                                 height: size.height)
        var hiddenFrame = targetFrame
        hiddenFrame.origin.x = screen.frame.maxX + 8
        panel.setFrame(hiddenFrame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        setScrollbarsVisible(false)
        installEventMonitors()

        animatePanel(from: hiddenFrame.origin,
                     to: targetFrame.origin,
                     duration: animationDuration) { [weak self] in
            guard let self, self.animationGeneration == generation, self.isPresented else { return }
            self.startAutoCloseMonitor()
        }
    }

    func hide() {
        guard isPresented else { return }
        isPresented = false
        animationGeneration += 1
        let generation = animationGeneration
        quickLook.close()
        removeEventMonitors()
        stopAutoCloseMonitor()
        guard let screen = panel.screen else {
            panel.orderOut(nil)
            return
        }
        var hiddenFrame = panel.frame
        hiddenFrame.origin.x = screen.frame.maxX + 8
        animatePanel(from: panel.frame.origin,
                     to: hiddenFrame.origin,
                     duration: animationDuration) { [weak self] in
            guard let self, self.animationGeneration == generation, !self.isPresented else { return }
            self.panel.orderOut(nil)
        }
    }

    private func animatePanel(from start: NSPoint,
                              to end: NSPoint,
                              duration: TimeInterval,
                              completion: @escaping () -> Void) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, duration > 0 else {
            panel.setFrameOrigin(end)
            completion()
            return
        }

        panel.setFrameOrigin(start)
        panel.slideAnimationDuration = duration
        var endFrame = panel.frame
        endFrame.origin = end
        // NSWindow's native frame animation is paced by AppKit/WindowServer,
        // avoiding the uneven main-run-loop timer updates that made the panel
        // stutter while SwiftUI was also processing its file list.
        panel.setFrame(endFrame, display: false, animate: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
        }
    }

    private var animationDuration: TimeInterval {
        switch UserDefaults.standard.string(forKey: "animationSpeed") ?? "slow" {
        case "instant": return 0
        case "fast": return 0.35
        default: return 0.50
        }
    }

    func windowDidResize(_ notification: Notification) {
        UserDefaults.standard.set(panel.frame.width, forKey: "panelWidthCompact")
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
            Task { @MainActor in
                guard let self,
                      UserDefaults.standard.string(forKey: "closeWindowMode") == "focus",
                      !self.panel.frame.contains(NSEvent.mouseLocation),
                      !self.isPointInMenuBar(NSEvent.mouseLocation),
                      ((NSApp.delegate as? AppDelegate)?.isPointOverStatusItem(NSEvent.mouseLocation) ?? false) == false else { return }
                self.hide()
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            if event.type == .scrollWheel {
                if event.window === self.panel,
                   abs(event.scrollingDeltaY) > 0 || abs(event.scrollingDeltaX) > 0 {
                    self.revealScrollbarsForScrolling()
                }
                return event
            }
            if event.type == .keyDown {
                if self.quickLook.isVisible {
                    if self.selectionOffset(for: event) != nil {
                        return self.handleKey(event) ? nil : event
                    }
                    if event.modifierFlags.contains(.command),
                       (event.keyCode == 51 || event.keyCode == 117) {
                        guard let currentURL = self.model.selectedURL else { return event }
                        let deletingURLs = self.model.selectedURLs
                        let nextURL = self.model.item(after: currentURL, excluding: deletingURLs)
                        self.model.deleteSelection(selecting: nextURL)
                        if let nextURL {
                            self.model.select(nextURL, extendingRange: false)
                            self.quickLook.update(url: nextURL)
                        } else {
                            self.quickLook.close()
                        }
                        return nil
                    }
                }
                guard event.window === self.panel, NSApp.modalWindow == nil else { return event }
                return self.handleKey(event) ? nil : event
            }
            if event.window !== self.panel,
               UserDefaults.standard.string(forKey: "closeWindowMode") == "focus",
               !self.isPointInMenuBar(NSEvent.mouseLocation),
               !((NSApp.delegate as? AppDelegate)?.isPointOverStatusItem(NSEvent.mouseLocation) ?? false) {
                self.hide()
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor); self.globalClickMonitor = nil }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor); self.localEventMonitor = nil }
        scrollbarHideWorkItem?.cancel()
        scrollbarHideWorkItem = nil
        setScrollbarsVisible(false)
    }

    private func revealScrollbarsForScrolling() {
        setScrollbarsVisible(true)
        scrollbarHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.setScrollbarsVisible(false) }
        scrollbarHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    private func setScrollbarsVisible(_ visible: Bool) {
        guard let contentView = panel.contentView else { return }
        for scrollView in scrollViews(in: contentView) {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = false
            scrollView.hasVerticalScroller = visible
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap(scrollViews(in:))
    }

    private func startAutoCloseMonitor() {
        stopAutoCloseMonitor()
        let timer = Timer(timeInterval: 0.05,
                          target: self,
                          selector: #selector(checkAutoClose),
                          userInfo: nil,
                          repeats: true)
        autoCloseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func installMenuTrackingObservers() {
        let center = NotificationCenter.default
        menuTrackingObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                                         object: nil,
                                                         queue: .main) { [weak self] _ in
            Task { @MainActor in self?.menuTrackingDepth += 1 }
        })
        menuTrackingObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification,
                                                         object: nil,
                                                         queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
            }
        })
    }

    private func stopAutoCloseMonitor() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        autoCloseArmed = false
    }

    @objc private func checkAutoClose() {
        guard isPresented,
              UserDefaults.standard.string(forKey: "closeWindowMode") == "auto" else {
            autoCloseArmed = false
            return
        }
        // Keep the panel alive while a file is being dragged out of it. The drag
        // session owns the pointer until mouse-up, just like a Dock drag.
        // Native context menus and their Open With submenus can extend outside
        // the panel; menu tracking temporarily owns the pointer in the same way.
        guard NSEvent.pressedMouseButtons == 0,
              menuTrackingDepth == 0,
              NSApp.modalWindow == nil else { return }
        if panel.frame.contains(NSEvent.mouseLocation) {
            autoCloseArmed = true
        } else if autoCloseArmed, !quickLook.isVisible {
            hide()
        }
    }

    private func isPointInMenuBar(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            point.x >= screen.frame.minX && point.x <= screen.frame.maxX &&
                point.y >= screen.visibleFrame.maxY && point.y <= screen.frame.maxY
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if let offset = selectionOffset(for: event) {
            let extendsRange = event.modifierFlags.contains(.shift)
            if let url = model.moveSelection(by: offset,
                                             extendingRange: extendsRange),
               quickLook.isVisible {
                quickLook.update(url: url)
            }
            return true
        }
        guard let url = model.selectedURL else {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" { model.paste(); return true }
            return false
        }
        if event.keyCode == 49 { quickLook.toggle(url: url, sourceWindow: panel); return true }
        if event.modifierFlags.contains(.command), (event.keyCode == 51 || event.keyCode == 117) {
            model.deleteSelection()
            return true
        }
        if event.keyCode == 36 { model.rename(url); return true }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "o": model.open(url); return true
            case "c": model.copy(url); return true
            case "v": model.paste(); return true
            case "d": model.duplicate(url); return true
            default: break
            }
        }
        return false
    }

    private func selectionOffset(for event: NSEvent) -> Int? {
        let isIconMode = UserDefaults.standard.string(forKey: "browserViewMode") == "icon"
        switch event.keyCode {
        case 125:
            return isIconMode ? iconGridColumnCount : 1   // Down
        case 126:
            return isIconMode ? -iconGridColumnCount : -1 // Up
        case 123 where isIconMode:
            return -1       // Left
        case 124 where isIconMode:
            return 1        // Right
        default:
            return nil
        }
    }

    private var iconGridColumnCount: Int {
        // Keep this calculation aligned with SidetopView's 108-point adaptive
        // cells, 6-point column spacing, and its surrounding panel/grid padding.
        let panelWidth = panel.contentView?.bounds.width ?? panel.frame.width
        let usableWidth = max(108, panelWidth - 28)
        return max(1, Int((usableWidth + 6) / (108 + 6)))
    }

}
