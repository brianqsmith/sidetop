import AppKit

@MainActor
final class EdgeMonitor {
    private let handler: (NSScreen) -> Void
    private var timer: Timer?
    private var enteredAt: Date?
    private weak var enteredScreen: NSScreen?
    private var fired = false

    init(handler: @escaping (NSScreen) -> Void) { self.handler = handler }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePointer() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func samplePointer() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              abs(point.x - screen.frame.maxX) <= 2.5 else {
            enteredAt = nil
            enteredScreen = nil
            fired = false
            return
        }
        if enteredScreen !== screen {
            enteredScreen = screen
            enteredAt = Date()
            fired = false
        }
        guard !fired, let enteredAt, Date().timeIntervalSince(enteredAt) >= 1 else { return }
        fired = true
        handler(screen)
    }
}
