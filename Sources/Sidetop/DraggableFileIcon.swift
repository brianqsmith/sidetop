import AppKit
import SwiftUI

struct DraggableFileSurface: NSViewRepresentable {
    let url: URL
    let dragURLs: () -> [URL]
    let onClick: (Int, NSEvent.ModifierFlags) -> Void

    init(url: URL,
         dragURLs: @escaping () -> [URL] = { [] },
         onClick: @escaping (Int, NSEvent.ModifierFlags) -> Void) {
        self.url = url
        self.dragURLs = dragURLs
        self.onClick = onClick
    }

    func makeNSView(context: Context) -> FileDragSurfaceView {
        let view = FileDragSurfaceView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: FileDragSurfaceView, context: Context) { update(nsView) }

    private func update(_ view: FileDragSurfaceView) {
        view.fileURL = url
        view.dragURLsProvider = dragURLs
        view.clickHandler = onClick
    }
}

final class FileDragSurfaceView: NSView, NSDraggingSource {
    var fileURL: URL?
    var dragURLsProvider: (() -> [URL])?
    var clickHandler: ((Int, NSEvent.ModifierFlags) -> Void)?

    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {}

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startingPoint = convert(event.locationInWindow, from: nil)
        // Capture selection modifiers at mouse-down. During AppKit's custom
        // drag-tracking loop the mouse-up event does not reliably retain Shift.
        let clickModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if nextEvent.type == .leftMouseUp {
                let modifiers = clickModifiers
                    .union(nextEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
                    .union(NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
                clickHandler?(nextEvent.clickCount, modifiers)
                return
            }

            let currentPoint = convert(nextEvent.locationInWindow, from: nil)
            if hypot(currentPoint.x - startingPoint.x, currentPoint.y - startingPoint.y) >= 3,
               let fileURL {
                let selected = dragURLsProvider?() ?? []
                let urls = selected.contains(fileURL) && !selected.isEmpty ? selected : [fileURL]
                let draggingItems = urls.map { url -> NSDraggingItem in
                    let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    item.setDraggingFrame(NSRect(origin: currentPoint, size: NSSize(width: 48, height: 48)),
                                          contents: icon)
                    return item
                }
                beginDraggingSession(with: draggingItems, event: nextEvent, source: self)
                return
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Keep the session valid while it crosses Sidetop's own window boundary.
        // Finder will choose Move for a normal same-volume file drag, while apps
        // that consume files (for example upload targets) can choose Copy.
        [.copy, .move]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
