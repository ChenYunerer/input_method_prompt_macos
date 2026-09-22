import Carbon
import AppKit
import CoreGraphics

struct InputSource: Equatable {
    let id: String
    let name: String
    let languages: [String]
    let inputModeID: String?

    init(id: String, name: String, languages: [String], inputModeID: String? = nil) {
        self.id = id
        self.name = name
        self.languages = languages
        self.inputModeID = inputModeID
    }

    var language: String {
        (languages.first ?? "").replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init)?.lowercased() ?? ""
    }

    var symbol: String {
        switch language {
        case "zh": return "中"
        case "en": return "EN"
        case "ja": return "日"
        case "ko": return "한"
        case "": return "⌨"
        default: return String(language.prefix(3)).uppercased()
        }
    }

    var caption: String {
        switch language {
        case "zh": return "中文输入"
        case "en": return "英文输入"
        default: return name
        }
    }

    static func read(_ source: TISInputSource) -> InputSource? {
        func property<T>(_ key: CFString) -> T? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
        }
        guard let id: String = property(kTISPropertyInputSourceID),
              let name: String = property(kTISPropertyLocalizedName) else { return nil }
        return InputSource(id: id, name: name,
                           languages: property(kTISPropertyInputSourceLanguages) ?? [],
                           inputModeID: property(kTISPropertyInputModeID))
    }

    static func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return read(source)
    }
}

struct InputState: Equatable {
    let source: InputSource
    let capsLock: Bool

    var symbol: String { capsLock ? "A" : (source.language == "en" ? "a" : source.symbol) }
    var caption: String { capsLock ? "大写锁定已开启" : (source.language == "en" ? "英文小写" : source.caption) }
    var statusSymbol: String { capsLock ? "⇪" : source.symbol }

    static func capsLockEnabled() -> Bool? {
        CapsLockReader.shared.read()
    }

    static func current() -> InputState? {
        guard let source = InputSource.current(), let capsLock = capsLockEnabled() else { return nil }
        return InputState(source: source, capsLock: capsLock)
    }
}

final class InputSourceMonitor: NSObject {
    private(set) var current: InputState?
    var onChange: ((InputState) -> Void)?
    private var capsLockTimer: Timer?
    private var settlingTimer: Timer?
    private var recoveryTimer: Timer?
    private var reconciliationTimer: Timer?
    private let sourceNotifications: NotificationCenter
    private let workspaceNotifications: NotificationCenter
    private var pending: InputState?
    private var lastObservedCapsLock: Bool?
    private var refreshScheduled = false
    private let readState: () -> InputState?
    private let readCapsLock: () -> Bool?

    init(readState: @escaping () -> InputState? = InputState.current,
         readCapsLock: @escaping () -> Bool? = InputState.capsLockEnabled,
         sourceNotifications: NotificationCenter = DistributedNotificationCenter.default(),
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         reconciliationInterval: TimeInterval = 2) {
        precondition(reconciliationInterval.isFinite && reconciliationInterval > 0)
        self.readState = readState
        self.readCapsLock = readCapsLock
        self.sourceNotifications = sourceNotifications
        self.workspaceNotifications = workspaceNotifications
        super.init()
        current = readState()
        lastObservedCapsLock = current?.capsLock ?? readCapsLock()
        let sourceNotification = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        if let distributed = sourceNotifications as? DistributedNotificationCenter {
            distributed.addObserver(self, selector: #selector(sourceChanged), name: sourceNotification,
                                    object: nil, suspensionBehavior: .deliverImmediately)
        } else {
            sourceNotifications.addObserver(self, selector: #selector(sourceChanged), name: sourceNotification, object: nil)
        }
        // Read only keyboard lock properties, without capturing keystrokes or typed text.
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let capsLock = self.readCapsLock() else {
                self.lastObservedCapsLock = nil
                self.cancelPending()
                self.scheduleRecovery()
                return
            }
            // Compare against the last observation, not the committed state: the
            // latter deliberately lags during settling and caused repeated TIS reads.
            guard capsLock != self.lastObservedCapsLock else { return }
            self.lastObservedCapsLock = capsLock
            self.refresh()
        }
        timer.tolerance = 0.015
        capsLockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        // Reconcile missed source notifications through the same confirmation
        // path, including the keyboard service query in CapsLockReader.
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceNotifications.addObserver(self, selector: #selector(sourceChanged), name: name, object: nil)
        }
        let reconciliation = Timer(timeInterval: reconciliationInterval, repeats: true) { [weak self] _ in
            guard let self, self.pending == nil, self.recoveryTimer == nil else { return }
            self.scheduleRefresh()
        }
        reconciliation.tolerance = reconciliationInterval * 0.1
        reconciliationTimer = reconciliation
        RunLoop.main.add(reconciliation, forMode: .common)
        if current == nil { scheduleRecovery() }
    }

    @objc private func sourceChanged() {
        // TIS and keyboard lock states can change on separate run-loop turns.
        if Thread.isMainThread {
            scheduleRefresh()
        } else {
            DispatchQueue.main.async { [weak self] in self?.scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleRefresh() }
            return
        }
        accept(readState())
    }

    private func accept(_ next: InputState?) {
        guard let next else {
            // A transient TIS failure is not evidence that the old state is still
            // selected. Retry even when the modifier flags have not changed.
            cancelPending()
            scheduleRecovery()
            return
        }
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        lastObservedCapsLock = next.capsLock
        guard next != current else {
            cancelPending()
            return
        }
        // Repeated polling of the same candidate must not keep postponing it.
        guard next != pending else { return }
        cancelPending()
        pending = next
        // Switching languages with Caps Lock may expose a temporary uppercase flag.
        // Confirm uppercase longer; ordinary language changes only wait 100 ms.
        let delay: TimeInterval = next.capsLock ? 0.25 : 0.10
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] timer in
            guard let self, self.settlingTimer === timer else { return }
            // Re-read at the deadline: a final flag change may precede our next poll.
            let latest = self.readState()
            guard let latest, latest == self.pending else {
                self.cancelPending()
                self.accept(latest)
                return
            }
            self.lastObservedCapsLock = latest.capsLock
            self.cancelPending()
            guard latest != self.current else { return }
            self.current = latest
            self.onChange?(latest)
        }
        settlingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleRecovery() {
        guard recoveryTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] timer in
            guard let self, self.recoveryTimer === timer else { return }
            self.recoveryTimer = nil
            self.refresh()
        }
        timer.tolerance = 0.05
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelPending() {
        settlingTimer?.invalidate()
        settlingTimer = nil
        pending = nil
    }

    deinit {
        capsLockTimer?.invalidate()
        recoveryTimer?.invalidate()
        reconciliationTimer?.invalidate()
        cancelPending()
        workspaceNotifications.removeObserver(self)
        sourceNotifications.removeObserver(self)
    }
}
