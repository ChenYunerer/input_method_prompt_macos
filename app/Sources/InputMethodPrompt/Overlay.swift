import AppKit
import QuartzCore

final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Overlay {
    static let defaultDuration: TimeInterval = 1
    static let durationRange: ClosedRange<Double> = 0.1...10
    static func clampedDuration(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDuration }
        let bounded = min(durationRange.upperBound, max(durationRange.lowerBound, value))
        return (bounded * 10).rounded() / 10
    }
    static let fadeInDuration: TimeInterval = 0.12
    static let fadeDuration: TimeInterval = 0.18
    let panel: PromptPanel
    private let promptView: PromptView
    private var dismissal: Timer?
    private var fadeTimer: Timer?
    private(set) var holdDuration: TimeInterval

    init(backgroundOpacity: Double = 0.78, holdDuration: TimeInterval = Overlay.defaultDuration) {
        self.holdDuration = Self.clampedDuration(holdDuration)
        promptView = PromptView(backgroundOpacity: backgroundOpacity)
        let size = PromptView.size
        panel = PromptPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        panel.contentView = promptView
    }

    func updateBackgroundOpacity(_ opacity: Double) {
        promptView.updateBackgroundOpacity(opacity)
    }

    func updateHoldDuration(_ duration: TimeInterval) {
        guard duration.isFinite else { return }
        holdDuration = Self.clampedDuration(duration)
    }

    func show(_ source: InputSource) {
        show(InputState(source: source, capsLock: false))
    }

    func show(_ state: InputState) {
        // Snapshot per presentation: editing settings never extends or cuts short an active prompt.
        let duration = holdDuration
        let startingAlpha = panel.isVisible ? panel.alphaValue : 0
        cancelTimers()
        panel.alphaValue = startingAlpha
        promptView.display(state)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        if let frame = screen?.frame {
            let origin = NSPoint(x: floor(frame.midX - panel.frame.width / 2),
                                 y: floor(frame.midY - panel.frame.height / 2))
            if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        }
        panel.orderFrontRegardless()
        animateAlpha(to: 1, duration: Self.fadeInDuration) { [weak self] in
            self?.scheduleDismissal(after: duration)
        }
    }

    private func scheduleDismissal(after duration: TimeInterval) {
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] timer in
            guard let self, self.dismissal === timer else { return }
            self.beginFade()
        }
        dismissal = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func beginFade() {
        dismissal = nil
        animateAlpha(to: 0, duration: Self.fadeDuration) { [weak self] in self?.hide() }
    }

    private func animateAlpha(to target: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        let initial = panel.alphaValue
        guard initial != target else {
            completion()
            return
        }
        let start = CACurrentMediaTime()
        // Cancelling this timer prevents stale animation completions hiding a newer prompt.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let progress = min(1, (CACurrentMediaTime() - start) / duration)
            let eased = progress * progress * (3 - 2 * progress)
            self.panel.alphaValue = initial + (target - initial) * eased
            if progress >= 1 {
                self.fadeTimer?.invalidate()
                self.fadeTimer = nil
                completion()
            }
        }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelTimers() {
        dismissal?.invalidate()
        dismissal = nil
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    func hide() {
        cancelTimers()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    deinit { cancelTimers(); panel.orderOut(nil) }
}
