import AppKit
import QuartzCore

protocol MouseFrameClock: AnyObject {
    var isRunning: Bool { get }
    func resume()
    func pause()
    func invalidate()
}

// NSWindow's display link follows the window between displays automatically.
// The owner must invalidate it to release the display link's retained target.
@available(macOS 14.0, *)
final class DisplayLinkMouseFrameClock: NSObject, MouseFrameClock {
    private var link: CADisplayLink?
    private var requestedRate: Float?
    private weak var window: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private let onFrame: () -> Void

    var isRunning: Bool { link.map { !$0.isPaused } ?? false }

    init(window: NSWindow, onFrame: @escaping () -> Void) {
        self.window = window
        self.onFrame = onFrame
        super.init()
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        self.link = link
        link.isPaused = true
        updateRefreshRate()
        link.add(to: .main, forMode: .common)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
        ) { [weak self] _ in self?.updateRefreshRate() }
    }

    private func updateRefreshRate() {
        guard let screen = window?.screen, screen.maximumFramesPerSecond > 0 else {
            if requestedRate != nil { link?.preferredFrameRateRange = .default }
            requestedRate = nil
            return
        }
        let rate = Float(screen.maximumFramesPerSecond)
        guard rate != requestedRate else { return }
        requestedRate = rate
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    func resume() {
        guard let link, link.isPaused else { return }
        updateRefreshRate()
        link.isPaused = false
    }

    func pause() { link?.isPaused = true }

    @objc private func tick(_ link: CADisplayLink) { onFrame() }

    func invalidate() {
        link?.invalidate()
        link = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}
