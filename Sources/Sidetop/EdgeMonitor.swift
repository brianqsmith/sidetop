import AppKit

@MainActor
final class EdgeMonitor {
    private let handler: (NSScreen) -> Void
    private var timer: Timer?
    private weak var enteredScreen: NSScreen?
    private var fired = false

    init(handler: @escaping (NSScreen) -> Void) { self.handler = handler }

    func start() {
        let timer = Timer(timeInterval: 0.03,
                          target: self,
                          selector: #selector(samplePointer),
                          userInfo: nil,
                          repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }

    @objc private func samplePointer() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              abs(point.x - screen.frame.maxX) <= 2.5 else {
            enteredScreen = nil
            fired = false
            return
        }
        if enteredScreen !== screen {
            enteredScreen = screen
            fired = false
        }
        guard !fired else { return }
        fired = true
        handler(screen)
    }
}
