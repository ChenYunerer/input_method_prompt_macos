import AppKit

final class AppSettings {
    static let defaultTransparency = 0.22
    static let defaultFullScreenTransparency = 0.45
    static let defaultMouseTransparency = 0.5
    private static let transparencyKey = "backgroundTransparency"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var transparency: Double {
        get {
            guard let value = defaults.object(forKey: Self.transparencyKey) as? NSNumber,
                  value.doubleValue.isFinite else { return Self.defaultTransparency }
            return min(1, max(0, value.doubleValue))
        }
        set {
            guard newValue.isFinite else { return }
            defaults.set(min(1, max(0, newValue)), forKey: Self.transparencyKey)
        }
    }

    var switchingPromptEnabled: Bool {
        get { defaults.object(forKey: "switchingPromptEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "switchingPromptEnabled") }
    }

    var switchingPromptDuration: Double {
        get {
            guard let value = defaults.object(forKey: "switchingPromptDuration") as? NSNumber else {
                return Overlay.defaultDuration
            }
            return Overlay.clampedDuration(value.doubleValue)
        }
        set {
            guard newValue.isFinite else { return }
            defaults.set(Overlay.clampedDuration(newValue), forKey: "switchingPromptDuration")
        }
    }

    var fullScreenIndicatorEnabled: Bool {
        get { defaults.object(forKey: "fullScreenIndicatorEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fullScreenIndicatorEnabled") }
    }

    var mouseIndicatorEnabled: Bool {
        get { defaults.object(forKey: "mouseIndicatorEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "mouseIndicatorEnabled") }
    }

    var mouseScale: Double {
        get {
            guard let value = defaults.object(forKey: "mouseScale") as? NSNumber else { return MouseIndicatorLayout.defaultScale }
            return MouseIndicatorLayout.clampedScale(value.doubleValue)
        }
        set {
            guard newValue.isFinite else { return }
            defaults.set(MouseIndicatorLayout.clampedScale(newValue), forKey: "mouseScale")
        }
    }

    var mouseTransparency: Double {
        get {
            guard let value = defaults.object(forKey: "mouseTransparency") as? NSNumber,
                  value.doubleValue.isFinite else { return Self.defaultMouseTransparency }
            return min(1, max(0, value.doubleValue))
        }
        set {
            guard newValue.isFinite else { return }
            defaults.set(min(1, max(0, newValue)), forKey: "mouseTransparency")
        }
    }

    var mouseIdleDelay: Double {
        get {
            guard let value = defaults.object(forKey: "mouseIdleDelay") as? NSNumber else { return MouseIndicator.defaultIdleDelay }
            return MouseIndicator.clampedIdleDelay(value.doubleValue)
        }
        set {
            guard newValue.isFinite else { return }
            defaults.set(MouseIndicator.clampedIdleDelay(newValue), forKey: "mouseIdleDelay")
        }
    }

    var mouseIdleBehavior: MouseIdleBehavior {
        get { defaults.string(forKey: "mouseIdleBehavior").flatMap(MouseIdleBehavior.init(rawValue:)) ?? .hide }
        set { defaults.set(newValue.rawValue, forKey: "mouseIdleBehavior") }
    }

    var mouseOpacity: Double { 1 - mouseTransparency }

    var fullScreenTransparency: Double {
        get {
            guard let value = defaults.object(forKey: "fullScreenTransparency") as? NSNumber,
                  value.doubleValue.isFinite else { return Self.defaultFullScreenTransparency }
            return min(1, max(0, value.doubleValue))
        }
        set {
            guard newValue.isFinite else { return }
            defaults.set(min(1, max(0, newValue)), forKey: "fullScreenTransparency")
        }
    }

    var fullScreenScale: Double {
        get {
            guard let value = defaults.object(forKey: "fullScreenScale") as? NSNumber else {
                return IndicatorMetrics.defaultScale
            }
            return IndicatorMetrics.clampedScale(value.doubleValue)
        }
        set {
            guard newValue.isFinite else { return }
            defaults.set(IndicatorMetrics.clampedScale(newValue), forKey: "fullScreenScale")
        }
    }

    var fullScreenPosition: IndicatorPosition {
        get { defaults.string(forKey: "fullScreenPosition").flatMap(IndicatorPosition.init(rawValue:)) ?? .topRight }
        set { defaults.set(newValue.rawValue, forKey: "fullScreenPosition") }
    }

    var fullScreenBackgroundOpacity: Double { 1 - fullScreenTransparency }
    var backgroundOpacity: Double { 1 - transparency }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let settings: AppSettings
    private let onChange: (Double) -> Void
    private let onPreview: () -> Void
    private let onFullScreenChange: () -> Void
    private let onSwitchingChange: () -> Void
    private let onMouseChange: () -> Void
    private let loginItem: LoginItemManaging
    private let switchingSwitch = NSSwitch()
    private let switchingDurationSeconds = NSTextField(string: "1.0")
    private let switchingDurationStepper = NSStepper()
    private let fullScreenSwitch = NSSwitch()
    private let mouseSwitch = NSSwitch()
    private let mouseSizeSlider = NSSlider(value: 100, minValue: MouseIndicatorLayout.scaleRange.lowerBound * 100,
                                           maxValue: MouseIndicatorLayout.scaleRange.upperBound * 100, target: nil, action: nil)
    private let mouseTransparencySlider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let mouseSizeLabel = NSTextField(labelWithString: "")
    private let mouseTransparencyLabel = NSTextField(labelWithString: "")
    private let mouseIdleSeconds = NSTextField(string: "3")
    private let mouseIdleStepper = NSStepper()
    private let mouseIdlePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mousePreview = MouseIndicatorView()
    private let mousePreviewPointer = NSImageView()
    private let loginSwitch = NSSwitch()
    private let slider = NSSlider(value: 22, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let fullScreenSlider = NSSlider(value: 45, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let fullScreenSizeSlider = NSSlider(value: 100, minValue: 75, maxValue: IndicatorMetrics.scaleRange.upperBound * 100, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "")
    private let fullScreenValueLabel = NSTextField(labelWithString: "")
    private let fullScreenPositionPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fullScreenSizeLabel = NSTextField(labelWithString: "")
    private let preview: PromptView
    private let fullScreenPreview: IndicatorView
    private var fullScreenPreviewCaption: NSTextField?
    private let loginStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let loginSettingsButton = NSButton(title: "打开登录项", target: nil, action: nil)
    private let pages = [NSView(), NSView(), NSView(), NSView()]
    private let sections = NSSegmentedControl(labels: ["切换提示", "全屏常驻", "鼠标跟随", "通用"],
                                              trackingMode: .selectOne, target: nil, action: nil)

    init(settings: AppSettings, loginItem: LoginItemManaging = LoginItemService(),
         onChange: @escaping (Double) -> Void,
         onPreview: @escaping () -> Void,
         onFullScreenChange: @escaping () -> Void = {},
         onSwitchingChange: @escaping () -> Void = {},
         onMouseChange: @escaping () -> Void = {}) {
        self.settings = settings
        self.loginItem = loginItem
        self.onChange = onChange
        self.onPreview = onPreview
        self.onFullScreenChange = onFullScreenChange
        self.onSwitchingChange = onSwitchingChange
        self.onMouseChange = onMouseChange
        preview = PromptView(backgroundOpacity: settings.backgroundOpacity)
        fullScreenPreview = IndicatorView(backgroundOpacity: settings.fullScreenBackgroundOpacity, scale: settings.fullScreenScale)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "中英提示设置"
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        refreshControls()
        refreshLoginStatus()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshControls()
        refreshLoginStatus()
    }

    @discardableResult
    private func label(_ text: String, in parent: NSView, frame: NSRect,
                       size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: secondary ? .regular : .medium)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.frame = frame
        parent.addSubview(label)
        return label
    }

    private func toggle(_ control: NSSwitch, title: String, id: String, action: Selector, in parent: NSView) {
        label(title, in: parent, frame: NSRect(x: 216, y: 270, width: 245, height: 22))
        control.frame = NSRect(x: 470, y: 268, width: 40, height: 26)
        control.target = self
        control.action = action
        control.identifier = NSUserInterfaceItemIdentifier(id)
        control.setAccessibilityLabel(title)
        parent.addSubview(control)
    }

    private func sliderRow(_ control: NSSlider, value: NSTextField, title: String,
                           accessibility: String, id: String, y: CGFloat, action: Selector, in parent: NSView) {
        label(title, in: parent, frame: NSRect(x: 216, y: y, width: 216, height: 20), size: 12)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        value.alignment = .right
        value.frame = NSRect(x: 438, y: y, width: 70, height: 20)
        parent.addSubview(value)
        control.frame = NSRect(x: 213, y: y - 32, width: 298, height: 24)
        control.isContinuous = true
        control.target = self
        control.action = action
        control.identifier = NSUserInterfaceItemIdentifier(id)
        control.setAccessibilityLabel(accessibility)
        parent.addSubview(control)
    }

    @discardableResult
    private func previewCard(in parent: NSView, view: NSView, caption: String) -> NSTextField? {
        let card = NSBox(frame: NSRect(x: 0, y: 64, width: 196, height: 234))
        card.boxType = .custom
        card.borderColor = .separatorColor
        card.borderWidth = 0.5
        card.cornerRadius = 14
        card.fillColor = .controlBackgroundColor
        card.contentViewMargins = .zero
        parent.addSubview(card)
        guard let content = card.contentView else { return nil }
        content.addSubview(view)
        let captionLabel = label(caption, in: content, frame: NSRect(x: 8, y: 14, width: 180, height: 18),
                                 size: 11, secondary: true)
        captionLabel.alignment = .center
        return captionLabel
    }

    private func button(_ title: String, id: String, action: Selector, frame: NSRect, in parent: NSView) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.frame = frame
        parent.addSubview(button)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        sections.frame = NSRect(x: 60, y: 426, width: 440, height: 28)
        sections.segmentStyle = .rounded
        sections.selectedSegment = 0
        sections.target = self
        sections.action = #selector(changeSection)
        sections.identifier = NSUserInterfaceItemIdentifier("settingsSections")
        sections.setAccessibilityLabel("设置分类")
        content.addSubview(sections)
        for (index, page) in pages.enumerated() {
            page.frame = NSRect(x: 24, y: 54, width: 512, height: 346)
            page.identifier = NSUserInterfaceItemIdentifier(["switchingPage", "fullScreenPage", "mousePage", "generalPage"][index])
            page.isHidden = index != 0
            content.addSubview(page)
        }
        buildSwitchingPage(pages[0])
        buildFullScreenPage(pages[1])
        buildMousePage(pages[2])
        buildGeneralPage(pages[3])
        let separator = NSBox(frame: NSRect(x: 24, y: 44, width: 512, height: 1))
        separator.boxType = .separator
        content.addSubview(separator)
        label("更改自动保存", in: content, frame: NSRect(x: 28, y: 16, width: 250, height: 18), size: 11, secondary: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        label(version.map { "中英提示 · \($0)" } ?? "中英提示", in: content,
              frame: NSRect(x: 350, y: 16, width: 184, height: 18), size: 11, secondary: true).alignment = .right
        refreshControls()
        refreshLoginStatus()
    }

    private func buildSwitchingPage(_ page: NSView) {
        label("切换输入法或大小写时，在屏幕中央短暂显示。", in: page,
              frame: NSRect(x: 0, y: 322, width: 512, height: 20), size: 12, secondary: true)
        preview.blendingMode = .withinWindow
        preview.setFrameOrigin(NSPoint(x: 20, y: 54))
        previewCard(in: page, view: preview, caption: "屏幕中央 · 样式预览")
        toggle(switchingSwitch, title: "启用切换提示", id: "switchingPromptEnabled",
               action: #selector(switchingChanged), in: page)
        sliderRow(slider, value: valueLabel, title: "背景透明度", accessibility: "切换提示背景透明度",
                  id: "backgroundTransparency", y: 218, action: #selector(transparencyChanged), in: page)
        label("数值越大越透明，文字保持清晰。", in: page,
              frame: NSRect(x: 216, y: 156, width: 296, height: 18), size: 11, secondary: true)
        label("停留时长", in: page, frame: NSRect(x: 216, y: 112, width: 96, height: 20), size: 12)
        switchingDurationSeconds.frame = NSRect(x: 318, y: 108, width: 64, height: 24)
        switchingDurationSeconds.alignment = .right
        switchingDurationSeconds.identifier = NSUserInterfaceItemIdentifier("switchingPromptDuration")
        switchingDurationSeconds.setAccessibilityLabel("切换提示停留时长（秒）")
        switchingDurationSeconds.toolTip = "0.1–10 秒，精确到 0.1 秒，默认 1 秒。"
        switchingDurationSeconds.delegate = self
        switchingDurationSeconds.target = self
        switchingDurationSeconds.action = #selector(switchingDurationChanged)
        page.addSubview(switchingDurationSeconds)
        switchingDurationStepper.frame = NSRect(x: 386, y: 106, width: 19, height: 28)
        switchingDurationStepper.minValue = Overlay.durationRange.lowerBound
        switchingDurationStepper.maxValue = Overlay.durationRange.upperBound
        switchingDurationStepper.increment = 0.1
        switchingDurationStepper.valueWraps = false
        switchingDurationStepper.identifier = NSUserInterfaceItemIdentifier("switchingPromptDurationStepper")
        switchingDurationStepper.setAccessibilityLabel("调整切换提示停留秒数")
        switchingDurationStepper.target = self
        switchingDurationStepper.action = #selector(switchingDurationStepChanged)
        page.addSubview(switchingDurationStepper)
        label("秒（0.1–10）", in: page, frame: NSRect(x: 411, y: 111, width: 101, height: 20), size: 11, secondary: true)
        label("完整停留时间，不包含淡入淡出。", in: page,
              frame: NSRect(x: 216, y: 78, width: 296, height: 18), size: 11, secondary: true)
        label("下次提示生效，默认 1 秒。", in: page,
              frame: NSRect(x: 216, y: 56, width: 296, height: 18), size: 11, secondary: true)
        button("恢复默认外观", id: "resetSwitchingAppearance", action: #selector(resetTransparency),
               frame: NSRect(x: -6, y: 8, width: 122, height: 32), in: page)
        button("预览切换提示", id: "previewSwitchingPrompt", action: #selector(previewOnScreen),
               frame: NSRect(x: 390, y: 8, width: 128, height: 32), in: page)
    }

    private func buildFullScreenPage(_ page: NSView) {
        label("全屏时持续显示当前输入法，退出全屏后隐藏。", in: page,
              frame: NSRect(x: 0, y: 322, width: 512, height: 20), size: 12, secondary: true)
        fullScreenPreview.blendingMode = .withinWindow
        fullScreenPreview.display(InputState(source: InputSource(id: "preview", name: "中文输入", languages: ["zh"]), capsLock: false))
        fullScreenPreviewCaption = previewCard(in: page, view: fullScreenPreview, caption: "右上角 · 实际大小预览")
        toggle(fullScreenSwitch, title: "启用全屏常驻提示", id: "fullScreenIndicatorEnabled",
               action: #selector(fullScreenChanged), in: page)
        sliderRow(fullScreenSlider, value: fullScreenValueLabel, title: "背景透明度", accessibility: "全屏常驻背景透明度",
                  id: "fullScreenTransparency", y: 218, action: #selector(fullScreenTransparencyChanged), in: page)
        sliderRow(fullScreenSizeSlider, value: fullScreenSizeLabel, title: "提示大小", accessibility: "全屏常驻提示大小",
                  id: "fullScreenScale", y: 134, action: #selector(fullScreenSizeChanged), in: page)
        fullScreenSizeSlider.toolTip = "75%–500%，文字和背景等比例缩放。100% 为默认大小。"
        label("展示位置", in: page, frame: NSRect(x: 216, y: 62, width: 92, height: 20), size: 12)
        fullScreenPositionPicker.frame = NSRect(x: 306, y: 58, width: 204, height: 28)
        fullScreenPositionPicker.addItems(withTitles: IndicatorPosition.allCases.map(\.title))
        fullScreenPositionPicker.target = self
        fullScreenPositionPicker.action = #selector(fullScreenPositionChanged)
        fullScreenPositionPicker.identifier = NSUserInterfaceItemIdentifier("fullScreenPosition")
        fullScreenPositionPicker.setAccessibilityLabel("全屏常驻展示位置")
        page.addSubview(fullScreenPositionPicker)
        label("鼠标移入时自动淡化，移开后恢复。", in: page,
              frame: NSRect(x: 216, y: 16, width: 296, height: 18), size: 11, secondary: true)
        button("恢复默认外观", id: "resetFullScreenAppearance", action: #selector(resetFullScreenAppearance),
               frame: NSRect(x: -6, y: 8, width: 122, height: 32), in: page)
    }

    private func buildMousePage(_ page: NSView) {
        label("跟随显示输入法，隐藏时切换会短暂展示。", in: page,
              frame: NSRect(x: 0, y: 322, width: 512, height: 20), size: 12, secondary: true)
        let sample = mousePreview
        sample.display(InputState(source: InputSource(id: "preview", name: "中文输入", languages: ["zh"]), capsLock: false))
        previewCard(in: page, view: sample, caption: "鼠标旁 · 实际大小预览")
        if let card = sample.superview {
            let pointer = mousePreviewPointer
            pointer.image = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: "鼠标指针示意")
            card.addSubview(pointer)
        }
        toggle(mouseSwitch, title: "启用鼠标跟随提示", id: "mouseIndicatorEnabled",
               action: #selector(mouseChanged), in: page)
        sliderRow(mouseTransparencySlider, value: mouseTransparencyLabel, title: "整体透明度", accessibility: "鼠标提示整体透明度",
                  id: "mouseTransparency", y: 218, action: #selector(mouseTransparencyChanged), in: page)
        mouseTransparencySlider.toolTip = "数值越大越淡，文字和背景一起变化。"
        sliderRow(mouseSizeSlider, value: mouseSizeLabel, title: "提示大小", accessibility: "鼠标提示大小",
                  id: "mouseScale", y: 158, action: #selector(mouseSizeChanged), in: page)
        label("50%–300% · 100% 为默认大小", in: page,
              frame: NSRect(x: 216, y: 104, width: 296, height: 18), size: 11, secondary: true)
        label("静止时长", in: page, frame: NSRect(x: 216, y: 72, width: 112, height: 20), size: 12)
        mouseIdleSeconds.frame = NSRect(x: 338, y: 68, width: 64, height: 24)
        mouseIdleSeconds.alignment = .right
        mouseIdleSeconds.identifier = NSUserInterfaceItemIdentifier("mouseIdleDelay")
        mouseIdleSeconds.setAccessibilityLabel("鼠标静止时长（秒）")
        mouseIdleSeconds.toolTip = "输入 1–60 的整数，默认 3 秒。"
        mouseIdleSeconds.delegate = self
        mouseIdleSeconds.target = self
        mouseIdleSeconds.action = #selector(mouseIdleSecondsChanged)
        page.addSubview(mouseIdleSeconds)
        mouseIdleStepper.frame = NSRect(x: 406, y: 66, width: 19, height: 28)
        mouseIdleStepper.minValue = MouseIndicator.idleDelayRange.lowerBound
        mouseIdleStepper.maxValue = MouseIndicator.idleDelayRange.upperBound
        mouseIdleStepper.increment = 1
        mouseIdleStepper.valueWraps = false
        mouseIdleStepper.identifier = NSUserInterfaceItemIdentifier("mouseIdleDelayStepper")
        mouseIdleStepper.setAccessibilityLabel("调整鼠标静止秒数")
        mouseIdleStepper.target = self
        mouseIdleStepper.action = #selector(mouseIdleStepChanged)
        page.addSubview(mouseIdleStepper)
        label("秒（1–60）", in: page, frame: NSRect(x: 431, y: 71, width: 80, height: 20), size: 11, secondary: true)
        label("静止后", in: page, frame: NSRect(x: 216, y: 36, width: 112, height: 20), size: 12)
        mouseIdlePicker.frame = NSRect(x: 338, y: 32, width: 172, height: 28)
        mouseIdlePicker.addItems(withTitles: MouseIdleBehavior.allCases.map(\.title))
        mouseIdlePicker.identifier = NSUserInterfaceItemIdentifier("mouseIdleBehavior")
        mouseIdlePicker.setAccessibilityLabel("鼠标静止后的行为")
        mouseIdlePicker.target = self
        mouseIdlePicker.action = #selector(mouseIdleChanged)
        page.addSubview(mouseIdlePicker)
        label("再次移动淡入；淡化至当前不透明度的 20%。", in: page,
              frame: NSRect(x: 216, y: 8, width: 296, height: 18), size: 11, secondary: true)
        if SystemCursorVisibility.read() == nil {
            label("当前系统不支持指针隐藏检测，静止设置仍生效。", in: page,
                  frame: NSRect(x: 0, y: 302, width: 512, height: 18), size: 11, secondary: true)
        }
        button("恢复默认外观", id: "resetMouseAppearance", action: #selector(resetMouseAppearance),
               frame: NSRect(x: -6, y: 8, width: 122, height: 32), in: page)
    }

    private func buildGeneralPage(_ page: NSView) {
        label("启动与运行", in: page, frame: NSRect(x: 0, y: 318, width: 512, height: 24), size: 16)
        label("登录时自动启动", in: page, frame: NSRect(x: 16, y: 264, width: 400, height: 22))
        loginSwitch.frame = NSRect(x: 460, y: 262, width: 40, height: 26)
        loginSwitch.identifier = NSUserInterfaceItemIdentifier("loginAtStartup")
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLoginItem)
        loginSwitch.setAccessibilityLabel("登录时自动启动")
        page.addSubview(loginSwitch)
        loginStatusLabel.font = .systemFont(ofSize: 12)
        loginStatusLabel.textColor = .secondaryLabelColor
        loginStatusLabel.frame = NSRect(x: 16, y: 206, width: 464, height: 44)
        page.addSubview(loginStatusLabel)
        loginSettingsButton.bezelStyle = .rounded
        loginSettingsButton.frame = NSRect(x: 10, y: 162, width: 118, height: 32)
        loginSettingsButton.target = self
        loginSettingsButton.action = #selector(openLoginSettings)
        page.addSubview(loginSettingsButton)
        label("应用运行时，可从菜单栏查看当前输入法或打开设置。", in: page,
              frame: NSRect(x: 16, y: 108, width: 480, height: 20), size: 12, secondary: true)
    }

    @objc private func changeSection() {
        for (index, page) in pages.enumerated() { page.isHidden = index != sections.selectedSegment }
    }

    private func refreshLoginStatus(error: Error? = nil) {
        let status = loginItem.status
        loginSwitch.state = status.isRegistered ? .on : .off
        loginSettingsButton.isHidden = status != .requiresApproval && status != .unavailable && error == nil
        loginStatusLabel.textColor = error == nil ? .secondaryLabelColor : .systemRed
        if let error {
            loginStatusLabel.stringValue = "设置未成功，请在系统登录项中检查。"
            loginStatusLabel.toolTip = error.localizedDescription
            return
        }
        loginStatusLabel.toolTip = nil
        switch status {
        case .disabled: loginStatusLabel.stringValue = "已关闭，登录 Mac 后需手动打开。"
        case .enabled: loginStatusLabel.stringValue = "已启用，登录 Mac 后自动在菜单栏运行。"
        case .requiresApproval: loginStatusLabel.stringValue = "等待系统允许，暂未生效。请前往登录项确认。"
        case .unavailable: loginStatusLabel.stringValue = "系统暂未找到登录项，可尝试开启或在系统中检查。"
        }
    }

    @objc private func toggleLoginItem() {
        loginSwitch.isEnabled = false
        defer { loginSwitch.isEnabled = true }
        do {
            try loginItem.setEnabled(loginSwitch.state == .on)
            refreshLoginStatus()
        } catch { refreshLoginStatus(error: error) }
    }

    @objc private func openLoginSettings() { loginItem.openSystemSettings() }

    private func refreshMouseControls() {
        mouseIdleSeconds.integerValue = Int(settings.mouseIdleDelay)
        mouseIdleStepper.doubleValue = settings.mouseIdleDelay
        mouseIdleSeconds.isEnabled = settings.mouseIndicatorEnabled
        mouseIdleStepper.isEnabled = settings.mouseIndicatorEnabled
        mouseIdlePicker.selectItem(at: MouseIdleBehavior.allCases.firstIndex(of: settings.mouseIdleBehavior)!)
        mouseIdlePicker.isEnabled = settings.mouseIndicatorEnabled
        mouseSwitch.state = settings.mouseIndicatorEnabled ? .on : .off
        mouseSizeSlider.isEnabled = settings.mouseIndicatorEnabled
        mouseTransparencySlider.isEnabled = settings.mouseIndicatorEnabled
        mouseSizeSlider.doubleValue = (settings.mouseScale * 100).rounded()
        mouseTransparencySlider.doubleValue = (settings.mouseTransparency * 100).rounded()
        mouseSizeLabel.stringValue = "\(Int(mouseSizeSlider.doubleValue))%"
        mouseTransparencyLabel.stringValue = "\(Int(mouseTransparencySlider.doubleValue))%"
        mousePreview.updateScale(settings.mouseScale)
        mousePreview.alphaValue = settings.mouseOpacity
        let pointerX = (196 - mousePreview.frame.width - 34) / 2
        mousePreviewPointer.frame = NSRect(x: pointerX, y: 154, width: 22, height: 28)
        mousePreview.setFrameOrigin(NSPoint(x: pointerX + 34, y: 144 - mousePreview.frame.height))
    }

    private func refreshControls() {
        refreshMouseControls()
        refreshSwitchingControls()
        refreshFullScreenControls()
    }

    private func refreshSwitchingControls() {
        switchingSwitch.state = settings.switchingPromptEnabled ? .on : .off
        switchingDurationSeconds.stringValue = String(format: "%.1f", settings.switchingPromptDuration)
        switchingDurationStepper.doubleValue = settings.switchingPromptDuration
        switchingDurationSeconds.isEnabled = settings.switchingPromptEnabled
        switchingDurationStepper.isEnabled = settings.switchingPromptEnabled
        slider.isEnabled = settings.switchingPromptEnabled
        slider.doubleValue = (settings.transparency * 100).rounded()
        valueLabel.stringValue = "\(Int(slider.doubleValue))%"
        preview.updateBackgroundOpacity(settings.backgroundOpacity)
    }

    private func refreshFullScreenControls() {
        fullScreenSwitch.state = settings.fullScreenIndicatorEnabled ? .on : .off
        fullScreenSizeSlider.doubleValue = (settings.fullScreenScale * 100).rounded()
        fullScreenSizeSlider.isEnabled = settings.fullScreenIndicatorEnabled
        if let index = IndicatorPosition.allCases.firstIndex(of: settings.fullScreenPosition) {
            fullScreenPositionPicker.selectItem(at: index)
        }
        fullScreenPositionPicker.isEnabled = settings.fullScreenIndicatorEnabled
        fullScreenSizeLabel.stringValue = "\(Int(fullScreenSizeSlider.doubleValue))%"
        fullScreenSlider.doubleValue = (settings.fullScreenTransparency * 100).rounded()
        fullScreenSlider.isEnabled = settings.fullScreenIndicatorEnabled
        fullScreenValueLabel.stringValue = "\(Int(fullScreenSlider.doubleValue))%"
        // Fit oversized samples inside the card; the real on-screen indicator keeps the full size.
        let previewScale = min(settings.fullScreenScale, 164.0 / 36.0)
        fullScreenPreview.updateScale(previewScale)
        fullScreenPreviewCaption?.stringValue = previewScale < settings.fullScreenScale
            ? "缩放预览 · 实际 \(Int(fullScreenSizeSlider.doubleValue))%"
            : "\(settings.fullScreenPosition.title) · 实际大小预览"
        fullScreenPreview.updateBackgroundOpacity(settings.fullScreenBackgroundOpacity)
        fullScreenPreview.setFrameOrigin(NSPoint(x: (196 - fullScreenPreview.frame.width) / 2,
                                                 y: 128 - fullScreenPreview.frame.height / 2))
    }

    @objc private func switchingChanged() {
        settings.switchingPromptEnabled = switchingSwitch.state == .on
        refreshSwitchingControls()
        onSwitchingChange()
    }

    @objc private func mouseChanged() {
        settings.mouseIndicatorEnabled = mouseSwitch.state == .on
        refreshMouseControls()
        onMouseChange()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field === mouseIdleSeconds { mouseIdleSecondsChanged() }
        if let field = notification.object as? NSTextField, field === switchingDurationSeconds { switchingDurationChanged() }
    }

    @objc private func switchingDurationChanged() {
        let text = switchingDurationSeconds.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(text), seconds.isFinite, Overlay.durationRange.contains(seconds) else {
            refreshSwitchingControls()
            return
        }
        setSwitchingDuration(seconds)
    }

    @objc private func switchingDurationStepChanged() {
        setSwitchingDuration(switchingDurationStepper.doubleValue)
    }

    private func setSwitchingDuration(_ seconds: Double) {
        let duration = Overlay.clampedDuration(seconds)
        guard duration != settings.switchingPromptDuration else { refreshSwitchingControls(); return }
        settings.switchingPromptDuration = duration
        refreshSwitchingControls()
        onSwitchingChange()
    }

    @objc private func mouseIdleSecondsChanged() {
        guard let seconds = Double(mouseIdleSeconds.stringValue), seconds.isFinite,
              seconds.rounded() == seconds, MouseIndicator.idleDelayRange.contains(seconds) else {
            refreshMouseControls()
            return
        }
        setMouseIdleSeconds(seconds)
    }

    @objc private func mouseIdleStepChanged() { setMouseIdleSeconds(mouseIdleStepper.doubleValue) }

    private func setMouseIdleSeconds(_ seconds: Double) {
        guard seconds != settings.mouseIdleDelay else { return }
        settings.mouseIdleDelay = seconds
        refreshMouseControls()
        onMouseChange()
    }

    @objc private func mouseIdleChanged() {
        let index = mouseIdlePicker.indexOfSelectedItem
        guard MouseIdleBehavior.allCases.indices.contains(index) else { return }
        settings.mouseIdleBehavior = MouseIdleBehavior.allCases[index]
        refreshMouseControls()
        onMouseChange()
    }

    @objc private func mouseSizeChanged() {
        let value = (mouseSizeSlider.doubleValue / 5).rounded() * 5 / 100
        guard value != settings.mouseScale else { refreshMouseControls(); return }
        settings.mouseScale = value
        refreshMouseControls()
        onMouseChange()
    }

    @objc private func mouseTransparencyChanged() {
        let value = mouseTransparencySlider.doubleValue.rounded() / 100
        guard value != settings.mouseTransparency else { refreshMouseControls(); return }
        settings.mouseTransparency = value
        refreshMouseControls()
        onMouseChange()
    }

    @objc private func resetMouseAppearance() {
        settings.mouseScale = MouseIndicatorLayout.defaultScale
        settings.mouseTransparency = AppSettings.defaultMouseTransparency
        refreshMouseControls()
        onMouseChange()
    }

    @objc private func fullScreenChanged() {
        settings.fullScreenIndicatorEnabled = fullScreenSwitch.state == .on
        refreshFullScreenControls()
        onFullScreenChange()
    }

    @objc private func fullScreenPositionChanged() {
        let index = fullScreenPositionPicker.indexOfSelectedItem
        guard IndicatorPosition.allCases.indices.contains(index) else { return }
        settings.fullScreenPosition = IndicatorPosition.allCases[index]
        refreshFullScreenControls()
        onFullScreenChange()
    }

    @objc private func fullScreenSizeChanged() {
        let value = (fullScreenSizeSlider.doubleValue / 5).rounded() * 5 / 100
        guard value != settings.fullScreenScale else { refreshFullScreenControls(); return }
        settings.fullScreenScale = value
        refreshFullScreenControls()
        onFullScreenChange()
    }

    @objc private func fullScreenTransparencyChanged() {
        let value = fullScreenSlider.doubleValue.rounded() / 100
        guard value != settings.fullScreenTransparency else { refreshFullScreenControls(); return }
        settings.fullScreenTransparency = value
        refreshFullScreenControls()
        onFullScreenChange()
    }

    @objc private func transparencyChanged() {
        let value = slider.doubleValue.rounded() / 100
        guard value != settings.transparency else { refreshSwitchingControls(); return }
        settings.transparency = value
        refreshSwitchingControls()
        onChange(settings.backgroundOpacity)
    }

    @objc private func resetTransparency() {
        settings.transparency = AppSettings.defaultTransparency
        refreshSwitchingControls()
        onChange(settings.backgroundOpacity)
    }

    @objc private func resetFullScreenAppearance() {
        settings.fullScreenTransparency = AppSettings.defaultFullScreenTransparency
        settings.fullScreenScale = IndicatorMetrics.defaultScale
        refreshFullScreenControls()
        onFullScreenChange()
    }

    @objc private func previewOnScreen() {
        window?.makeFirstResponder(nil)
        onPreview()
    }
}
