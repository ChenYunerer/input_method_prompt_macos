import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let currentItem = NSMenuItem(title: "正在读取输入法…", action: nil, keyEquivalent: "")
    private let monitor = InputSourceMonitor()
    private let settings = AppSettings()
    private lazy var overlay = Overlay(backgroundOpacity: settings.backgroundOpacity,
                                       holdDuration: settings.switchingPromptDuration)
    private let fullScreenMonitor = FullScreenMonitor()
    private let mouseIndicator = MouseIndicator()
    private lazy var fullScreenIndicator = FullScreenIndicator(backgroundOpacity: settings.fullScreenBackgroundOpacity, scale: settings.fullScreenScale, position: settings.fullScreenPosition)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        onChange: { [weak self] opacity in self?.overlay.updateBackgroundOpacity(opacity) },
        onPreview: { [weak self] in self?.preview() },
        onFullScreenChange: { [weak self] in self?.applyFullScreenSettings() },
        onSwitchingChange: { [weak self] in self?.applySwitchingSettings() },
        onMouseChange: { [weak self] in self?.applyMouseSettings() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(currentItem)
        menu.addItem(.separator())
        addItem("显示当前输入法", action: #selector(preview), to: menu)
        let settingsItem = addItem("设置…", action: #selector(openSettings), to: menu)
        settingsItem.keyEquivalent = ","
        menu.addItem(.separator())
        addItem("退出中英提示", action: #selector(quit), to: menu)
        statusItem.menu = menu
        fullScreenMonitor.onChange = { [weak self] screens in self?.fullScreenIndicator.updateScreens(screens) }
        fullScreenIndicator.updateState(monitor.current)
        mouseIndicator.updateState(monitor.current)
        applyMouseSettings()
        applyFullScreenSettings()
        updateStatus(monitor.current)
        monitor.onChange = { [weak self] source in
            guard let self else { return }
            self.updateStatus(source)
            self.fullScreenIndicator.updateState(source)
            self.mouseIndicator.updateState(source)
            if self.settings.switchingPromptEnabled { self.overlay.show(source) }
        }
        if settings.switchingPromptEnabled, let source = monitor.current { overlay.show(source) }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    private func applyFullScreenSettings() {
        fullScreenIndicator.updateBackgroundOpacity(settings.fullScreenBackgroundOpacity)
        fullScreenIndicator.updateScale(settings.fullScreenScale)
        fullScreenIndicator.updatePosition(settings.fullScreenPosition)
        fullScreenMonitor.setEnabled(settings.fullScreenIndicatorEnabled)
    }

    private func applyMouseSettings() {
        mouseIndicator.updateIdleDelay(settings.mouseIdleDelay)
        mouseIndicator.updateIdleBehavior(settings.mouseIdleBehavior)
        mouseIndicator.updateAppearance(scale: settings.mouseScale, opacity: settings.mouseOpacity)
        mouseIndicator.setEnabled(settings.mouseIndicatorEnabled)
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func updateStatus(_ state: InputState?) {
        statusItem.button?.title = state?.statusSymbol ?? "⌨"
        statusItem.button?.font = .systemFont(ofSize: 13, weight: .semibold)
        let name = state.map { $0.source.name + ($0.capsLock ? " · 大写锁定" : "") } ?? "无法读取输入法"
        statusItem.button?.toolTip = "中英提示 · \(name)"
        currentItem.title = "当前：\(name)"
    }

    @objc private func preview() {
        if let state = monitor.current { overlay.show(state) }
    }

    @objc private func openSettings() { settingsWindow.present() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    private func applySwitchingSettings() {
        overlay.updateHoldDuration(settings.switchingPromptDuration)
        if !settings.switchingPromptEnabled { overlay.hide() }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfCheck.run())
        }
        if CommandLine.arguments.contains("--diagnose") {
            if let source = InputSource.current() {
                print("当前输入源：\(source.id) | \(source.name) | \(source.languages) | \(source.symbol) | Caps Lock: \(InputState.capsLockEnabled())")
            } else {
                print("无法读取当前输入源")
                exit(1)
            }
            return
        }
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
