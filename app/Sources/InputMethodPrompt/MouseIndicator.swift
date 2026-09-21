import AppKit
import QuartzCore

enum MouseIndicatorLayout {
    static let defaultScale = 1.0
    static let scaleRange = 0.5...3.0
    static let backgroundOpacity = 0.55
    static let opacity: CGFloat = 0.5

    static func clampedScale(_ value: Double) -> Double {
        value.isFinite ? min(scaleRange.upperBound, max(scaleRange.lowerBound, value)) : defaultScale
    }

    static func size(scale: Double = defaultScale) -> NSSize {
        let scale = clampedScale(scale)
        return NSSize(width: 27 * scale, height: 27 * scale)
    }

    static func frame(at mouse: NSPoint, in screens: [NSRect], scale: Double = defaultScale) -> NSRect? {
        var placement = MouseIndicatorPlacement()
        return placement.frame(at: mouse, in: screens, scale: scale)
    }
}

struct MouseIndicatorPlacement {
    private var previousScreen: NSRect?
    private var previousSize: NSSize?
    private var onLeft = false
    private var above = false

    mutating func frame(at mouse: NSPoint, in screens: [NSRect],
                        scale: Double = MouseIndicatorLayout.defaultScale) -> NSRect? {
        guard let screen = screens.first(where: { $0.contains(mouse) }) else {
            self = Self()
            return nil
        }
        let size = MouseIndicatorLayout.size(scale: scale)
        if previousScreen != screen || previousSize != size {
            onLeft = false
            above = false
            previousScreen = screen
            previousSize = size
        }
        let inset: CGFloat = 6
        let gap: CGFloat = 18
        let returnMargin: CGFloat = 12
        let bounds = screen.insetBy(dx: inset, dy: inset)
        let right = mouse.x + gap
        let left = mouse.x - gap - size.width
        let below = mouse.y - gap - size.height
        let top = mouse.y + gap
        // Switch away as soon as space runs out, but require extra room before
        // switching back. Tiny pointer movements near an edge must not flip sides.
        if onLeft {
            if right + size.width <= bounds.maxX - returnMargin || left < bounds.minX { onLeft = false }
        } else if right + size.width > bounds.maxX { onLeft = true }
        if above {
            if below >= bounds.minY + returnMargin || top + size.height > bounds.maxY { above = false }
        } else if below < bounds.minY { above = true }
        var x = onLeft ? left : right
        var y = above ? top : below
        x = min(max(bounds.minX, x), max(bounds.minX, bounds.maxX - size.width))
        y = min(max(bounds.minY, y), max(bounds.minY, bounds.maxY - size.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

// A moving badge does not need live backdrop blur or a WindowServer shadow.
// Draw a small translucent surface once; moving the window reuses its contents.
final class MouseIndicatorView: NSView {
    private var appliedScale: Double?
    private var displayedState: InputState?
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(origin: .zero, size: MouseIndicatorLayout.size()))
        wantsLayer = true
        label.textColor = .labelColor
        label.alignment = .center
        addSubview(label)
        updateScale(MouseIndicatorLayout.defaultScale)
    }

    required init?(coder: NSCoder) { nil }

    func updateScale(_ scale: Double) {
        let scale = MouseIndicatorLayout.clampedScale(scale)
        guard scale != appliedScale else { return }
        appliedScale = scale
        setFrameSize(MouseIndicatorLayout.size(scale: scale))
        label.font = .systemFont(ofSize: 13.5 * scale, weight: .medium)
        label.frame = NSRect(x: 2.25 * scale, y: 4.5 * scale, width: 22.5 * scale, height: 18 * scale)
        needsDisplay = true
    }

    func display(_ state: InputState) {
        guard state != displayedState else { return }
        displayedState = state
        if label.stringValue != state.symbol { label.stringValue = state.symbol }
        setAccessibilityLabel(state.caption)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = PromptStyle.cornerRadius(for: bounds.size)
        NSColor.windowBackgroundColor.withAlphaComponent(MouseIndicatorLayout.backgroundOpacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

enum MouseIdleBehavior: String, CaseIterable {
    case hide, fade
    var title: String { self == .hide ? "隐藏" : "淡化" }
}

// This legacy public CoreGraphics symbol is no longer exposed to Swift.
// Resolve it optionally: unsupported systems report unknown rather than a made-up state.
enum SystemCursorVisibility {
    private static let query: (@convention(c) () -> UInt32)? = {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else { return nil }
        return unsafeBitCast(address, to: (@convention(c) () -> UInt32).self)
    }()
    static func read() -> Bool? { query.map { $0() != 0 } }
}

final class MouseIndicator {
    typealias FrameClockFactory = (NSWindow, @escaping () -> Void) -> MouseFrameClock?
    static let defaultIdleDelay: TimeInterval = 3
    static let idleDelayRange: ClosedRange<Double> = 1...60
    static func clampedIdleDelay(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIdleDelay }
        return min(idleDelayRange.upperBound, max(idleDelayRange.lowerBound, value.rounded()))
    }
    static let idleOpacityFactor = 0.2
    static let inputChangeDuration: TimeInterval = 0.5
    static let fadeInDuration: TimeInterval = 0.12
    static let fadeOutDuration: TimeInterval = 0.18
    let panel: PromptPanel
    private let readCursorVisible: () -> Bool?
    private let readTime: () -> TimeInterval
    private var cursorVisible: Bool?
    private var baseOpacity = Double(MouseIndicatorLayout.opacity)
    private var idleDelay = MouseIndicator.defaultIdleDelay
    private var idleBehavior: MouseIdleBehavior = .hide
    private var lastMovementTime: TimeInterval = 0
    private var visibilityTimer: Timer?
    private var inputChangeTimer: Timer?
    private var appearanceTimer: Timer?
    private var appearanceTarget: CGFloat?
    private let view = MouseIndicatorView()
    private let readMouseLocation: () -> NSPoint
    private let readScreens: () -> [NSRect]
    private let observeMouseEvents: Bool
    private let makeFrameClock: FrameClockFactory
    private var frameClock: MouseFrameClock?
    private var idleFramesRemaining = 0
    private var placement = MouseIndicatorPlacement()
    private var enabled = false
    private var scale = MouseIndicatorLayout.defaultScale
    private var state: InputState?
    private var tracking = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var pendingRefresh: Timer?
    private var screens: [NSRect] = []
    private var lastMouse: NSPoint?
    private var lastOrigin: NSPoint?
    private var lastRefreshTime: TimeInterval = 0

    init(readMouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
         readScreens: @escaping () -> [NSRect] = { NSScreen.screens.map(\.frame) },
         observeMouseEvents: Bool = true,
         readCursorVisible: @escaping () -> Bool? = { SystemCursorVisibility.read() },
         readTime: @escaping () -> TimeInterval = { CACurrentMediaTime() },
         makeFrameClock: @escaping FrameClockFactory = { window, callback in
             if #available(macOS 14.0, *) {
                 return DisplayLinkMouseFrameClock(window: window, onFrame: callback)
             }
             return nil
         }) {
        self.readCursorVisible = readCursorVisible
        self.readTime = readTime
        self.readMouseLocation = readMouseLocation
        self.readScreens = readScreens
        self.observeMouseEvents = observeMouseEvents
        self.makeFrameClock = makeFrameClock
        panel = PromptPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = MouseIndicatorLayout.opacity
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = view
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        syncTracking()
    }

    func updateState(_ state: InputState?) {
        guard self.state != state else { return }
        let shouldReveal = tracking && self.state != nil && state != nil &&
            (inputChangeTimer != nil || cursorVisible == false || readTime() - lastMovementTime >= idleDelay)
        self.state = state
        if let state { view.display(state) }
        syncTracking()
        if shouldReveal, tracking { revealInputChange() }
    }

    private func revealInputChange() {
        inputChangeTimer?.invalidate()
        let fadeInTime = panel.isVisible && panel.alphaValue == CGFloat(baseOpacity) ? 0 : Self.fadeInDuration
        let timer = Timer(timeInterval: Self.inputChangeDuration + fadeInTime, repeats: false) { [weak self] timer in
            guard let self, self.inputChangeTimer === timer else { return }
            self.inputChangeTimer = nil
            // Restore the current policy, not a stale snapshot from before the reveal.
            self.refreshVisibility()
        }
        inputChangeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        // Read the actual location, but only a real pointer move resets idle time.
        refreshPosition(force: true)
    }

    func updateAppearance(scale: Double, opacity: Double) {
        let scale = MouseIndicatorLayout.clampedScale(scale)
        let opacity = opacity.isFinite ? min(1, max(0, opacity)) : Double(MouseIndicatorLayout.opacity)
        let resized = scale != self.scale
        guard resized || opacity != baseOpacity else { return }
        if resized {
            self.scale = scale
            panel.setContentSize(MouseIndicatorLayout.size(scale: scale))
            view.updateScale(scale)
            lastOrigin = nil
        }
        baseOpacity = opacity
        syncTracking()
        if resized, tracking { refreshPosition(force: true) }
        if tracking { applyVisibility() }
    }

    func updateIdleDelay(_ seconds: TimeInterval) {
        let delay = Self.clampedIdleDelay(seconds)
        guard delay != idleDelay else { return }
        idleDelay = delay
        if tracking { applyVisibility() }
    }

    func updateIdleBehavior(_ behavior: MouseIdleBehavior) {
        guard idleBehavior != behavior else { return }
        idleBehavior = behavior
        if tracking { applyVisibility() }
    }

    private func syncTracking() {
        guard enabled, state != nil, baseOpacity > 0 else {
            if tracking { stopTracking() }
            animateAppearance(to: 0)
            return
        }
        guard !tracking else { return }
        tracking = true
        lastMovementTime = readTime()
        cursorVisible = readCursorVisible()
        startVisibilityPolling()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if observeMouseEvents {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                self?.schedulePositionRefresh()
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.schedulePositionRefresh()
                return event
            }
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.refreshScreens() })
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshScreens() }
        refreshScreens()
        frameClock = makeFrameClock(panel) { [weak self] in self?.displayFrame() }
    }

    // Respond immediately to the first movement after rest. Further events are
    // merged into the next display refresh and sample the latest cursor position.
    func schedulePositionRefresh() {
        guard tracking else { return }
        if let frameClock, cursorVisible != false {
            idleFramesRemaining = 3
            if !frameClock.isRunning || !panel.isVisible {
                refreshPosition()
                frameClock.resume()
            }
            return
        }
        // macOS 13 compatibility: CADisplayLink is available starting in macOS 14.
        guard pendingRefresh == nil else { return }
        let delay = 1.0 / 120 - (CACurrentMediaTime() - lastRefreshTime)
        guard delay > 0 else { refreshPosition(); return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.pendingRefresh = nil
            self?.refreshPosition()
        }
        pendingRefresh = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func displayFrame() {
        guard tracking else {
            frameClock?.pause()
            return
        }
        // While moving, sample the actual pointer at every display refresh even
        // if AppKit has not delivered its mouse event yet. Stop after 3 unchanged
        // samples; a delayed event no longer causes a skipped frame or false idle.
        let previousMouse = lastMouse
        refreshPosition()
        if lastMouse == previousMouse {
            idleFramesRemaining -= 1
            if idleFramesRemaining <= 0 { frameClock?.pause() }
        } else {
            idleFramesRemaining = 3
        }
    }

    func refreshScreens() {
        guard tracking else { return }
        screens = readScreens()
        refreshPosition(force: true)
    }

    func refreshPosition(force: Bool = false) {
        guard tracking else { return }
        lastRefreshTime = CACurrentMediaTime()
        let mouse = readMouseLocation()
        guard force || mouse != lastMouse else { return }
        if mouse != lastMouse {
            lastMovementTime = readTime()
            if cursorVisible == false || visibilityTimer == nil { cursorVisible = readCursorVisible() }
        }
        lastMouse = mouse
        guard let frame = placement.frame(at: mouse, in: screens, scale: scale) else {
            appearanceTimer?.invalidate()
            appearanceTimer = nil
            appearanceTarget = nil
            if panel.isVisible { panel.orderOut(nil) }
            lastOrigin = nil
            return
        }
        // WindowServer rounds window origins. Compare our requested origin rather
        // than its rounded frame, otherwise fractional coordinates cause endless moves.
        let origin = NSPoint(x: floor(frame.minX), y: floor(frame.minY))
        if origin != lastOrigin {
            panel.setFrameOrigin(origin)
            lastOrigin = origin
        }
        applyVisibility(forceOrder: force)
    }

    // Only query visibility and elapsed time here; position and screen reads stay event-driven.
    func refreshVisibility() {
        guard tracking else { return }
        let previous = cursorVisible
        cursorVisible = readCursorVisible()
        if previous == false && cursorVisible == true {
            refreshPosition(force: true)
        }
        applyVisibility()
    }

    private func startVisibilityPolling() {
        guard visibilityTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.refreshVisibility() }
        timer.tolerance = 0.02
        visibilityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func pauseUnneededVisibilityPolling() {
        guard tracking, inputChangeTimer == nil, idleBehavior == .hide, !panel.isVisible,
              readTime() - lastMovementTime >= idleDelay else { return }
        // Cursor changes cannot reveal an idle-hidden badge. Mouse events and
        // settings changes wake it without a background visibility poll.
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        frameClock?.pause()
    }

    private func applyVisibility(forceOrder: Bool = false) {
        guard tracking else { return }
        let idle = readTime() - lastMovementTime >= idleDelay
        let revealingChange = inputChangeTimer != nil
        if visibilityTimer == nil, revealingChange || !(idle && idleBehavior == .hide) {
            cursorVisible = readCursorVisible()
            startVisibilityPolling()
        }
        // A confirmed input change briefly takes priority over cursor/idle hiding,
        // while disabled, fully transparent and off-screen states remain suppressed.
        let suppressed = lastOrigin == nil || (cursorVisible == false && !revealingChange)
        let target = suppressed ? 0 : CGFloat(baseOpacity * (idle && !revealingChange ? (idleBehavior == .hide ? 0 : Self.idleOpacityFactor) : 1))
        animateAppearance(to: target, forceOrder: forceOrder)
        pauseUnneededVisibilityPolling()
    }

    private func animateAppearance(to target: CGFloat, forceOrder: Bool = false) {
        if target > 0 {
            if !panel.isVisible {
                // Set alpha before ordering in, so a hidden badge never flashes.
                panel.alphaValue = 0
                appearanceTarget = nil
                panel.orderFrontRegardless()
            } else if forceOrder {
                panel.orderFrontRegardless()
            }
        }
        // Mouse/frame/visibility updates must not keep restarting the same animation.
        guard target != appearanceTarget else { return }
        appearanceTimer?.invalidate()
        appearanceTimer = nil
        appearanceTarget = target
        let initial = panel.alphaValue
        guard panel.isVisible, initial != target else {
            panel.alphaValue = target
            if target == 0 { panel.orderOut(nil) }
            return
        }
        let started = CACurrentMediaTime()
        let duration = target > initial ? Self.fadeInDuration : Self.fadeOutDuration
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let progress = min(1, (CACurrentMediaTime() - started) / duration)
            let eased = progress * progress * (3 - 2 * progress)
            self.panel.alphaValue = initial + (target - initial) * eased
            if progress >= 1 {
                self.appearanceTimer?.invalidate()
                self.appearanceTimer = nil
                if target == 0 { self.panel.orderOut(nil) }
                self.pauseUnneededVisibilityPolling()
            }
        }
        appearanceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTracking() {
        tracking = false
        inputChangeTimer?.invalidate()
        inputChangeTimer = nil
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        appearanceTimer?.invalidate()
        appearanceTimer = nil
        appearanceTarget = nil
        idleFramesRemaining = 0
        placement = MouseIndicatorPlacement()
        frameClock?.invalidate()
        frameClock = nil
        pendingRefresh?.invalidate()
        pendingRefresh = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        screens = []
        lastMouse = nil
        lastOrigin = nil
        lastRefreshTime = 0
    }

    deinit {
        stopTracking()
        panel.orderOut(nil)
    }
}
