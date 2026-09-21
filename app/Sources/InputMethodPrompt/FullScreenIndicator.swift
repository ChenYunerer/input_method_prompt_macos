import AppKit
import QuartzCore

enum IndicatorMetrics {
    static let defaultScale = 1.0
    static let scaleRange = 0.75...5.0

    static func clampedScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultScale }
        return min(scaleRange.upperBound, max(scaleRange.lowerBound, value))
    }

    static func size(scale: Double) -> NSSize {
        let scale = clampedScale(scale)
        return NSSize(width: 36 * scale, height: 36 * scale)
    }
}

enum IndicatorPosition: String, CaseIterable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    var title: String {
        switch self {
        case .topLeft: return "左上角"
        case .top: return "上方居中"
        case .topRight: return "右上角"
        case .left: return "左侧居中"
        case .center: return "屏幕中央"
        case .right: return "右侧居中"
        case .bottomLeft: return "左下角"
        case .bottom: return "下方居中"
        case .bottomRight: return "右下角"
        }
    }

    var anchor: NSPoint {
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .topLeft, .left, .bottomLeft: x = 0
        case .top, .center, .bottom: x = 0.5
        case .topRight, .right, .bottomRight: x = 1
        }
        switch self {
        case .bottomLeft, .bottom, .bottomRight: y = 0
        case .left, .center, .right: y = 0.5
        case .topLeft, .top, .topRight: y = 1
        }
        return NSPoint(x: x, y: y)
    }
}

struct IndicatorScreen: Equatable {
    let id: UInt32
    let frame: NSRect
    let safeTop: CGFloat
    let safeRight: CGFloat

    var safeLeft: CGFloat = 0
    var safeBottom: CGFloat = 0

    func indicatorFrame(scale: Double = IndicatorMetrics.defaultScale,
                        position: IndicatorPosition = .topRight) -> NSRect {
        let size = IndicatorMetrics.size(scale: scale)
        let anchor = position.anchor
        let x = frame.minX + safeLeft + 18 + max(0, frame.width - safeLeft - safeRight - 36 - size.width) * anchor.x
        let y = frame.minY + safeBottom + 18 + max(0, frame.height - safeTop - safeBottom - 36 - size.height) * anchor.y
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

// WindowServer exposes geometry, not another app's native full-screen flag.
// Treat a window covering a display (including its notch-safe area) as immersive.
// This also intentionally covers borderless video/presentation windows.
enum FullScreenDetection {
    struct Window {
        let ownerPID: Int32
        let frame: CGRect
    }

    static func coversScreen(_ window: CGRect, screen: CGRect, safeTop: CGFloat, reservedTop: CGFloat = 0) -> Bool {
        let tolerance: CGFloat = 2
        // Native full screen on the tested notched Mac starts 5 pt below safeAreaInsets.
        // Allow that AppKit spacing plus rounding only at the notch, not at other edges.
        let safeTopTolerance: CGFloat = safeTop > 0 ? 6 : tolerance
        return abs(window.minX - screen.minX) <= tolerance &&
            abs(window.maxX - screen.maxX) <= tolerance &&
            abs(window.maxY - screen.maxY) <= tolerance &&
            (abs(window.minY - screen.minY) <= tolerance ||
             abs(window.minY - screen.minY - safeTop) <= safeTopTolerance ||
             abs(window.minY - screen.minY - reservedTop) <= tolerance)
    }

    static func isFullScreen(_ windows: [Window], screen: CGRect, safeTop: CGFloat,
                             reservedTop: CGFloat = 0) -> Bool {
        // WindowServer order is front to back. A large normal foreground window
        // must still hide an older full-screen window, including one from the same app.
        guard let main = windows.first(where: {
            let intersection = $0.frame.intersection(screen)
            return !intersection.isNull && intersection.width * intersection.height > screen.width * screen.height / 2
        }) else { return false }
        if coversScreen(main.frame, screen: screen, safeTop: safeTop, reservedTop: reservedTop) { return true }

        let tolerance: CGFloat = 2
        guard abs(main.frame.minX - screen.minX) <= tolerance,
              abs(main.frame.maxX - screen.maxX) <= tolerance,
              abs(main.frame.maxY - screen.maxY) <= tolerance else { return false }

        // Chrome immersive full screen can expose separate toolbar and content
        // windows. Only join same-process, full-width, connected top strips;
        // a bounding-box union alone would incorrectly fill gaps or unrelated windows.
        let strips = windows.filter {
            $0.ownerPID == main.ownerPID && $0.frame.height <= screen.height / 2 &&
            $0.frame.minY >= screen.minY - tolerance &&
            abs($0.frame.minX - screen.minX) <= tolerance &&
            abs($0.frame.maxX - screen.maxX) <= tolerance
        }
        var combined = main.frame
        var extended: Bool
        repeat {
            extended = false
            for strip in strips where strip.frame.minY < combined.minY &&
                strip.frame.maxY >= combined.minY - tolerance {
                combined = combined.union(strip.frame)
                extended = true
            }
        } while extended
        return coversScreen(combined, screen: screen, safeTop: safeTop, reservedTop: reservedTop)
    }

    static func screens(excludingProcessID: Int32 = ProcessInfo.processInfo.processIdentifier) -> [IndicatorScreen] {
        // Use one display snapshot throughout the conversion, including display reconfiguration.
        let screens = NSScreen.screens
        guard let primary = screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return [] }
        let candidates: [Window] = windows.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != excludingProcessID,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 0, rect.height > 0 else { return nil }
            return Window(ownerPID: pid, frame: rect)
        }
        return screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            // Quartz uses a top-left origin; AppKit uses the primary display's bottom-left.
            let bounds = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                                width: screen.frame.width, height: screen.frame.height)
            guard isFullScreen(candidates, screen: bounds, safeTop: screen.safeAreaInsets.top,
                               reservedTop: max(0, screen.frame.maxY - screen.visibleFrame.maxY)) else { return nil }
            return IndicatorScreen(id: number.uint32Value, frame: screen.frame,
                                   safeTop: screen.safeAreaInsets.top, safeRight: screen.safeAreaInsets.right,
                                   safeLeft: screen.safeAreaInsets.left, safeBottom: screen.safeAreaInsets.bottom)
        }
    }
}

final class FullScreenMonitor {
    var onChange: (([IndicatorScreen]) -> Void)?
    private(set) var current: [IndicatorScreen] = []
    private let readScreens: () -> [IndicatorScreen]
    private var enabled = false
    private var timer: Timer?
    private var pendingRefresh: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?

    init(readScreens: @escaping () -> [IndicatorScreen] = { FullScreenDetection.screens() }) {
        self.readScreens = readScreens
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        stop()
        guard enabled else {
            current = []
            onChange?([])
            return
        }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.15
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() })
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() }
        // Install resources before notifying consumers: onChange may disable the monitor.
        refresh()
    }

    private func scheduleRefresh() {
        guard enabled, pendingRefresh == nil else { return }
        // Space, application and display notifications often arrive together.
        // Coalesce that burst into one WindowServer query on the next run-loop turn.
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in self?.refresh() }
        pendingRefresh = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh() {
        pendingRefresh?.invalidate()
        pendingRefresh = nil
        guard enabled else { return }
        let screens = readScreens()
        guard screens != current else { return }
        current = screens
        onChange?(screens)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        pendingRefresh?.invalidate()
        pendingRefresh = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    deinit { stop() }
}

final class FullScreenIndicator {
    static let hoveredAlpha: CGFloat = 0.12
    private static let hoverFadeDuration: TimeInterval = 0.16
    private struct Fade {
        let initial: CGFloat
        let target: CGFloat
        let started: TimeInterval
    }
    private let readMouseLocation: () -> NSPoint
    private var hoveredScreens: Set<UInt32> = []
    private var hoverTimer: Timer?
    private var fadeTimer: Timer?
    private var lastHoverMouse: NSPoint?
    private var fades: [UInt32: Fade] = [:]
    private var requestedFrames: [UInt32: NSRect] = [:]
    private(set) var panels: [UInt32: PromptPanel] = [:]
    private var screens: [IndicatorScreen] = []
    private var state: InputState?
    private var opacity: Double
    private var scale: Double
    private var position: IndicatorPosition

    init(backgroundOpacity: Double, scale: Double = IndicatorMetrics.defaultScale,
         position: IndicatorPosition = .topRight,
         readMouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.readMouseLocation = readMouseLocation
        self.position = position
        opacity = backgroundOpacity
        self.scale = IndicatorMetrics.clampedScale(scale)
    }

    func updatePosition(_ position: IndicatorPosition) {
        guard position != self.position else { return }
        self.position = position
        render()
    }

    func updateScale(_ scale: Double) {
        let scale = IndicatorMetrics.clampedScale(scale)
        guard scale != self.scale else { return }
        self.scale = scale
        render()
    }

    func updateState(_ state: InputState?) {
        guard state != self.state else { return }
        self.state = state
        render()
    }

    func updateScreens(_ screens: [IndicatorScreen]) {
        guard screens != self.screens else { return }
        self.screens = screens
        render()
    }

    func updateBackgroundOpacity(_ opacity: Double) {
        guard opacity != self.opacity else { return }
        self.opacity = opacity
        for panel in panels.values {
            (panel.contentView as? IndicatorView)?.updateBackgroundOpacity(opacity)
        }
    }

    private func render() {
        defer { syncHoverTracking() }
        let visibleScreens = state == nil ? [] : screens
        let ids = Set(visibleScreens.map(\.id))
        for id in Array(panels.keys) where !ids.contains(id) {
            panels.removeValue(forKey: id)?.orderOut(nil)
            requestedFrames.removeValue(forKey: id)
            lastHoverMouse = nil
        }
        guard let state else { return }
        for screen in visibleScreens {
            let frame = screen.indicatorFrame(scale: scale, position: position)
            let panel: PromptPanel
            if let existing = panels[screen.id] {
                panel = existing
            } else {
                panel = PromptPanel(contentRect: frame,
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
                panel.contentView = IndicatorView(backgroundOpacity: opacity, scale: scale)
                panels[screen.id] = panel
            }
            (panel.contentView as? IndicatorView)?.display(state)
            if requestedFrames[screen.id] != frame {
                requestedFrames[screen.id] = frame
                lastHoverMouse = nil
                if panel.frame != frame { panel.setFrame(frame, display: false) }
                (panel.contentView as? IndicatorView)?.updateScale(scale)
            }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func syncHoverTracking() {
        guard !panels.isEmpty else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            fadeTimer?.invalidate()
            fadeTimer = nil
            hoveredScreens.removeAll()
            fades.removeAll()
            lastHoverMouse = nil
            return
        }
        hoveredScreens.formIntersection(panels.keys)
        fades = fades.filter { panels[$0.key] != nil }
        if fades.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
        if hoverTimer == nil {
            // Keep click-through enabled: observe position without subscribing to mouse events.
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.refreshHover() }
            timer.tolerance = 0.015
            hoverTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        refreshHover()
    }

    func refreshHover() {
        guard !panels.isEmpty else { return }
        let mouse = readMouseLocation()
        guard mouse != lastHoverMouse else { return }
        lastHoverMouse = mouse
        let hovered = Set(panels.compactMap { id, panel in panel.frame.contains(mouse) ? id : nil })
        for id in hovered.symmetricDifference(hoveredScreens) {
            guard let panel = panels[id] else { continue }
            fades[id] = Fade(initial: panel.alphaValue,
                             target: hovered.contains(id) ? Self.hoveredAlpha : 1,
                             started: CACurrentMediaTime())
        }
        hoveredScreens = hovered
        guard !fades.isEmpty, fadeTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.advanceFades() }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceFades() {
        let now = CACurrentMediaTime()
        for (id, fade) in fades {
            guard let panel = panels[id] else { fades.removeValue(forKey: id); continue }
            let progress = min(1, (now - fade.started) / Self.hoverFadeDuration)
            let eased = progress * progress * (3 - 2 * progress)
            panel.alphaValue = fade.initial + (fade.target - fade.initial) * eased
            if progress >= 1 { fades.removeValue(forKey: id) }
        }
        if fades.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    deinit {
        hoverTimer?.invalidate()
        fadeTimer?.invalidate()
        panels.values.forEach { $0.orderOut(nil) }
    }
}

final class IndicatorView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var opacity: Double
    private var appliedScale: Double?
    private var displayedState: InputState?
    private var maskSize: NSSize?
    private var maskAlpha: CGFloat?

    init(backgroundOpacity: Double, scale: Double) {
        opacity = backgroundOpacity
        super.init(frame: NSRect(origin: .zero, size: IndicatorMetrics.size(scale: scale)))
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        label.textColor = .labelColor
        label.alignment = .center
        addSubview(label)
        updateScale(scale)
    }

    required init?(coder: NSCoder) { nil }

    func display(_ state: InputState) {
        guard state != displayedState else { return }
        displayedState = state
        label.stringValue = state.symbol
        setAccessibilityLabel(state.caption)
    }

    func updateScale(_ scale: Double) {
        let scale = IndicatorMetrics.clampedScale(scale)
        guard scale != appliedScale else { return }
        appliedScale = scale
        let factor = CGFloat(scale)
        setFrameSize(IndicatorMetrics.size(scale: scale))
        label.font = .systemFont(ofSize: 18 * factor, weight: .medium)
        label.frame = NSRect(x: 3 * factor, y: 6 * factor, width: 30 * factor, height: 24 * factor)
        updateBackgroundOpacity(opacity)
    }

    func updateBackgroundOpacity(_ opacity: Double) {
        self.opacity = opacity
        let alpha = CGFloat(min(1, max(0, opacity)))
        guard frame.size != maskSize || alpha != maskAlpha else { return }
        maskSize = frame.size
        maskAlpha = alpha
        let radius = PromptStyle.cornerRadius(for: frame.size)
        maskImage = NSImage(size: frame.size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        needsDisplay = true
    }
}
