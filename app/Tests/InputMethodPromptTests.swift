import AppKit
import Carbon

@main
enum Tests {
    private static var failures = 0

    private static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if !condition { failures += 1 }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--input-state-only") {
            checkInputStateReconciliation()
            checkInputStateLifecycleAndModes()
            checkInputMonitorRecovery()
            checkCapsLockAfterWindowClick()
            checkUnavailableCapsLock()
            checkCapsLockClientRecovery()
            checkCapsLockDeviceDiscovery()
            print("输入状态专项完成，失败数：\(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        if CommandLine.arguments.contains("--caps-lock-only") {
            checkCapsLockReader()
            checkCapsLockAfterWindowClick()
            checkUnavailableCapsLock()
            checkCapsLockClientRecovery()
            checkCapsLockDeviceDiscovery()
            checkCapsLockChanges(InputSource(id: "abc", name: "ABC", languages: ["en"]))
            checkTransientCapsLockDuringSourceSwitch()
            checkSourceBeforeCapsLock()
            checkCancelledCapsLockAndFinalReread()
            print("大写锁定专项完成，失败数：\(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        if CommandLine.arguments.contains("--switching-duration-only") {
            checkSwitchingPromptDuration()
            print("切换提示停留时长专项完成，失败数：\(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        if CommandLine.arguments.contains("--switch-reveal-only") {
            checkMouseInputChangeReveal()
            print("切换临时提示专项完成，失败数：\(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        if CommandLine.arguments.contains("--performance-only") {
            checkRenderingReuse()
            checkFullScreenMonitorLifecycle()
            checkMouseIdlePollingLifecycle()
            checkInputMonitorRecovery()
            print("性能稳定性专项完成，失败数：\(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        if CommandLine.arguments.contains("--fullscreen-only") {
            checkNativeFullScreen()
            exit(failures == 0 ? 0 : 1)
        }
        for language in ["zh-Hans", "zh-Hant", "zh_CN"] {
            let source = InputSource(id: "pinyin", name: "拼音", languages: [language])
            check(source.symbol == "中" && source.caption == "中文输入", "中文识别：\(language)")
        }
        let english = InputSource(id: "abc", name: "ABC", languages: ["en-US"])
        check(english.symbol == "EN" && english.caption == "英文输入", "英文识别")
        check(InputSource(id: "pinyin", name: "拼音", languages: ["zh-Hans", "en"]).symbol == "中",
              "多语言输入源以首选语言为准")
        check(InputSource(id: "ja", name: "日本語", languages: ["ja"]).symbol == "日", "其他语言不冒充英文")
        check(InputSource(id: "unknown", name: "未知", languages: []).symbol == "⌨", "未知语言不冒充英文")
        check(InputSource(id: "hex", name: "Unicode Hex", languages: [""]).caption == "Unicode Hex", "空语言保留输入法名称")
        if SelfCheck.run() != 0 { failures += 1 }
        checkCapsLockChanges(english)
        checkTransientCapsLockDuringSourceSwitch()
        checkSourceBeforeCapsLock()
        checkCancelledCapsLockAndFinalReread()
        checkCapsLockReader()
        checkCapsLockAfterWindowClick()
        checkUnavailableCapsLock()
        checkCapsLockClientRecovery()
        checkCapsLockDeviceDiscovery()
        checkSettingsPersistenceAndControls()
        checkSwitchingPromptDuration()
        checkLoginItemControls()
        checkFullScreenIndicator()
        checkFullScreenControls()
        checkFullScreenHover()
        checkFullScreenPositions()
        checkSettingsSections()
        checkMouseIndicator()
        checkMouseFramePacing()
        checkMouseEdgeStability()
        checkMouseAppearance()
        checkMouseVisibilityAndIdle()
        checkMouseIdleDelay()
        checkMouseInputChangeReveal()
        checkRenderingReuse()
        checkFullScreenMonitorLifecycle()
        checkMouseIdlePollingLifecycle()
        checkInputMonitorRecovery()
        checkInputStateReconciliation()
        checkInputStateLifecycleAndModes()
        if ProcessInfo.processInfo.environment["TEST_CURSOR_VISIBILITY"] == "1" { checkSystemCursorVisibility() }
        if ProcessInfo.processInfo.environment["TEST_FULLSCREEN"] == "1" { checkNativeFullScreen() }
        if ProcessInfo.processInfo.environment["TEST_SYSTEM_INPUT_SWITCH"] == "1" {
            checkSystemSwitch()
        }
        print("全部测试完成，失败数：\(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func checkCapsLockReader() {
        var states: [Bool?]? = [false, false, false]
        let reader = CapsLockReader(readKeyboardStates: { states })
        check(reader.read() == false, "三个键盘均关闭时报告小写")
        // 2026-09-22 16:02:13: only the external keyboard reported true.
        states = [false, false, true]
        check(reader.read() == true, "外接键盘真正开启大写时，不被其他空闲键盘的关闭状态否决")
        states = [true, false, false]
        check(reader.read() == true, "不依赖键盘品牌、顺序或名称")
        states = [false, true, true]
        check(reader.read() == true, "多键盘同时锁定时仍识别大写")
        states = [false, false]
        check(reader.read() == false, "移除锁定键盘后不保留已断开的状态")
        states = [true]
        check(reader.read() == true, "热插拔后读取新键盘状态")
        states = []
        check(reader.read() == nil, "没有可读键盘时返回未知")
        states = nil
        check(reader.read() == nil, "服务枚举失败时返回未知")
        states = [nil]
        check(reader.read() == nil, "缺失的锁定属性不冒充关闭")
        states = [false, nil]
        check(reader.read() == nil, "部分键盘不可读且无已开启键盘时不猜测整体状态")
        states = [nil, true]
        check(reader.read() == true, "已确认开启的键盘足以确认大写，无需猜测其他键盘")
        states = [false, false, false]
        check(reader.read() == false, "服务恢复后重新读取，不缓存失败结果")
        check(CapsLockReader.readBoolean(kCFBooleanTrue) == true &&
              CapsLockReader.readBoolean(kCFBooleanFalse) == false, "接受系统契约中的 CFBoolean 属性")
        for property: CFTypeRef? in [nil, NSNumber(value: 1), NSNumber(value: 0), "true" as CFString] {
            check(CapsLockReader.readBoolean(property) == nil, "缺失或非布尔属性不强制转换为锁定状态")
        }

        // Captured while the user confirmed Caps Lock was off. The old reader
        // accepted both legacy flags being true; all keyboard services were off.
        let eventCaps = true
        let legacyLock = true
        check(eventCaps && legacyLock && reader.read() == false,
              "16:02:38 实测：两个旧接口同时误报开启，键盘属性全关时仍返回关闭")
    }

    private static func checkCapsLockAfterWindowClick() {
        var states: [Bool?] = [false, false, false]
        var source = InputSource(id: "abc", name: "ABC", languages: ["en"])
        let reader = CapsLockReader(readKeyboardStates: { states })
        let notifications = NotificationCenter()
        let monitor = InputSourceMonitor(readState: {
            guard let capsLock = reader.read() else { return nil }
            return InputState(source: source, capsLock: capsLock)
        }, readCapsLock: { reader.read() }, sourceNotifications: NotificationCenter(), workspaceNotifications: notifications)
        var symbols: [String] = []
        monitor.onChange = { symbols.append($0.symbol) }

        // The real 16:02:12 trace contains a 53 ms Caps pulse before activation;
        // language switching also produced pulses shorter than 125 ms.
        states[2] = true
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        states[2] = false
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(symbols.isEmpty, "键盘服务短暂开启后恢复时，不将中英切换的中间态显示为 A")
        states[2] = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        check(symbols == ["A"], "英文下长按中英键开启真实大写，正常提示 A")
        // Actual turn-off included a brief false -> true bounce before settling.
        states[2] = false
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        states[2] = true
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.07))
        states[2] = false
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.30))
        check(symbols == ["A", "a"], "短按中英键关闭大写的短暂反跳合并后只恢复一次 a")
        // After the real turn-off, event flags and legacy IOHID lock both became
        // true while all service properties stayed false. Neither legacy API is
        // an input to this reader, including on every restored P0 refresh path.
        monitor.refresh()
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            notifications.post(name: name, object: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            check(symbols == ["A", "a"], "关闭大写后的生命周期刷新不重发 A：\(name.rawValue)")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(2.3))
        check(symbols == ["A", "a"] && monitor.current?.capsLock == false,
              "关闭后键盘属性持续 3.8 秒为关，周期校准与生命周期刷新不重发大写")
        source = InputSource(id: "pinyin", name: "拼音", languages: ["zh-Hans"])
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(symbols == ["A", "a", "中"], "焦点切换同时变更输入源时，仍展示正确语言")
        states[0] = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        check(symbols.last == "A" && symbols.count == 4, "换另一键盘真正开启锁定时仍能发现变化")
        states[0] = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(symbols.last == "中" && symbols.count == 5, "关闭真实锁定后恢复中文")
    }

    private static func checkCapsLockClientRecovery() {
        var time: TimeInterval = 0
        var creations = 0
        var stale = false
        var freshStates: [Bool?]? = [false, false, false]
        weak var firstClient: NSObject?
        var reader: CapsLockReader? = CapsLockReader(makeKeyboardQuery: {
            creations += 1
            let generation = creations
            let client = NSObject()
            if generation == 1 { firstClient = client }
            return {
                withExtendedLifetime(client) {
                    if generation == 1 { return stale ? [nil, false, nil] : [false, false, false] }
                    return freshStates
                }
            }
        }, now: { time })
        check(reader?.read() == false && creations == 1, "正常查询复用客户端")
        stale = true
        time = 20
        check(reader?.read() == false && creations == 2,
              "实测旧连接返回 [nil,false,nil] 时重建连接并在本次读取恢复")
        check(firstClient == nil, "替换查询闭包时释放失效客户端")
        for _ in 0..<20 { _ = reader?.read() }
        check(creations == 2, "恢复后的健康客户端不会在每次轮询重建")
        freshStates = nil
        time = 20.2
        check(reader?.read() == nil && creations == 2, "连接持续失败时在冷却期返回未知")
        time = 20.5
        check(reader?.read() == nil && creations == 3, "到达重试期限只重新创建一次")
        for _ in 0..<5 { time += 0.08; _ = reader?.read() }
        check(creations == 3, "80 毫秒轮询不导致反复重连")
        freshStates = [false, false, true]
        check(reader?.read() == true && creations == 3, "冷却期仍读取现有客户端，真实大写恢复可立即识别")
        reader = nil

        for unavailable: [Bool?]? in [nil, [], [nil, false, nil]] {
            var attempts = 0
            var clock: TimeInterval = 0
            let recovery = CapsLockReader(makeKeyboardQuery: {
                attempts += 1
                let generation = attempts
                return { generation == 1 ? unavailable : [false] }
            }, now: { clock })
            check(recovery.read() == nil && attempts == 1, "启动时不可用不猜测状态或立即反复创建客户端")
            clock = 0.5
            check(recovery.read() == false && attempts == 2, "枚举失败、空列表或部分属性失效均可重建恢复")
        }

        var source = InputSource(id: "abc", name: "ABC", languages: ["en"])
        var oldConnectionExpired = false
        var currentCaps = false
        var clientCount = 0
        var clock: TimeInterval = 0
        let recovery = CapsLockReader(makeKeyboardQuery: {
            clientCount += 1
            let generation = clientCount
            return { generation == 1 && oldConnectionExpired ? [nil, false, nil] : [false, false, currentCaps] }
        }, now: { clock })
        let monitor = InputSourceMonitor(readState: {
            recovery.read().map { InputState(source: source, capsLock: $0) }
        }, readCapsLock: { recovery.read() }, sourceNotifications: NotificationCenter(),
           workspaceNotifications: NotificationCenter())
        var symbols: [String] = []
        monitor.onChange = { symbols.append($0.symbol) }
        oldConnectionExpired = true
        source = InputSource(id: "pinyin", name: "拼音", languages: ["zh-Hans"])
        clock = 100
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(symbols == ["中"] && clientCount == 2, "长时间运行后旧服务失效不会永久阻断中英切换提示")
        currentCaps = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        check(symbols == ["中", "A"], "重建后仍识别真实大写锁定")
        currentCaps = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(symbols == ["中", "A", "中"], "重建后关闭大写仍正确恢复输入法")
    }

    private static func checkCapsLockDeviceDiscovery() {
        final class KeyboardService {
            var caps: Bool?
            init(_ caps: Bool?) { self.caps = caps }
        }
        let builtIn = KeyboardService(false)
        let bluetooth = KeyboardService(true)
        var keyboards = [builtIn]
        var time: TimeInterval = 0
        var creations = 0
        let reader = CapsLockReader(makeKeyboardQuery: {
            creations += 1
            // A client's service list stays valid but omits later connections.
            let capturedServices = keyboards
            return { capturedServices.map { $0.caps } }
        }, now: { time })
        check(reader.read() == false && creations == 1, "只有内置键盘时读取初始列表")
        keyboards.append(bluetooth)
        time = 0.49
        check(reader.read() == false && creations == 1, "列表刷新间隔内复用客户端，不每 80 毫秒重建")
        time = 0.5
        check(reader.read() == true && creations == 2,
              "旧客户端只返回有效 false 时仍重新发现蓝牙键盘，不等待 nil 才恢复")
        for _ in 0..<20 { _ = reader.read() }
        check(creations == 2, "到期后只重建一次，多次查询共用新的客户端")
        bluetooth.caps = false
        check(reader.read() == false && creations == 2, "设备列表刷新间隔内仍实时读取大小写变化")
        bluetooth.caps = true
        keyboards = [builtIn]
        time = 1
        check(reader.read() == false && creations == 3,
              "移除键盘后清除旧列表内仍为 true 的服务，不保留幽灵大写")
        keyboards.append(bluetooth)
        time = 1000
        check(reader.read() == true && creations == 4, "长时间休眠后只刷新一次，不追补所有错过的周期")
        time = 1000.2
        _ = reader.read()
        check(creations == 4, "恢复后按当前时间设置新期限，避免连续刷新")

        var connected = [builtIn]
        let start = ProcessInfo.processInfo.systemUptime
        let liveReader = CapsLockReader(makeKeyboardQuery: {
            let capturedServices = connected
            return { capturedServices.map { $0.caps } }
        }, now: { ProcessInfo.processInfo.systemUptime - start })
        let source = InputSource(id: "abc", name: "ABC", languages: ["en"])
        let monitor = InputSourceMonitor(readState: {
            liveReader.read().map { InputState(source: source, capsLock: $0) }
        }, readCapsLock: { liveReader.read() }, sourceNotifications: NotificationCenter(),
           workspaceNotifications: NotificationCenter())
        var symbols: [String] = []
        monitor.onChange = { symbols.append($0.symbol) }
        connected.append(bluetooth)
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        check(symbols == ["A"], "蓝牙键盘接入后无需通知或重新启动即可确认真实大写")
        bluetooth.caps = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        check(symbols == ["A", "a"], "发现蓝牙键盘后关闭大写仍正常提示")
        builtIn.caps = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        check(symbols == ["A", "a", "A"], "设备列表刷新不影响内置键盘大写识别")
    }

    private static func checkUnavailableCapsLock() {
        let source = InputSource(id: "abc", name: "ABC", languages: ["en"])
        var locked: Bool? = false
        var reads = 0
        let monitor = InputSourceMonitor(readState: {
            reads += 1
            return locked.map { InputState(source: source, capsLock: $0) }
        }, readCapsLock: { locked }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
        var symbols: [String] = []
        monitor.onChange = { symbols.append($0.symbol) }
        locked = true
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        locked = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.30))
        check(symbols.isEmpty && monitor.current?.capsLock == false,
              "确认窗口内锁定状态不可用时取消待显示的大写")
        let readsBefore = reads
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        check(reads - readsBefore <= 2, "锁定读取失败只低频恢复，不每次轮询读取 TIS")
        locked = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        check(symbols == ["A"], "锁定接口恢复后可确认真实大写状态")
    }

    private static func checkSettingsPersistenceAndControls() {
        let suite = "InputMethodPrompt.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        check(abs(settings.backgroundOpacity - 0.78) < 0.001, "首次使用保留现有的背景透明度")
        let overlay = Overlay(backgroundOpacity: settings.backgroundOpacity)
        var previewCount = 0
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { overlay.updateBackgroundOpacity($0) },
            onPreview: { previewCount += 1 })
        guard let content = controller.window?.contentView,
              let slider = descendants(of: content).compactMap({ $0 as? NSSlider }).first else {
            check(false, "设置窗口包含透明度滑块")
            return
        }
        slider.doubleValue = 65
        slider.sendAction(slider.action, to: slider.target)
        let reloaded = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        check(abs(reloaded.transparency - 0.65) < 0.001, "滑块设置自动保存，新实例可读回")
        if let view = overlay.panel.contentView as? PromptView,
           let data = view.maskImage?.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: data),
           let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2) {
            check(abs(center.alphaComponent - 0.35) < 0.01, "设置即时更新真实浮层的背景遮罩")
        } else { check(false, "读取浮层遮罩") }
        let buttons = descendants(of: content).compactMap { $0 as? NSButton }
        buttons.first { $0.identifier?.rawValue == "previewSwitchingPrompt" }?.performClick(nil)
        check(previewCount == 1, "屏幕预览按钮连接到浮层")
        buttons.first { $0.identifier?.rawValue == "resetSwitchingAppearance" }?.performClick(nil)
        check(abs(settings.transparency - 0.22) < 0.001 && slider.doubleValue == 22,
              "恢复默认同时更新保存值和滑块")
        slider.doubleValue = 100
        slider.sendAction(slider.action, to: slider.target)
        check(settings.backgroundOpacity == 0, "100% 透明时允许只保留文字")
        slider.doubleValue = 0
        slider.sendAction(slider.action, to: slider.target)
        check(settings.backgroundOpacity == 1, "0% 透明时保留完整系统材质")
        controller.close()
    }

    private static func checkSwitchingPromptDuration() {
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        let suite = "InputMethodPrompt.SwitchingDuration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let state = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        let overlay = Overlay(holdDuration: settings.switchingPromptDuration)
        var changes = 0
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { _ in }, onPreview: { overlay.show(state) }, onSwitchingChange: {
                changes += 1
                overlay.updateHoldDuration(settings.switchingPromptDuration)
                if !settings.switchingPromptEnabled { overlay.hide() }
            })
        let views = descendants(of: controller.window!.contentView!)
        let seconds = views.first { $0.identifier?.rawValue == "switchingPromptDuration" } as! NSTextField
        let stepper = views.first { $0.identifier?.rawValue == "switchingPromptDurationStepper" } as! NSStepper
        let toggle = views.first { $0.identifier?.rawValue == "switchingPromptEnabled" } as! NSSwitch
        let preview = views.first { $0.identifier?.rawValue == "previewSwitchingPrompt" } as! NSButton
        func input(_ text: String) {
            seconds.stringValue = text
            seconds.sendAction(seconds.action, to: seconds.target)
        }
        check(settings.switchingPromptDuration == 1 && overlay.holdDuration == 1 &&
              seconds.doubleValue == 1 && stepper.doubleValue == 1,
              "无停留时长配置时默认1秒，控件和实际浮层一致")
        check(stepper.minValue == 0.1 && stepper.maxValue == 10 && stepper.increment == 0.1,
              "停留时长支持0.1至10秒，步进0.1秒")
        overlay.show(state)
        wait(0.8)
        check(overlay.panel.isVisible && overlay.panel.alphaValue == 1, "默认停留不再沿用旧0.5秒")
        wait(0.65)
        check(!overlay.panel.isVisible, "默认1秒停留后淡出隐藏")

        input("0.4")
        let reloaded = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        check(reloaded.switchingPromptDuration == 0.4 && stepper.doubleValue == 0.4 &&
              overlay.holdDuration == 0.4 && changes == 1 && !overlay.panel.isVisible,
              "输入秒数持久化并同步运行时，修改配置本身不弹窗")
        let restarted = Overlay(holdDuration: reloaded.switchingPromptDuration)
        check(restarted.holdDuration == 0.4, "重建浮层使用已保存时长")
        preview.performClick(nil)
        wait(0.03)
        input("1.4")
        wait(0.8)
        check(!overlay.panel.isVisible, "淡入中修改时长不改变正在展示的一轮")
        preview.performClick(nil)
        wait(0.85)
        check(overlay.panel.isVisible && overlay.panel.alphaValue == 1, "下次预览使用新停留时长")
        overlay.show(state)
        wait(0.85)
        check(overlay.panel.isVisible && overlay.panel.alphaValue == 1, "连续触发重新计时，旧截止不能提前隐藏")
        wait(0.85)
        check(!overlay.panel.isVisible, "连续触发后按新截止淡出完成")

        stepper.doubleValue = 0.2
        stepper.sendAction(stepper.action, to: stepper.target)
        check(seconds.doubleValue == 0.2 && settings.switchingPromptDuration == 0.2 && overlay.holdDuration == 0.2,
              "步进器更新输入框、保存值和实际浮层")
        overlay.show(state)
        wait(0.40)
        let alpha = overlay.panel.alphaValue
        check(alpha > 0 && alpha < 1, "自定义短停留后仍执行淡出动画")
        input("0.8")
        overlay.show(state)
        check(overlay.panel.alphaValue == alpha, "淡出中重新触发从当前透明度淡入")
        wait(0.45)
        check(overlay.panel.isVisible && overlay.panel.alphaValue == 1, "旧淡出不会隐藏使用新时长的提示")
        overlay.hide()

        input(" 1.26 ")
        check(seconds.doubleValue == 1.3 && settings.switchingPromptDuration == 1.3, "输入自动取整到0.1秒")
        let beforeUnchanged = changes
        input("1.30")
        controller.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: seconds))
        check(changes == beforeUnchanged && seconds.stringValue == "1.3", "相同数值和重复结束编辑不重复回调")
        seconds.stringValue = "2.5"
        controller.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: seconds))
        check(settings.switchingPromptDuration == 2.5 && stepper.doubleValue == 2.5, "失去编辑焦点保存秒数")
        for invalid in ["", "abc", "0", "-1", "10.1", "nan", "inf"] {
            let before = changes
            input(invalid)
            check(settings.switchingPromptDuration == 2.5 && seconds.doubleValue == 2.5 && changes == before,
                  "无效停留时长恢复已有值且不回调：\(invalid)")
        }
        (views.first { $0.identifier?.rawValue == "resetSwitchingAppearance" } as! NSButton).performClick(nil)
        check(settings.switchingPromptDuration == 2.5 && settings.mouseIdleDelay == 3 &&
              MouseIndicator.inputChangeDuration == 0.5, "外观重置保留时长，鼠标计时规则独立")
        overlay.show(state)
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        check(!seconds.isEnabled && !stepper.isEnabled && !overlay.panel.isVisible && settings.switchingPromptDuration == 2.5,
              "关闭切换提示隐藏浮层、禁用时长控件且保留数值")
        preview.performClick(nil)
        check(overlay.panel.isVisible && overlay.holdDuration == 2.5, "关闭自动提示仍可按保存时长手动预览")
        overlay.hide()
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        check(seconds.isEnabled && stepper.isEnabled && seconds.doubleValue == 2.5, "重新开启恢复控件并保留时长")
        settings.switchingPromptDuration = .infinity
        check(settings.switchingPromptDuration == 2.5, "非有限值不会覆盖偏好")
        defaults.set("broken", forKey: "switchingPromptDuration")
        check(settings.switchingPromptDuration == 1, "错误类型的时长配置回到默认1秒")
        defaults.set(Double.nan, forKey: "switchingPromptDuration")
        check(settings.switchingPromptDuration == 1, "非有限时长配置回到默认1秒")
        settings.switchingPromptDuration = 100
        check(settings.switchingPromptDuration == 10, "存储时长上限10秒")
        settings.switchingPromptDuration = 0
        check(settings.switchingPromptDuration == 0.1, "存储时长下限0.1秒")
        controller.close()
    }

    private static func checkLoginItemControls() {
        let suite = "InputMethodPrompt.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItem()
        let controller = SettingsWindowController(settings: AppSettings(defaults: defaults),
            loginItem: service, onChange: { _ in }, onPreview: {})
        guard let content = controller.window?.contentView,
              let toggle = descendants(of: content).compactMap({ $0 as? NSSwitch }).first(where: { $0.identifier?.rawValue == "loginAtStartup" }) else {
            check(false, "设置窗口包含自动启动开关")
            return
        }
        check(toggle.state == .off && service.changeCount == 0, "打开设置不自动注册登录项")
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        check(service.status == .enabled && toggle.state == .on, "打开开关注册自动启动")
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        check(service.status == .disabled && toggle.state == .off, "关闭开关注销自动启动")

        service.needsApproval = true
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        let labels = descendants(of: content).compactMap { $0 as? NSTextField }
        let systemButton = descendants(of: content).compactMap { $0 as? NSButton }.first { $0.title == "打开登录项" }
        check(service.status == .requiresApproval && systemButton?.isHidden == false &&
              labels.contains { $0.stringValue.contains("暂未生效") }, "待系统允许时明确提示尚未生效")
        systemButton?.performClick(nil)
        check(service.openCount == 1, "登录项按钮连接到系统设置入口")
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        check(service.status == .disabled, "等待允许期间也能取消自动启动")

        service.failure = NSError(domain: "LoginItemTest", code: 1)
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        check(toggle.state == .off && toggle.isEnabled &&
              labels.contains { $0.stringValue.contains("设置未成功") }, "注册失败恢复真实状态并显示错误")
        service.failure = nil
        service.status = .enabled
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        check(toggle.state == .on, "从系统设置返回时同步真实登录项状态")
        controller.close()
    }

    private static func checkFullScreenIndicator() {
        let screen = CGRect(x: 1512, y: -172, width: 2560, height: 1440)
        check(FullScreenDetection.coversScreen(screen, screen: screen, safeTop: 0), "副屏负坐标全屏窗口识别")
        let notched = CGRect(x: 0, y: 0, width: 1512, height: 982)
        check(FullScreenDetection.coversScreen(CGRect(x: 0, y: 32, width: 1512, height: 950),
                                               screen: notched, safeTop: 32), "刘海安全区域全屏识别")
        check(FullScreenDetection.coversScreen(CGRect(x: 0, y: 37, width: 1512, height: 945),
                                               screen: notched, safeTop: 32, reservedTop: 32),
              "真实刘海屏全屏顶部系统预留区域识别")
        check(!FullScreenDetection.coversScreen(CGRect(x: 0, y: 38, width: 1512, height: 870),
                                                screen: notched, safeTop: 32, reservedTop: 38), "普通最大化窗口不当作全屏")
        typealias Window = FullScreenDetection.Window
        let content = Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -91, width: 2560, height: 1359))
        let toolbar = Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -172, width: 2560, height: 81))
        let overlappingToolbar = Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -172, width: 2560, height: 153))
        let otherDisplay = Window(ownerPID: 78748, frame: CGRect(x: 0, y: 38, width: 905, height: 585))
        check(FullScreenDetection.isFullScreen([toolbar, otherDisplay, overlappingToolbar, content],
                                               screen: screen, safeTop: 0), "真实Chrome全屏工具栏与内容拆窗识别")
        check(FullScreenDetection.isFullScreen([content, toolbar], screen: screen, safeTop: 0),
              "工具栏与内容前后顺序不影响连续区域识别")
        check(FullScreenDetection.isFullScreen([Window(ownerPID: 1, frame: screen)], screen: screen, safeTop: 0),
              "单窗口全屏识别保持兼容")
        check(!FullScreenDetection.isFullScreen([content], screen: screen, safeTop: 0),
              "缺少顶部区域不能凭空当作全屏")
        check(!FullScreenDetection.isFullScreen([Window(ownerPID: 2, frame: toolbar.frame), content],
                                                screen: screen, safeTop: 0), "不同进程窗口不得拼接")
        check(!FullScreenDetection.isFullScreen([
            Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -172, width: 2560, height: 70)), content
        ], screen: screen, safeTop: 0), "工具栏与内容存在间隙不得拼接")
        check(!FullScreenDetection.isFullScreen([
            Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -172, width: 1280, height: 81)), content
        ], screen: screen, safeTop: 0), "非全宽工具栏不得补齐整屏")
        let normal = Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -91, width: 2560, height: 1280))
        check(!FullScreenDetection.isFullScreen([toolbar, normal], screen: screen, safeTop: 0),
              "底部仍有Dock空隙的窗口不当作全屏")
        check(!FullScreenDetection.isFullScreen([content, Window(ownerPID: 90125, frame: screen)],
                                                screen: screen, safeTop: 0), "同进程后台大窗口不得补齐前台普通窗口")
        check(!FullScreenDetection.isFullScreen([normal, Window(ownerPID: 2, frame: screen)],
                                                screen: screen, safeTop: 0), "前台普通窗口遮挡后台全屏时不展示")
        check(FullScreenDetection.isFullScreen([
            Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -172, width: 2560, height: 40)), content,
            Window(ownerPID: 90125, frame: CGRect(x: 1512, y: -132, width: 2560, height: 41))
        ], screen: screen, safeTop: 0), "多个顶部条带按连续关系拼接而不依赖列表顺序")
        let target = IndicatorScreen(id: 123, frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
                                     safeTop: 32, safeRight: 0)
        check(target.indicatorFrame().maxX == -18 && target.indicatorFrame().maxY == 932,
              "常驻标识定位屏幕右上角并避开刘海")
        var screens: [IndicatorScreen] = []
        let indicator = FullScreenIndicator(backgroundOpacity: 0.55)
        let monitor = FullScreenMonitor(readScreens: { screens })
        monitor.onChange = { indicator.updateScreens($0) }
        let chinese = InputState(source: InputSource(id: "pinyin", name: "拼音", languages: ["zh"]), capsLock: false)
        let english = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        indicator.updateState(chinese)
        monitor.setEnabled(true)
        check(indicator.panels.isEmpty, "普通桌面不显示常驻标识")
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        screens = [target]
        monitor.refresh()
        guard let panel = indicator.panels[target.id] else {
            check(false, "进入全屏无需切换输入法即可展示状态")
            return
        }
        let label = panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first
        check(panel.isVisible && label?.stringValue == "中", "进入全屏立即显示已有中文状态")
        check(!panel.canBecomeKey && !panel.canBecomeMain && panel.ignoresMouseEvents &&
              foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
              "常驻标识不抢焦点且鼠标穿透")
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        check(panel.isVisible, "常驻标识不会随中央提示超时消失")
        indicator.updateState(english)
        check(label?.stringValue == "a", "常驻标识同步英文状态")
        indicator.updateState(InputState(source: english.source, capsLock: true))
        check(label?.stringValue == "A", "常驻标识同步大写锁定")
        let originalFrame = panel.frame
        indicator.updateScale(5)
        check(indicator.panels[target.id] === panel && panel.frame.size == NSSize(width: 180, height: 180) &&
              panel.frame.maxX == originalFrame.maxX && panel.frame.maxY == originalFrame.maxY,
              "放大到500%复用窗口并保持右上角边距")
        check(label?.font?.pointSize == 90 && label?.stringValue == "A" &&
              (panel.contentView as? NSVisualEffectView)?.maskImage?.size == NSSize(width: 180, height: 180),
              "文字与材质同步缩放并保留当前状态")
        indicator.updateScale(0.75)
        check(panel.frame.size == NSSize(width: 27, height: 27) && label?.font?.pointSize == 13.5,
              "缩小到75%时窗口和文字比例一致")
        indicator.updateBackgroundOpacity(0)
        indicator.updateScale(1.5)
        let view = panel.contentView as? NSVisualEffectView
        if let data = view?.maskImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) {
            check(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent == 0 &&
                  label?.alphaValue == 1, "常驻提示透明度只改变背景")
        } else { check(false, "常驻标识材质遮罩可读取") }
        monitor.setEnabled(false)
        check(indicator.panels.isEmpty && !panel.isVisible, "关闭开关立即隐藏已有常驻窗口")
        monitor.setEnabled(true)
        check(indicator.panels[target.id]?.isVisible == true &&
              indicator.panels[target.id]?.frame.size == NSSize(width: 54, height: 54),
              "全屏期间重新开启保留大小及当前状态")
        screens = []
        monitor.refresh()
        check(indicator.panels.isEmpty, "退出全屏清除常驻标识")
        screens = [target, IndicatorScreen(id: 124, frame: screen, safeTop: 0, safeRight: 0)]
        monitor.refresh()
        check(indicator.panels.count == 2, "多个全屏显示器分别显示标识")
        indicator.updateState(nil)
        check(indicator.panels.isEmpty, "无有效输入状态不显示伪造标识")
        monitor.setEnabled(false)
    }

    private static func checkFullScreenControls() {
        let suite = "InputMethodPrompt.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        var changes = 0
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { _ in }, onPreview: {}, onFullScreenChange: { changes += 1 })
        guard let content = controller.window?.contentView,
              let toggle = descendants(of: content).first(where: { $0.identifier?.rawValue == "fullScreenIndicatorEnabled" }) as? NSSwitch,
              let slider = descendants(of: content).first(where: { $0.identifier?.rawValue == "fullScreenTransparency" }) as? NSSlider,
              let sizeSlider = descendants(of: content).first(where: { $0.identifier?.rawValue == "fullScreenScale" }) as? NSSlider else {
            check(false, "设置包含全屏常驻提示开关和独立透明度")
            return
        }
        check(toggle.state == .on && slider.doubleValue == 45 && sizeSlider.doubleValue == 100 && changes == 0,
              "首次默认开启全屏提示，背景透明度45%，读取不触发修改")
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        let reloaded = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        check(!reloaded.fullScreenIndicatorEnabled && !slider.isEnabled && !sizeSlider.isEnabled && changes == 1,
              "关闭全屏提示即时回调并持久保存，禁用独立滑块")
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        slider.doubleValue = 72
        slider.sendAction(slider.action, to: slider.target)
        check(abs(reloaded.fullScreenTransparency - 0.72) < 0.001 && settings.transparency == 0.22 && changes == 3,
              "常驻透明度独立保存，不改变中央提示")
        sizeSlider.doubleValue = 153
        sizeSlider.sendAction(sizeSlider.action, to: sizeSlider.target)
        check(reloaded.fullScreenScale == 1.55 && sizeSlider.doubleValue == 155 && sizeSlider.isEnabled && changes == 4,
              "大小滑块按5%步进即时回调并持久保存")
        check(settings.fullScreenTransparency == 0.72 && settings.transparency == 0.22,
              "修改大小不改变两种透明度")
        descendants(of: content).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "resetSwitchingAppearance" }?.performClick(nil)
        check(settings.fullScreenScale == 1.55, "重置中央透明度不改变常驻大小")
        sizeSlider.doubleValue = 500
        sizeSlider.sendAction(sizeSlider.action, to: sizeSlider.target)
        let sample = descendants(of: content).compactMap { $0 as? IndicatorView }.first
        check(sizeSlider.maxValue == 500 && reloaded.fullScreenScale == 5 && sizeSlider.doubleValue == 500,
              "滑块支持500%并保存实际比例")
        check(sample.map { $0.frame.width <= 172.01 && $0.frame.minX >= 0 } == true &&
              descendants(of: content).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "缩放预览 · 实际 500%" },
              "500%样式预览适配卡片且明确标注真实比例")
        settings.fullScreenScale = 0
        check(reloaded.fullScreenScale == 0.75, "保存大小下限保护")
        settings.fullScreenScale = 6
        settings.fullScreenScale = .nan
        check(reloaded.fullScreenScale == 5, "保存大小上限保护且拒绝非有限值")
        defaults.set(Double.infinity, forKey: "fullScreenScale")
        check(settings.fullScreenScale == 1, "损坏的大小配置回到默认值")
        settings.fullScreenScale = 1.55
        check(settings.fullScreenIndicatorEnabled && settings.fullScreenTransparency == 0.72,
              "原重置按钮保持常驻开关和独立透明度")
        // Render our own settings view for visual review, without capturing other applications.
        content.layoutSubtreeIfNeeded()
        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/settings-preview.png"))
        }
        controller.close()
    }

    private static func checkFullScreenPositions() {
        let screen = IndicatorScreen(id: 789, frame: NSRect(x: -1512, y: -200, width: 1512, height: 982),
                                     safeTop: 32, safeRight: 20, safeLeft: 10, safeBottom: 8)
        var origins = Set<String>()
        let safeBounds = NSRect(x: -1484, y: -174, width: 1446, height: 906)
        for position in IndicatorPosition.allCases {
            let frame = screen.indicatorFrame(scale: 5, position: position)
            origins.insert(NSStringFromPoint(frame.origin))
            check(safeBounds.contains(frame) && frame.size == NSSize(width: 180, height: 180),
                  "500%在\(position.title)保持屏幕安全边距")
        }
        check(origins.count == 9 && screen.indicatorFrame(position: .topLeft).minX == -1484 &&
              screen.indicatorFrame(position: .bottomRight).minY == -174,
              "九种位置独立且兼容副屏负坐标")
        let indicator = FullScreenIndicator(backgroundOpacity: 0.5, position: .topRight, readMouseLocation: { .zero })
        indicator.updateState(InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false))
        indicator.updateScreens([screen])
        let panel = indicator.panels[screen.id]
        indicator.updatePosition(.bottomLeft)
        check(indicator.panels[screen.id] === panel && panel?.frame == screen.indicatorFrame(position: .bottomLeft),
              "修改位置即时移动现有窗口")
        indicator.updateScale(5)
        check(panel?.frame == screen.indicatorFrame(scale: 5, position: .bottomLeft), "放大后保留所选位置")
        indicator.updateScreens([])
        indicator.updateScreens([screen])
        check(indicator.panels[screen.id]?.frame == screen.indicatorFrame(scale: 5, position: .bottomLeft),
              "重新进入全屏沿用位置和大小")
        indicator.updateScreens([])

        let suite = "InputMethodPrompt.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        var changes = 0
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { _ in }, onPreview: {}, onFullScreenChange: { changes += 1 })
        guard let content = controller.window?.contentView else { check(false, "读取位置设置窗口"); return }
        let views = descendants(of: content)
        guard let picker = views.first(where: { $0.identifier?.rawValue == "fullScreenPosition" }) as? NSPopUpButton,
              let toggle = views.first(where: { $0.identifier?.rawValue == "fullScreenIndicatorEnabled" }) as? NSSwitch else {
            check(false, "全屏常驻包含展示位置选择器")
            return
        }
        check(picker.numberOfItems == 9 && picker.titleOfSelectedItem == "右上角" && changes == 0,
              "位置默认右上角并提供九宫格选项")
        picker.selectItem(withTitle: "下方居中")
        picker.sendAction(picker.action, to: picker.target)
        check(AppSettings(defaults: UserDefaults(suiteName: suite)!).fullScreenPosition == .bottom && changes == 1,
              "选择位置即时回调并持久保存")
        views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "resetFullScreenAppearance" }?.performClick(nil)
        check(settings.fullScreenPosition == .bottom && picker.titleOfSelectedItem == "下方居中",
              "恢复默认外观保留展示位置")
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        check(!picker.isEnabled && settings.fullScreenPosition == .bottom, "关闭常驻提示禁用位置选择但保留选择")
        defaults.set("invalid-position", forKey: "fullScreenPosition")
        check(settings.fullScreenPosition == .topRight, "无效位置配置回到右上角")
        controller.close()
    }

    private static func checkFullScreenHover() {
        guard let screen = NSScreen.screens.first else { check(false, "悬停测试读取屏幕"); return }
        let target = IndicatorScreen(id: 456, frame: screen.frame, safeTop: screen.safeAreaInsets.top, safeRight: 0)
        var mouse = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        let indicator = FullScreenIndicator(backgroundOpacity: 0.65, scale: 5, readMouseLocation: { mouse })
        let source = InputSource(id: "abc", name: "ABC", languages: ["en"])
        indicator.updateState(InputState(source: source, capsLock: false))
        indicator.updateScreens([target])
        guard let panel = indicator.panels[target.id] else { check(false, "悬停测试创建常驻窗口"); return }
        let originalFrame = panel.frame
        mouse = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        indicator.refreshHover()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(panel.alphaValue < 1 && panel.alphaValue > FullScreenIndicator.hoveredAlpha,
              "鼠标移入时平滑淡化而非突然隐藏")
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))
        check(abs(panel.alphaValue - 0.12) < 0.001 && panel.isVisible && panel.ignoresMouseEvents,
              "悬停时整块提示降至12%不透明度并保持点击穿透")
        indicator.updateState(InputState(source: source, capsLock: true))
        check(abs(panel.alphaValue - 0.12) < 0.001 && panel.frame == originalFrame,
              "悬停期间切换状态不恢复遮挡且窗口位置不变")
        mouse = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        // Exercise periodic position reading rather than an explicit refresh.
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        check(abs(panel.alphaValue - 1) < 0.001, "鼠标移开后自动恢复原有外观")
        if let data = (panel.contentView as? NSVisualEffectView)?.maskImage?.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: data),
           let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2) {
            check(abs(color.alphaComponent - 0.65) < 0.01, "悬停淡化不改用户设置的背景透明度")
        } else { check(false, "悬停后背景透明度读取") }
        mouse = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        indicator.refreshHover()
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let partial = panel.alphaValue
        mouse = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        indicator.refreshHover()
        check(panel.alphaValue == partial, "快速移出从当前透明度反向恢复，不跳变")
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(abs(panel.alphaValue - 1) < 0.001, "快速进出无过期动画覆盖最终状态")
        mouse = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        indicator.refreshHover()
        indicator.updateScreens([])
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        check(indicator.panels.isEmpty && !panel.isVisible, "淡化期间退出全屏后不会被旧动画重新显示")
    }

    private static func checkSettingsSections() {
        let suite = "InputMethodPrompt.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.transparency = 0.6
        settings.fullScreenTransparency = 0.7
        settings.fullScreenScale = 1.5
        let login = FakeLoginItem()
        var switchingChanges = 0
        var fullScreenChanges = 0
        var previews = 0
        let controller = SettingsWindowController(settings: settings, loginItem: login,
            onChange: { _ in }, onPreview: { previews += 1 },
            onFullScreenChange: { fullScreenChanges += 1 }, onSwitchingChange: { switchingChanges += 1 })
        guard let content = controller.window?.contentView else { check(false, "读取分组设置"); return }
        let views = descendants(of: content)
        guard let sections = views.first(where: { $0.identifier?.rawValue == "settingsSections" }) as? NSSegmentedControl,
              let switching = views.first(where: { $0.identifier?.rawValue == "switchingPromptEnabled" }) as? NSSwitch,
              let fullScreen = views.first(where: { $0.identifier?.rawValue == "fullScreenIndicatorEnabled" }) as? NSSwitch,
              let opacity = views.first(where: { $0.identifier?.rawValue == "backgroundTransparency" }) as? NSSlider,
              let sample = views.compactMap({ $0 as? IndicatorView }).first else {
            check(false, "设置包含四个分类、独立开关和常驻预览")
            return
        }
        let pages = ["switchingPage", "fullScreenPage", "mousePage", "generalPage"].compactMap { id in
            views.first { $0.identifier?.rawValue == id }
        }
        check(pages.count == 4 && pages.filter { !$0.isHidden }.count == 1 && !pages[0].isHidden,
              "默认只展示切换提示分类")
        for index in 0..<4 {
            sections.selectedSegment = index
            sections.sendAction(sections.action, to: sections.target)
            check(!pages[index].isHidden && pages.filter { !$0.isHidden }.count == 1,
                  "分类\(index + 1)切换后只显示对应设置")
        }
        switching.state = .off
        switching.sendAction(switching.action, to: switching.target)
        check(!AppSettings(defaults: UserDefaults(suiteName: suite)!).switchingPromptEnabled &&
              switchingChanges == 1 && !opacity.isEnabled && settings.fullScreenIndicatorEnabled,
              "切换提示开关自动保存、即时回调且不影响全屏常驻")
        views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "previewSwitchingPrompt" }?.performClick(nil)
        check(previews == 1, "关闭自动切换提示后仍可手动预览")
        fullScreen.state = .off
        fullScreen.sendAction(fullScreen.action, to: fullScreen.target)
        check(!settings.switchingPromptEnabled && !settings.fullScreenIndicatorEnabled,
              "两种提示开关可独立关闭")
        check(sample.frame.size == NSSize(width: 54, height: 54), "常驻分类按保存比例展示实际大小预览")
        views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "resetFullScreenAppearance" }?.performClick(nil)
        check(settings.fullScreenScale == 1 && settings.fullScreenTransparency == 0.45 && settings.transparency == 0.6 &&
              !settings.fullScreenIndicatorEnabled && !settings.switchingPromptEnabled && login.changeCount == 0 && fullScreenChanges == 2,
              "全屏分类恢复外观只重置自身透明度和大小，不改开关及登录项")
        check(sample.frame.size == NSSize(width: 36, height: 36), "恢复外观同步更新常驻预览")
        controller.close()
    }

    private static func checkMouseIndicator() {
        let primary = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let secondary = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let screens = [primary, secondary]
        let middle = NSPoint(x: 500, y: 500)
        check(MouseIndicatorLayout.frame(at: middle, in: screens) == NSRect(x: 518, y: 455, width: 27, height: 27),
              "鼠标提示位于右下方且与指针保持间隔")
        for screen in screens {
            for point in [NSPoint(x: screen.minX + 1, y: screen.minY + 1),
                          NSPoint(x: screen.maxX - 1, y: screen.minY + 1),
                          NSPoint(x: screen.minX + 1, y: screen.maxY - 1),
                          NSPoint(x: screen.maxX - 1, y: screen.maxY - 1)] {
                let frame = MouseIndicatorLayout.frame(at: point, in: screens)!
                check(screen.contains(frame) && !frame.contains(point), "鼠标提示在屏幕角落自动避让并兼容负坐标")
            }
        }
        check(MouseIndicatorLayout.frame(at: middle, in: []) == nil, "无匹配显示器时不猜测鼠标位置")
        var mouse = middle
        var reads = 0
        var availableScreens = screens
        var screenReads = 0
        let indicator = MouseIndicator(readMouseLocation: { reads += 1; return mouse },
            readScreens: { screenReads += 1; return availableScreens }, observeMouseEvents: false, readCursorVisible: { true },
            makeFrameClock: { _, _ in nil })
        let chinese = InputState(source: InputSource(id: "pinyin", name: "拼音", languages: ["zh"]), capsLock: false)
        let english = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        indicator.setEnabled(true)
        check(!indicator.panel.isVisible, "鼠标提示没有输入状态时保持隐藏")
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        indicator.updateState(chinese)
        let label = indicator.panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first
        check(indicator.panel.isVisible && label?.stringValue == "中" &&
              indicator.panel.ignoresMouseEvents && !indicator.panel.canBecomeKey && !indicator.panel.canBecomeMain &&
              foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
              "开启鼠标提示立即显示状态且点击穿透、不抢焦点")
        mouse = NSPoint(x: -500, y: 400)
        indicator.schedulePositionRefresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        check(indicator.panel.frame == MouseIndicatorLayout.frame(at: mouse, in: screens), "鼠标移动通知触发跨屏跟随")
        let idleReads = reads
        let idleScreenReads = screenReads
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        check(reads == idleReads && screenReads == idleScreenReads, "鼠标静止时没有定时位置或显示器轮询")
        mouse = NSPoint(x: -500.375, y: 400.625)
        indicator.refreshPosition()
        let fractionalFrame = indicator.panel.frame
        var moves = 0
        let moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
            object: indicator.panel, queue: .main) { _ in moves += 1 }
        let cachedScreenReads = screenReads
        for _ in 0..<200 { indicator.refreshPosition() }
        NotificationCenter.default.removeObserver(moveObserver)
        check(moves == 0 && indicator.panel.frame == fractionalFrame && screenReads == cachedScreenReads,
              "小数鼠标坐标静止时不重复移动窗口或枚举显示器")
        let coalescedReads = reads
        for index in 0..<200 {
            mouse = NSPoint(x: -600 + CGFloat(index), y: 420)
            indicator.schedulePositionRefresh()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        check(reads - coalescedReads <= 2 && indicator.panel.frame == MouseIndicatorLayout.frame(at: mouse, in: screens),
              "高频移动事件合并并使用最后位置，不积压过期位置")
        check(!(indicator.panel.contentView is NSVisualEffectView) && !indicator.panel.hasShadow,
              "鼠标提示使用轻量背景且不计算动态毛玻璃和窗口阴影")
        indicator.updateState(english)
        check(label?.stringValue == "a", "鼠标提示同步英文状态")
        indicator.updateState(InputState(source: english.source, capsLock: true))
        check(label?.stringValue == "A", "鼠标提示同步已确认的大写锁定状态")
        mouse.x += 12
        indicator.schedulePositionRefresh()
        indicator.setEnabled(false)
        let stoppedReads = reads
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(!indicator.panel.isVisible && reads == stoppedReads, "关闭鼠标提示淡出并取消待处理移动")
        indicator.setEnabled(true)
        check(indicator.panel.isVisible && label?.stringValue == "A", "重新开启鼠标提示保留当前输入状态")
        availableScreens = []
        indicator.refreshScreens()
        check(!indicator.panel.isVisible, "显示器暂时不可用时隐藏鼠标提示")
        availableScreens = screens
        indicator.refreshScreens()
        check(indicator.panel.isVisible, "显示器恢复后鼠标提示重新显示")
        indicator.updateState(nil)
        let emptyReads = reads
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(!indicator.panel.isVisible && reads == emptyReads, "输入状态失效时隐藏并停止轮询")

        let suite = "InputMethodPrompt.MouseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        var changes = 0
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { _ in }, onPreview: {}, onMouseChange: { changes += 1 })
        let views = descendants(of: controller.window!.contentView!)
        let toggle = views.first { $0.identifier?.rawValue == "mouseIndicatorEnabled" } as! NSSwitch
        check(settings.mouseIndicatorEnabled && toggle.state == .on && changes == 0, "鼠标跟随默认开启且设置初始化不触发修改")
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        check(!AppSettings(defaults: UserDefaults(suiteName: suite)!).mouseIndicatorEnabled && changes == 1 &&
              settings.switchingPromptEnabled && settings.fullScreenIndicatorEnabled,
              "鼠标跟随开关即时回调并独立保存，不影响其他模式")
        controller.close()
    }

    private static func checkMouseAppearance() {
        let suite = "InputMethodPrompt.MouseAppearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let screen = NSScreen.screens.first!.frame
        let mouse = NSPoint(x: screen.maxX - 1, y: screen.minY + 1)
        let indicator = MouseIndicator(readMouseLocation: { mouse }, readScreens: { [screen] },
                                       observeMouseEvents: false, readCursorVisible: { true }, makeFrameClock: { _, _ in nil })
        indicator.updateState(InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false))
        indicator.setEnabled(true)
        let apply = {
            indicator.updateAppearance(scale: settings.mouseScale, opacity: settings.mouseOpacity)
            indicator.setEnabled(settings.mouseIndicatorEnabled)
        }
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { _ in }, onPreview: {}, onMouseChange: apply)
        let views = descendants(of: controller.window!.contentView!)
        guard let size = views.first(where: { $0.identifier?.rawValue == "mouseScale" }) as? NSSlider,
              let transparency = views.first(where: { $0.identifier?.rawValue == "mouseTransparency" }) as? NSSlider,
              let toggle = views.first(where: { $0.identifier?.rawValue == "mouseIndicatorEnabled" }) as? NSSwitch,
              let sample = views.compactMap({ $0 as? MouseIndicatorView }).first,
              let reset = views.first(where: { $0.identifier?.rawValue == "resetMouseAppearance" }) as? NSButton else {
            check(false, "鼠标外观包含大小、透明度、开关、预览与重置"); return
        }
        check(size.doubleValue == 100 && transparency.doubleValue == 50 &&
              sample.frame.size == NSSize(width: 27, height: 27) && sample.alphaValue == 0.5,
              "鼠标外观默认正方形与50%整体不透明度")
        size.doubleValue = 199
        size.sendAction(size.action, to: size.target)
        let label = indicator.panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first
        check(settings.mouseScale == 2 && indicator.panel.frame.size == NSSize(width: 54, height: 54) &&
              label?.font?.pointSize == 27 && label?.stringValue == "a" && sample.frame.size == indicator.panel.frame.size,
              "鼠标大小按5%步进实时缩放窗口、文字和预览，保留当前状态")
        check(screen.contains(indicator.panel.frame) && !indicator.panel.frame.contains(mouse),
              "鼠标静止在边缘时放大仍重新避让且不覆盖指针")
        transparency.doubleValue = 72
        transparency.sendAction(transparency.action, to: transparency.target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        let saved = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        check(saved.mouseScale == 2 && saved.mouseTransparency == 0.72 &&
              abs(indicator.panel.alphaValue - 0.28) < 0.001 && sample.alphaValue == indicator.panel.alphaValue &&
              settings.fullScreenScale == 1 && settings.transparency == AppSettings.defaultTransparency,
              "整体透明度同时作用于真实窗口和预览，保存后可读回且不影响其他模式")
        transparency.doubleValue = 100
        transparency.sendAction(transparency.action, to: transparency.target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(!indicator.panel.isVisible && sample.alphaValue == 0, "100%整体透明度隐藏鼠标标识")
        transparency.doubleValue = 0
        transparency.sendAction(transparency.action, to: transparency.target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 1, "降低透明度后无需移动鼠标即可恢复显示")
        size.doubleValue = 300
        size.sendAction(size.action, to: size.target)
        check(indicator.panel.frame.size == NSSize(width: 81, height: 81) &&
              sample.superview!.bounds.contains(sample.frame), "300%大小的真实窗口及预览完整显示")
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(!size.isEnabled && !transparency.isEnabled && !indicator.panel.isVisible,
              "关闭鼠标跟随后禁用外观滑块并隐藏标识")
        reset.performClick(nil)
        check(settings.mouseScale == 1 && settings.mouseTransparency == 0.5 && !settings.mouseIndicatorEnabled &&
              settings.fullScreenIndicatorEnabled && settings.switchingPromptEnabled && !indicator.panel.isVisible,
              "恢复默认只重置鼠标外观，不开启功能或影响其他模式")
        settings.mouseScale = 0.1
        check(settings.mouseScale == 0.5, "鼠标大小最小50%")
        settings.mouseScale = 8
        check(settings.mouseScale == 3, "鼠标大小最大300%")
        settings.mouseScale = .nan
        check(settings.mouseScale == 3, "非有限大小不覆盖已保存值")
        settings.mouseTransparency = 5
        settings.mouseTransparency = .infinity
        check(settings.mouseTransparency == 1, "透明度范围约束且忽略非有限输入")
        controller.close()
        indicator.setEnabled(false)
    }

    private static func checkSystemCursorVisibility() {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        pumpAppEvents(for: 0.4)
        defer { previous?.activate(options: []) }
        let screen = NSScreen.screens.first!.frame
        let mouse = NSPoint(x: screen.midX, y: screen.midY)
        let indicator = MouseIndicator(readMouseLocation: { mouse }, observeMouseEvents: false)
        indicator.updateState(InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false))
        indicator.setEnabled(true)
        defer { indicator.setEnabled(false) }
        check(SystemCursorVisibility.read() == true && indicator.panel.isVisible, "真实系统可见指针与跟随标识同步显示")
        NSCursor.hide()
        pumpAppEvents(for: 0.4)
        check(SystemCursorVisibility.read() == false && !indicator.panel.isVisible, "真实NSCursor.hide后自动检测并隐藏标识")
        NSCursor.unhide()
        pumpAppEvents(for: 0.4)
        check(SystemCursorVisibility.read() == true && indicator.panel.isVisible, "真实NSCursor.unhide后无需移动即可恢复标识")
        NSCursor.setHiddenUntilMouseMoves(true)
        pumpAppEvents(for: 0.4)
        check(SystemCursorVisibility.read() == false && !indicator.panel.isVisible, "真实输入时隐藏指针模式同步隐藏标识")
        NSCursor.setHiddenUntilMouseMoves(false)
        pumpAppEvents(for: 0.4)
        check(SystemCursorVisibility.read() == true && indicator.panel.isVisible, "取消输入时隐藏指针后恢复标识")
    }

    private static func checkMouseVisibilityAndIdle() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        var mouse = NSPoint(x: 500, y: 500)
        var now: TimeInterval = 100
        var cursor: Bool? = true
        var visibilityReads = 0
        let indicator = MouseIndicator(readMouseLocation: { mouse }, readScreens: { [screen] },
            observeMouseEvents: false, readCursorVisible: { visibilityReads += 1; return cursor }, readTime: { now },
            makeFrameClock: { _, _ in nil })
        let state = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        indicator.updateState(state)
        indicator.setEnabled(true)
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0, "首次显示从完全透明开始淡入")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(indicator.panel.alphaValue > 0 && indicator.panel.alphaValue < 0.5, "显示过程中存在淡入中间帧")
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        now = 102.99
        indicator.refreshVisibility()
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0.5, "静止不足3秒保持正常显示")
        now = 103
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(indicator.panel.alphaValue > 0 && indicator.panel.alphaValue < 0.5, "静止隐藏通过短渐隐过渡")
        mouse.x += 1
        let reversingAlpha = indicator.panel.alphaValue
        indicator.refreshPosition()
        check(indicator.panel.alphaValue == reversingAlpha, "淡出中移动从当前透明度反向淡入，没有跳变")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0.5, "渐隐中再次移动平滑恢复且旧动画不会误隐藏")
        now = 106
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        check(!indicator.panel.isVisible, "默认静止3秒后隐藏")
        indicator.updateAppearance(scale: 2, opacity: 0.4)
        indicator.refreshScreens()
        check(!indicator.panel.isVisible, "尺寸和屏幕更新不会唤醒静止隐藏标识")
        indicator.updateIdleBehavior(.fade)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        check(indicator.panel.isVisible && abs(indicator.panel.alphaValue - 0.08) < 0.001,
              "切换为淡化后立即生效且叠加用户不透明度")
        cursor = false
        let beforeHide = indicator.panel.alphaValue
        indicator.refreshVisibility()
        check(indicator.panel.isVisible && indicator.panel.alphaValue == beforeHide, "系统指针隐藏从当前透明度淡出")
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        check(indicator.panel.alphaValue > 0 && indicator.panel.alphaValue < beforeHide, "系统指针隐藏存在淡出中间帧")
        RunLoop.main.run(until: Date().addingTimeInterval(0.16))
        check(!indicator.panel.isVisible, "系统鼠标隐藏优先于静止淡化")
        mouse.x += 10
        now = 107
        indicator.refreshPosition()
        check(!indicator.panel.isVisible, "指针隐藏期间移动不会单独显示标识")
        cursor = true
        indicator.refreshVisibility()
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0, "指针恢复从透明淡入")
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0.4, "指针恢复可见且未静止3秒时恢复正常显示")
        now = 110
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        cursor = false
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        cursor = true
        indicator.refreshVisibility()
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0,
              "静止淡化标识恢复也从透明淡入，避免亮闪")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        check(indicator.panel.isVisible && abs(indicator.panel.alphaValue - 0.08) < 0.001,
              "指针静止恢复可见时仍遵守淡化设置")
        indicator.updateIdleBehavior(.hide)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        cursor = false
        indicator.refreshVisibility()
        cursor = true
        indicator.refreshVisibility()
        check(!indicator.panel.isVisible, "指针静止恢复可见时仍遵守隐藏设置")
        mouse.x += 1
        indicator.refreshPosition()
        indicator.updateAppearance(scale: 1, opacity: 0)
        let reads = visibilityReads
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(!indicator.panel.isVisible && visibilityReads == reads, "全透明时停止可见性检测")
        indicator.updateAppearance(scale: 1, opacity: 0.5)
        check(indicator.panel.isVisible, "从全透明恢复会重新开始静止计时")
        cursor = nil
        indicator.refreshVisibility()
        check(indicator.panel.isVisible, "检测不可用时保留静止功能，不猜测指针隐藏")
        indicator.setEnabled(false)
        let stopped = visibilityReads
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(!indicator.panel.isVisible && stopped == visibilityReads, "关闭后取消可见性检测及动画")

        let suite = "InputMethodPrompt.Idle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        var changes = 0
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { _ in }, onPreview: {}, onMouseChange: { changes += 1 })
        let views = descendants(of: controller.window!.contentView!)
        let picker = views.first { $0.identifier?.rawValue == "mouseIdleBehavior" } as! NSPopUpButton
        check(settings.mouseIdleBehavior == .hide && picker.titleOfSelectedItem == "隐藏", "静止设置默认隐藏")
        picker.selectItem(withTitle: "淡化")
        picker.sendAction(picker.action, to: picker.target)
        check(AppSettings(defaults: UserDefaults(suiteName: suite)!).mouseIdleBehavior == .fade && changes == 1,
              "静止选项实时回调并持久保存")
        let reset = views.first { $0.identifier?.rawValue == "resetMouseAppearance" } as! NSButton
        reset.performClick(nil)
        check(settings.mouseIdleBehavior == .fade, "恢复默认外观不修改静止行为")
        let toggle = views.first { $0.identifier?.rawValue == "mouseIndicatorEnabled" } as! NSSwitch
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        check(!picker.isEnabled && settings.mouseIdleBehavior == .fade, "关闭跟随禁用静止选项并保留选择")
        controller.close()
        check(PromptView.size == NSSize(width: 148, height: 148), "切换提示为148pt正方形")
        for scale in [0.75, 1, 3, 5] {
            let size = IndicatorMetrics.size(scale: scale)
            let view = IndicatorView(backgroundOpacity: 0.5, scale: scale)
            check(size.width == size.height && view.frame.size == size, "常驻提示缩放后仍为正方形")
        }
        for scale in [0.5, 1, 3] {
            let size = MouseIndicatorLayout.size(scale: scale)
            let view = MouseIndicatorView()
            view.updateScale(scale)
            check(size.width == size.height && view.frame.size == size, "鼠标提示缩放后仍为正方形")
        }
    }

    private static func checkMouseIdleDelay() {
        let suite = "InputMethodPrompt.IdleDelay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let screen = NSScreen.screens.first!.frame
        var now: TimeInterval = 0
        let indicator = MouseIndicator(readMouseLocation: { NSPoint(x: screen.midX, y: screen.midY) },
            observeMouseEvents: false, readCursorVisible: { true }, readTime: { now }, makeFrameClock: { _, _ in nil })
        indicator.updateState(InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false))
        indicator.setEnabled(true)
        var changes = 0
        let controller = SettingsWindowController(settings: settings, loginItem: FakeLoginItem(),
            onChange: { _ in }, onPreview: {}, onMouseChange: {
                changes += 1
                indicator.updateIdleDelay(settings.mouseIdleDelay)
            })
        let views = descendants(of: controller.window!.contentView!)
        let seconds = views.first { $0.identifier?.rawValue == "mouseIdleDelay" } as! NSTextField
        let stepper = views.first { $0.identifier?.rawValue == "mouseIdleDelayStepper" } as! NSStepper
        check(settings.mouseIdleDelay == 3 && seconds.integerValue == 3 && stepper.integerValue == 3,
              "旧配置没有秒数时默认3秒且控件一致")
        seconds.stringValue = "8"
        seconds.sendAction(seconds.action, to: seconds.target)
        check(settings.mouseIdleDelay == 8 && stepper.integerValue == 8 && changes == 1 &&
              AppSettings(defaults: UserDefaults(suiteName: suite)!).mouseIdleDelay == 8,
              "输入秒数实时更新、同步步进器并持久保存")
        now = 7.99
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0.5, "自定义8秒在到期前不会隐藏")
        now = 8
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(!indicator.panel.isVisible, "自定义8秒到期后淡出隐藏")
        stepper.doubleValue = 10
        stepper.sendAction(stepper.action, to: stepper.target)
        check(seconds.integerValue == 10 && settings.mouseIdleDelay == 10 && indicator.panel.alphaValue == 0,
              "延长时长立即按已静止时间重新判断并从透明淡入")
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        let partial = indicator.panel.alphaValue
        check(partial > 0 && partial < 0.5, "隐藏后的恢复存在淡入中间帧")
        stepper.doubleValue = 5
        stepper.sendAction(stepper.action, to: stepper.target)
        check(indicator.panel.alphaValue == partial, "淡入中缩短时长从当前透明度反向淡出")
        RunLoop.main.run(until: Date().addingTimeInterval(0.23))
        check(!indicator.panel.isVisible, "反向淡出完成后无旧动画再次显示")
        for invalid in ["", "abc", "0", "61", "3.5", "nan"] {
            seconds.stringValue = invalid
            seconds.sendAction(seconds.action, to: seconds.target)
            check(settings.mouseIdleDelay == 5 && seconds.integerValue == 5, "无效秒数不会覆盖保存值：\(invalid)")
        }
        let reset = views.first { $0.identifier?.rawValue == "resetMouseAppearance" } as! NSButton
        reset.performClick(nil)
        check(settings.mouseIdleDelay == 5, "恢复默认外观不修改静止秒数")
        let toggle = views.first { $0.identifier?.rawValue == "mouseIndicatorEnabled" } as! NSSwitch
        toggle.state = .off
        toggle.sendAction(toggle.action, to: toggle.target)
        check(!seconds.isEnabled && !stepper.isEnabled && settings.mouseIdleDelay == 5,
              "关闭跟随禁用秒数输入和步进器但保留设置")
        defaults.set(Double.infinity, forKey: "mouseIdleDelay")
        check(settings.mouseIdleDelay == 3, "损坏秒数配置恢复默认3秒")
        settings.mouseIdleDelay = 100
        check(settings.mouseIdleDelay == 60, "秒数上限60")
        settings.mouseIdleDelay = 0
        check(settings.mouseIdleDelay == 1, "秒数下限1")
        controller.close()
        indicator.setEnabled(false)
    }

    private static func checkMouseInputChangeReveal() {
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        var now: TimeInterval = 0
        var mouse = NSPoint(x: 500, y: 500)
        var cursor = true
        var screens = [NSRect(x: 0, y: 0, width: 1512, height: 982)]
        var visibilityReads = 0
        let english = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        let chinese = InputState(source: InputSource(id: "pinyin", name: "拼音", languages: ["zh"]), capsLock: false)
        var indicator: MouseIndicator? = MouseIndicator(readMouseLocation: { mouse }, readScreens: { screens },
            observeMouseEvents: false, readCursorVisible: { visibilityReads += 1; return cursor }, readTime: { now },
            makeFrameClock: { _, _ in nil })
        indicator!.updateState(english)
        indicator!.setEnabled(true)
        wait(0.2)
        now = 3
        indicator!.refreshVisibility()
        wait(0.22)
        check(!indicator!.panel.isVisible, "切换提示前已因静止隐藏")
        indicator!.updateState(chinese)
        let label = indicator!.panel.contentView!.subviews.compactMap { $0 as? NSTextField }.first!
        check(indicator!.panel.isVisible && indicator!.panel.alphaValue == 0 && label.stringValue == "中",
              "隐藏中切换输入法唤出最新状态并从透明淡入")
        wait(0.18)
        check(indicator!.panel.alphaValue == 0.5, "临时切换提示恢复用户设定的不透明度")
        indicator!.refreshVisibility()
        indicator!.refreshScreens()
        check(indicator!.panel.alphaValue == 0.5, "静止策略与屏幕刷新不会打断临时展示")
        wait(0.12)
        indicator!.updateState(english)
        wait(0.38)
        check(indicator!.panel.isVisible && indicator!.panel.alphaValue == 0.5 && label.stringValue == "a",
              "连续切换延长展示，旧截止不会提前隐藏新状态")
        // Identical states must not extend the temporary reveal.
        for _ in 0..<5 { indicator!.updateState(english); wait(0.08) }
        check(!indicator!.panel.isVisible, "相同状态不延长展示，到期恢复静止隐藏而不重新计时")
        let stoppedReads = visibilityReads
        wait(0.25)
        check(visibilityReads == stoppedReads, "临时展示结束并隐藏后重新暂停可见性轮询")

        cursor = false
        indicator!.updateState(chinese)
        wait(0.18)
        check(indicator!.panel.isVisible && indicator!.panel.alphaValue == 0.5,
              "系统指针隐藏期间切换也短暂展示输入状态")
        wait(0.68)
        check(!indicator!.panel.isVisible, "展示结束恢复系统指针隐藏策略")
        cursor = true
        indicator!.updateIdleBehavior(.fade)
        wait(0.2)
        check(abs(indicator!.panel.alphaValue - 0.1) < 0.001, "静止淡化状态可用于临时展示前的状态")
        indicator!.updateState(english)
        wait(0.18)
        check(indicator!.panel.alphaValue == 0.5, "淡化中切换输入法会短暂恢复正常亮度")
        wait(0.68)
        check(abs(indicator!.panel.alphaValue - 0.1) < 0.001, "展示结束恢复静止淡化")

        indicator!.updateState(chinese)
        now = 4
        mouse.x += 1
        indicator!.refreshPosition()
        wait(0.85)
        check(indicator!.panel.isVisible && indicator!.panel.alphaValue == 0.5,
              "临时展示中移动，到期遵守新的活动状态，不强行隐藏")
        now = 7
        indicator!.updateIdleBehavior(.hide)
        indicator!.refreshVisibility()
        wait(0.22)
        indicator!.updateState(english)
        wait(MouseIndicator.fadeInDuration + MouseIndicator.inputChangeDuration + 0.06)
        let partialAlpha = indicator!.panel.alphaValue
        check(indicator!.panel.isVisible && partialAlpha > 0 && partialAlpha < 0.5,
              "临时展示到期进入淡出中间帧")
        indicator!.updateState(chinese)
        check(indicator!.panel.alphaValue == partialAlpha, "淡出中再次切换从当前透明度反向淡入")
        wait(0.2)
        check(indicator!.panel.isVisible && indicator!.panel.alphaValue == 0.5,
              "旧淡出不会关闭再次切换后的临时提示")
        indicator!.updateIdleBehavior(.fade)
        wait(0.7)
        check(abs(indicator!.panel.alphaValue - 0.1) < 0.001, "临时展示结束遵循刚修改的淡化行为")
        indicator!.updateState(english)
        indicator!.updateIdleDelay(10)
        wait(0.85)
        check(indicator!.panel.isVisible && indicator!.panel.alphaValue == 0.5,
              "临时展示中延长静止时长，到期不强行恢复过期隐藏状态")
        indicator!.updateIdleDelay(3)
        // Leave a different state ready for the following cancellation scenario.
        indicator!.updateState(chinese)
        wait(0.85)
        now = 7
        indicator!.updateIdleBehavior(.hide)
        indicator!.refreshVisibility()
        wait(0.22)
        indicator!.updateState(english)
        wait(0.06)
        indicator!.setEnabled(false)
        indicator!.updateState(chinese)
        wait(0.85)
        check(!indicator!.panel.isVisible, "关闭功能取消临时展示，后续切换与旧截止不能重现图标")
        indicator!.updateAppearance(scale: 1, opacity: 0)
        indicator!.setEnabled(true)
        indicator!.updateState(english)
        wait(0.2)
        check(!indicator!.panel.isVisible, "整体透明度100%时切换不会唤出")
        indicator!.updateAppearance(scale: 1, opacity: 0.5)
        cursor = false
        indicator!.refreshVisibility()
        wait(0.22)
        screens = []
        indicator!.refreshScreens()
        indicator!.updateState(chinese)
        wait(0.2)
        check(!indicator!.panel.isVisible, "没有有效屏幕时不猜测临时展示位置")
        indicator!.updateState(nil)
        wait(0.7)
        check(!indicator!.panel.isVisible, "状态失效取消临时展示")
        screens = [NSRect(x: 0, y: 0, width: 1512, height: 982)]
        indicator!.updateState(english)
        indicator!.updateState(chinese)
        weak let released = indicator
        let panel = indicator!.panel
        indicator = nil
        wait(0.7)
        check(released == nil && !panel.isVisible, "临时计时器不持有对象，销毁后无残留窗口")
    }

    private static func checkInputStateReconciliation() {
        let chinese = InputState(source: InputSource(id: "test.zh", name: "Chinese", languages: ["zh"]), capsLock: false)
        let english = InputState(source: InputSource(id: "test.en", name: "English", languages: ["en"]), capsLock: false)
        var state = chinese
        let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { false }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
        var events: [InputState] = []
        monitor.onChange = { events.append($0) }
        // Deliberately change the source without a notification or modifier edge.
        state = english
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        check(monitor.current == english && events == [english], "漏收输入源通知、Caps 不变时自动纠正旧中文状态")
    }

    private static func checkInputStateLifecycleAndModes() {
        let chinese = InputState(source: InputSource(id: "test.zh", name: "Chinese", languages: ["zh"]), capsLock: false)
        let english = InputState(source: InputSource(id: "test.en", name: "English", languages: ["en"]), capsLock: false)
        func wait(_ interval: Double) { RunLoop.main.run(until: Date().addingTimeInterval(interval)) }
        let notifications = NotificationCenter()
        let sourceNotifications = NotificationCenter()
        let sourceChanged = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        let triggers = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                        NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                        NSWorkspace.sessionDidBecomeActiveNotification]
        do {
            var state = chinese
            var reads = 0
            let monitor = InputSourceMonitor(readState: { reads += 1; return state }, readCapsLock: { false },
                                             sourceNotifications: sourceNotifications, workspaceNotifications: notifications, reconciliationInterval: 60)
            var events: [InputState] = []
            monitor.onChange = { events.append($0) }
            for trigger in triggers {
                state = state == chinese ? english : chinese
                let before = events.count
                notifications.post(name: trigger, object: nil)
                wait(0.18)
                check(monitor.current == state && events.count == before + 1, "生命周期通知重新确认输入状态：\(trigger.rawValue)")
            }
            let beforeReads = reads
            let beforeEvents = events.count
            for _ in 0..<20 {
                for trigger in triggers { notifications.post(name: trigger, object: nil) }
                sourceNotifications.post(name: sourceChanged, object: nil)
            }
            wait(0.04)
            check(reads == beforeReads + 1 && events.count == beforeEvents, "混合系统通知合并读取，相同状态不重复弹窗")
            state = chinese
            DispatchQueue.global().async { notifications.post(name: NSWorkspace.didWakeNotification, object: nil) }
            wait(0.25)
            check(monitor.current == chinese && events.count == beforeEvents + 1, "后台线程通知回主线程确认状态")
        }
        do {
            var state = chinese
            var reads = 0
            let monitor = InputSourceMonitor(readState: { reads += 1; return state }, readCapsLock: { state.capsLock },
                                             sourceNotifications: sourceNotifications, workspaceNotifications: notifications, reconciliationInterval: 0.15)
            var events: [InputState] = []
            monitor.onChange = { events.append($0) }
            wait(0.38)
            check(reads >= 3 && reads <= 4 && events.isEmpty, "低频校准不重复发布稳定状态")
            state = InputState(source: english.source, capsLock: true)
            monitor.refresh()
            wait(0.10)
            state = english
            wait(0.35)
            check(events == [english], "校准与 Caps 轮询交错也不发布短暂 A")
            state = InputState(source: english.source, capsLock: true)
            monitor.refresh()
            wait(0.32)
            check(events.last?.symbol == "A" && events.count == 2, "校准周期短于确认窗口也不延后真实 Caps Lock")
        }
        do {
            let mode1 = InputSource(id: "test.same", name: "模式", languages: ["zh"], inputModeID: "mode.1")
            let mode2 = InputSource(id: "test.same", name: "模式", languages: ["zh"], inputModeID: "mode.2")
            var state = InputState(source: mode1, capsLock: false)
            let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { false },
                                             sourceNotifications: sourceNotifications, workspaceNotifications: notifications, reconciliationInterval: 0.15)
            var events: [InputState] = []
            monitor.onChange = { events.append($0) }
            state = InputState(source: mode2, capsLock: false)
            wait(0.35)
            check(monitor.current == state && events == [state], "输入源 ID 不变时仍识别系统公开的模式 ID 变化")
        }
        var readsAfterRelease = 0
        weak var released: InputSourceMonitor?
        autoreleasepool {
            let monitor = InputSourceMonitor(readState: { readsAfterRelease += 1; return english }, readCapsLock: { false },
                                             sourceNotifications: sourceNotifications, workspaceNotifications: notifications, reconciliationInterval: 0.10)
            released = monitor
            notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        }
        let baseline = readsAfterRelease
        sourceNotifications.post(name: sourceChanged, object: nil)
        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        wait(0.35)
        check(released == nil && readsAfterRelease == baseline, "销毁后取消校准、系统观察者和已排队刷新")

        check(InputSource(id: "test.unknown", name: "未知", languages: ["zh"], inputModeID: "vendor.English").symbol == "中",
              "不通过模式 ID 字符串猜测未公开的英文状态")
        check(InputSource(id: "test.no-mode", name: "未提供模式", languages: ["zh"]).inputModeID == nil,
              "系统未公开模式 ID 时保留缺失状态")
    }

    private static func checkInputMonitorRecovery() {
        let english = InputSource(id: "test.en", name: "English", languages: ["en"])
        let chinese = InputSource(id: "test.zh", name: "Chinese", languages: ["zh"])
        func waitForMonitor(_ interval: Double) { RunLoop.main.run(until: Date().addingTimeInterval(interval)) }
        do {
            var state = InputState(source: english, capsLock: false)
            var reads = 0
            let monitor = InputSourceMonitor(readState: { reads += 1; return state }, readCapsLock: { state.capsLock }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), reconciliationInterval: 60)
            var events: [InputState] = []
            monitor.onChange = { events.append($0) }
            waitForMonitor(0.25)
            check(reads == 1, "steady state does not re-read TIS: \(reads)")
            state = InputState(source: english, capsLock: true)
            waitForMonitor(0.45)
            check(reads == 3 && events.map(\.symbol) == ["A"], "Caps Lock: one poll read + one deadline read; reads=\(reads)")
            state = InputState(source: english, capsLock: false)
            waitForMonitor(0.3)
            check(events.map(\.symbol) == ["A", "a"], "Caps Lock release still emits once")
            let baseline = reads
            for _ in 0..<100 { monitor.perform(NSSelectorFromString("sourceChanged")) }
            waitForMonitor(0.04)
            check(reads == baseline + 1, "100 same-loop notifications coalesce to one read: \(reads-baseline)")
        }

        do {
            var state: InputState? = InputState(source: english, capsLock: false)
            var reads = 0
            let monitor = InputSourceMonitor(readState: { reads += 1; return state }, readCapsLock: { false }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), reconciliationInterval: 60)
            var events: [InputState] = []
            monitor.onChange = { events.append($0) }
            state = nil
            monitor.refresh()
            waitForMonitor(0.18)
            check(reads == 2, "failed TIS read does not retry on every Caps Lock tick: \(reads)")
            state = InputState(source: chinese, capsLock: false)
            waitForMonitor(0.65)
            check(events.map(\.symbol) == ["中"], "transient notification read failure recovers without another notification")
        }

        do {
            var state: InputState? = InputState(source: english, capsLock: false)
            let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { false }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), reconciliationInterval: 60)
            var events: [InputState] = []
            monitor.onChange = { events.append($0) }
            state = InputState(source: chinese, capsLock: false)
            monitor.refresh()
            waitForMonitor(0.04)
            state = nil
            waitForMonitor(0.15)
            state = InputState(source: chinese, capsLock: false)
            waitForMonitor(0.7)
            check(events.map(\.symbol) == ["中"], "deadline read failure recovers without displaying an invalid candidate")
        }

        do {
            var state: InputState? = nil
            var reads = 0
            let monitor = InputSourceMonitor(readState: { reads += 1; return state }, readCapsLock: { false }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), reconciliationInterval: 60)
            var events: [InputState] = []
            monitor.onChange = { events.append($0) }
            waitForMonitor(0.3)
            check(reads == 1, "initial unavailability uses low-frequency recovery: \(reads)")
            state = InputState(source: english, capsLock: false)
            waitForMonitor(0.5)
            check(events.map(\.symbol) == ["a"], "initial unavailability recovers")
        }

        do {
            var state = InputState(source: chinese, capsLock: false)
            let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { state.capsLock }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), reconciliationInterval: 60)
            var symbols: [String] = []
            monitor.onChange = { symbols.append($0.symbol) }
            state = InputState(source: chinese, capsLock: true)
            monitor.refresh()
            waitForMonitor(0.1)
            state = InputState(source: english, capsLock: true)
            monitor.refresh()
            waitForMonitor(0.08)
            state = InputState(source: english, capsLock: false)
            monitor.refresh()
            waitForMonitor(0.4)
            check(symbols == ["a"], "Caps-first source change suppresses transient uppercase")
        }

        do {
            var state = InputState(source: chinese, capsLock: false)
            let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { state.capsLock }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), reconciliationInterval: 60)
            var symbols: [String] = []
            monitor.onChange = { symbols.append($0.symbol) }
            state = InputState(source: english, capsLock: false)
            monitor.refresh()
            waitForMonitor(0.03)
            state = InputState(source: english, capsLock: true)
            monitor.refresh()
            waitForMonitor(0.1)
            state = InputState(source: english, capsLock: false)
            monitor.refresh()
            waitForMonitor(0.4)
            check(symbols == ["a"], "Source-first change suppresses transient uppercase")
        }

        weak var released: InputSourceMonitor?
        var deadReads = 0
        autoreleasepool {
            let monitor = InputSourceMonitor(readState: { deadReads += 1; return nil }, readCapsLock: { false }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), reconciliationInterval: 60)
            released = monitor
            monitor.perform(NSSelectorFromString("sourceChanged"))
        }
        let deadBaseline = deadReads
        waitForMonitor(0.65)
        check(released == nil && deadReads == deadBaseline, "pending retry and queued notification do not retain destroyed monitor")
    }

    private static func checkRenderingReuse() {
        let state = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        let prompt = PromptView(backgroundOpacity: 0.55)
        let full = IndicatorView(backgroundOpacity: 0.55, scale: 1)
        let promptMask = prompt.maskImage
        let fullMask = full.maskImage
        for _ in 0..<1000 {
            prompt.updateBackgroundOpacity(0.55)
            prompt.display(state)
            full.updateScale(1)
            full.updateBackgroundOpacity(0.55)
            full.display(state)
        }
        check(prompt.maskImage === promptMask && full.maskImage === fullMask,
              "1000次同值更新复用中央/常驻蒙版，不重新分配")
        full.updateScale(2)
        check(full.maskImage !== fullMask && full.maskImage?.size == NSSize(width: 72, height: 72), "实际缩放会更新蒙版")
        prompt.updateBackgroundOpacity(0.3)
        check(prompt.maskImage !== promptMask, "实际透明度变化仍会刷新蒙版")
        let screen = IndicatorScreen(id: 42, frame: NSRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 0, safeRight: 0)
        let indicator = FullScreenIndicator(backgroundOpacity: 0.55)
        indicator.updateState(state)
        indicator.updateScreens([screen])
        let panel = indicator.panels[42]!
        let original = (panel.contentView as! IndicatorView).maskImage
        let origin = panel.frame
        for index in 0..<100 {
            indicator.updateState(InputState(source: state.source, capsLock: index % 2 == 0))
        }
        check((panel.contentView as! IndicatorView).maskImage === original && panel.frame == origin,
              "输入状态连续改变不会重新生成常驻背景或移动窗口")
        indicator.updateScreens([])

        let suite = "InputMethodPrompt.RenderReuse.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var changes = 0
        let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), loginItem: FakeLoginItem(),
            onChange: { _ in changes += 1 }, onPreview: {})
        let views = descendants(of: controller.window!.contentView!)
        let slider = views.first { $0.identifier?.rawValue == "backgroundTransparency" } as! NSSlider
        let preview = views.compactMap { $0 as? IndicatorView }.first!
        let mask = preview.maskImage
        for _ in 0..<100 { slider.doubleValue = 22.2; slider.sendAction(slider.action, to: slider.target) }
        check(changes == 0 && preview.maskImage === mask, "同百分比滑块事件不重复保存回调或刷新其他分类")
        slider.doubleValue = 35
        slider.sendAction(slider.action, to: slider.target)
        check(changes == 1 && preview.maskImage === mask, "切换提示调整只刷新本组，常驻预览不变")
        controller.close()
        var overlay: Overlay? = Overlay()
        overlay!.show(state)
        let orphanPanel = overlay!.panel
        overlay = nil
        check(!orphanPanel.isVisible, "中央提示对象释放时关闭残留浮层")
    }

    private static func checkFullScreenMonitorLifecycle() {
        var reads = 0
        let monitor = FullScreenMonitor(readScreens: { reads += 1; return [] })
        monitor.setEnabled(true)
        for _ in 0..<100 {
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        check(reads == 1, "连发通知不立即重复扫描全屏窗口")
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(reads == 2, "100个同轮屏幕通知合并成一次扫描")
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        monitor.setEnabled(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(reads == 2, "关闭全屏监控取消排队扫描")
        var reentrantReads = 0
        let screen = IndicatorScreen(id: 42, frame: NSRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 0, safeRight: 0)
        let reentrant = FullScreenMonitor(readScreens: { reentrantReads += 1; return [screen] })
        reentrant.onChange = { [weak reentrant] screens in if !screens.isEmpty { reentrant?.setEnabled(false) } }
        reentrant.setEnabled(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        check(reentrantReads == 1 && reentrant.current.isEmpty, "启动回调中禁用不会泄漏定时扫描")
    }

    private static func checkMouseIdlePollingLifecycle() {
        var now: TimeInterval = 0
        var cursor = true
        var reads = 0
        let screen = NSScreen.screens.first!.frame
        var mouse = NSPoint(x: screen.midX, y: screen.midY)
        let indicator = MouseIndicator(readMouseLocation: { mouse }, observeMouseEvents: false,
            readCursorVisible: { reads += 1; return cursor }, readTime: { now }, makeFrameClock: { _, _ in nil })
        let state = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        indicator.updateState(state)
        indicator.setEnabled(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        now = 3
        indicator.refreshVisibility()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let idleReads = reads
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        check(!indicator.panel.isVisible && reads == idleReads, "静止隐藏完成后停止鼠标可见性轮询")
        cursor = false
        indicator.updateIdleBehavior(.fade)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        check(reads > idleReads && !indicator.panel.isVisible, "改为淡化时重新读取真实指针状态，不用过期缓存闪现")
        cursor = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(indicator.panel.isVisible && abs(indicator.panel.alphaValue - 0.1) < 0.001, "淡化模式恢复可见性监控")
        indicator.updateIdleBehavior(.hide)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        now = 4
        cursor = false
        mouse.x += 1
        indicator.refreshPosition()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        check(!indicator.panel.isVisible, "停止轮询后指针隐藏再移动也不会因旧缓存闪现")
        cursor = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(indicator.panel.isVisible && indicator.panel.alphaValue == 0.5, "静止隐藏后移动会恢复监控和显示")
        indicator.setEnabled(false)
        for _ in 0..<5 {
            indicator.updateState(InputState(source: state.source, capsLock: true))
            indicator.setEnabled(false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.045))
        }
        check(!indicator.panel.isVisible, "禁用期间重复状态更新不会无限延后淡出")
    }

    private static func checkMouseEdgeStability() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        for scale in [0.5, 0.8, 1.0, 3.0] {
            let size = MouseIndicatorLayout.size(scale: scale)
            let rightThreshold = screen.maxX - 6 - 18 - size.width
            let bottomThreshold = screen.minY + 6 + 18 + size.height
            var placement = MouseIndicatorPlacement()
            var mouse = NSPoint(x: rightThreshold - 1, y: 500)
            var frame = placement.frame(at: mouse, in: [screen], scale: scale)!
            check(frame.minX > mouse.x, "边缘避让初始优先鼠标右侧（\(Int(scale * 100))%）")
            mouse.x += 2
            frame = placement.frame(at: mouse, in: [screen], scale: scale)!
            check(frame.maxX < mouse.x && screen.contains(frame), "右侧空间不足立即换到左侧且不越界")
            var stable = true
            for offset: CGFloat in [-2, 1, -1, 2, -3, 0] {
                mouse.x = rightThreshold + offset
                frame = placement.frame(at: mouse, in: [screen], scale: scale)!
                stable = stable && frame.maxX < mouse.x && screen.contains(frame)
            }
            check(stable, "换侧阈值附近来回移动不会左右跳动")
            mouse.x = rightThreshold - 13
            frame = placement.frame(at: mouse, in: [screen], scale: scale)!
            check(frame.minX > mouse.x, "离开边缘并留足12pt空间后恢复右侧")
            mouse = NSPoint(x: 500, y: bottomThreshold - 1)
            frame = placement.frame(at: mouse, in: [screen], scale: scale)!
            check(frame.minY > mouse.y, "底部不足时改到鼠标上方")
            mouse.y += 2
            frame = placement.frame(at: mouse, in: [screen], scale: scale)!
            check(frame.minY > mouse.y, "底部阈值附近不反复上下跳动")
            mouse.y = bottomThreshold + 13
            frame = placement.frame(at: mouse, in: [screen], scale: scale)!
            check(frame.maxY < mouse.y, "底部空间充分后恢复鼠标下方")
        }
        var placement = MouseIndicatorPlacement()
        _ = placement.frame(at: NSPoint(x: 1511, y: 400), in: [screen])
        let secondary = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let mouse = NSPoint(x: -100, y: 400)
        let crossed = placement.frame(at: mouse, in: [screen, secondary])!
        check(crossed.minX > mouse.x && secondary.contains(crossed), "跨屏重置换侧状态并兼容负坐标")
        let resizeMouse = NSPoint(x: 1420, y: 400)
        let large = placement.frame(at: resizeMouse, in: [screen], scale: 3)!
        let small = placement.frame(at: resizeMouse, in: [screen], scale: 0.5)!
        check(large.maxX < resizeMouse.x && small.minX > resizeMouse.x,
              "尺寸改变重新评估换侧，不继承过期的边缘状态")
    }

    private final class FakeMouseFrameClock: MouseFrameClock {
        private(set) var isRunning = false
        private(set) var invalidated = false
        let callback: () -> Void
        init(callback: @escaping () -> Void) { self.callback = callback }
        func resume() { if !invalidated { isRunning = true } }
        func pause() { isRunning = false }
        func invalidate() { invalidated = true; isRunning = false }
        func fire() { if isRunning { callback() } }
    }

    private static func checkMouseFramePacing() {
        let screen = NSScreen.screens.first!.frame
        var mouse = NSPoint(x: screen.midX, y: screen.midY)
        var reads = 0
        var clocks: [FakeMouseFrameClock] = []
        let state = InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false)
        var indicator: MouseIndicator? = MouseIndicator(readMouseLocation: { reads += 1; return mouse },
            readScreens: { [screen] }, observeMouseEvents: false, readCursorVisible: { true }, makeFrameClock: { _, callback in
                let clock = FakeMouseFrameClock(callback: callback)
                clocks.append(clock)
                return clock
            })
        indicator!.updateState(state)
        indicator!.setEnabled(true)
        let clock = clocks[0]
        let initialReads = reads
        mouse.x += 10
        indicator!.schedulePositionRefresh()
        check(reads == initialReads + 1 && clock.isRunning &&
              indicator!.panel.frame == MouseIndicatorLayout.frame(at: mouse, in: [screen]),
              "静止后首次移动立即跟随，不等待固定定时器")
        let burstReads = reads
        for index in 0..<200 {
            mouse.x = screen.midX + CGFloat(index)
            indicator!.schedulePositionRefresh()
        }
        check(reads == burstReads, "一帧内多次鼠标事件不重复提交窗口移动")
        // The callback must sample the cursor now, not replay the last event's coordinates.
        mouse.x += 20
        clock.fire()
        check(reads == burstReads + 1 && indicator!.panel.frame == MouseIndicatorLayout.frame(at: mouse, in: [screen]),
              "屏幕刷新时使用最新鼠标位置，无过期位置排队")
        let delayedReads = reads
        for _ in 0..<6 {
            mouse.x += 2
            clock.fire()
        }
        check(clock.isRunning && reads == delayedReads + 6 &&
              indicator!.panel.frame == MouseIndicatorLayout.frame(at: mouse, in: [screen]),
              "鼠标事件延迟时仍逐帧读取实际位置，持续移动不误判为空闲")
        let finalReads = reads
        clock.fire()
        clock.fire()
        check(clock.isRunning && reads == finalReads + 2, "连续两个位置不变帧保留短暂观察期")
        clock.fire()
        clock.fire()
        check(!clock.isRunning && reads == finalReads + 3, "三个位置不变帧后暂停且不继续读取位置")
        mouse.x += 10
        indicator!.schedulePositionRefresh()
        check(clock.isRunning && reads == finalReads + 4, "暂停后再次移动立即恢复跟随")
        mouse = NSPoint(x: screen.maxX + 100, y: screen.maxY + 100)
        clock.fire()
        check(!indicator!.panel.isVisible, "屏幕外位置隐藏标识")
        mouse = NSPoint(x: screen.midX, y: screen.midY)
        indicator!.schedulePositionRefresh()
        check(indicator!.panel.isVisible, "窗口隐藏后无需等待不可见窗口的刷新即可恢复")
        indicator!.setEnabled(false)
        let stoppedReads = reads
        clock.callback()
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        check(clock.invalidated && reads == stoppedReads && !indicator!.panel.isVisible,
              "关闭时销毁刷新源，迟到回调不能重新显示")
        indicator!.setEnabled(true)
        check(clocks.count == 2 && indicator!.panel.isVisible, "重新开启创建新的刷新源并显示当前状态")
        weak let released = indicator
        indicator = nil
        check(released == nil && clocks[1].invalidated, "屏幕同步回调不循环持有鼠标提示且析构完成清理")

        if #available(macOS 14.0, *) {
            var actualReads = 0
            var actualClock: DisplayLinkMouseFrameClock?
            let live = MouseIndicator(readMouseLocation: { actualReads += 1; return mouse },
                readScreens: { [screen] }, observeMouseEvents: false, readCursorVisible: { true }, makeFrameClock: { window, callback in
                    let clock = DisplayLinkMouseFrameClock(window: window, onFrame: callback)
                    actualClock = clock
                    return clock
                })
            live.updateState(state)
            live.setEnabled(true)
            let startingReads = actualReads
            mouse.x += 15
            live.schedulePositionRefresh()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            check(actualReads >= startingReads + 2 && actualClock?.isRunning == false,
                  "真实CADisplayLink收到屏幕刷新并在静止后暂停")
            live.setEnabled(false)
        }
    }

    private static func pumpAppEvents(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02),
                                          inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            NSApp.updateWindows()
        }
    }

    private static func checkNativeFullScreen() {
        guard let screen = NSScreen.screens.first,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            check(false, "真实全屏测试读取主屏")
            return
        }
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()
        let window = NSWindow(contentRect: screen.frame.insetBy(dx: 160, dy: 160),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "中英提示 · 全屏检测验证"
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pumpAppEvents(for: 0.5)
        let detected = { FullScreenDetection.screens(excludingProcessID: -1).contains { $0.id == number.uint32Value } }
        check(!detected(), "真实普通窗口不触发常驻标识")
        window.toggleFullScreen(nil)
        pumpAppEvents(for: 3)
        check(window.styleMask.contains(.fullScreen) && detected(), "真实原生全屏窗口可通过系统几何信息识别")
        let indicator = FullScreenIndicator(backgroundOpacity: 0.55)
        indicator.updateState(InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false))
        indicator.updateScreens(FullScreenDetection.screens(excludingProcessID: -1))
        pumpAppEvents(for: 0.3)
        if let panel = indicator.panels[number.uint32Value] {
            if !panel.isVisible || !panel.isOnActiveSpace || !window.isKeyWindow {
                print("全屏验证现场：visible=\(panel.isVisible), activeSpace=\(panel.isOnActiveSpace), fixtureKey=\(window.isKeyWindow), frontPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1), fixturePID=\(ProcessInfo.processInfo.processIdentifier)")
            }
            check(panel.isVisible && panel.isOnActiveSpace && window.isKeyWindow,
                  "真实全屏Space中常驻窗口可见且全屏主窗口保持焦点")
        } else { check(false, "真实全屏生成常驻窗口") }
        var fullScreenMouse = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        let mouseIndicator = MouseIndicator(readMouseLocation: { fullScreenMouse }, observeMouseEvents: false, readCursorVisible: { true })
        mouseIndicator.updateState(InputState(source: InputSource(id: "abc", name: "ABC", languages: ["en"]), capsLock: false))
        mouseIndicator.setEnabled(true)
        pumpAppEvents(for: 0.2)
        if !mouseIndicator.panel.isVisible || !mouseIndicator.panel.isOnActiveSpace || !window.isKeyWindow {
            print("鼠标提示验证现场：visible=\(mouseIndicator.panel.isVisible), activeSpace=\(mouseIndicator.panel.isOnActiveSpace), fixtureKey=\(window.isKeyWindow), frontPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1), fixturePID=\(ProcessInfo.processInfo.processIdentifier)")
        }
        check(mouseIndicator.panel.isVisible && mouseIndicator.panel.isOnActiveSpace && window.isKeyWindow,
              "真实全屏Space中鼠标提示可见且保持原窗口焦点")
        for index in 0..<20 {
            fullScreenMouse.x = screen.frame.midX + CGFloat(index * 2)
            mouseIndicator.schedulePositionRefresh()
            pumpAppEvents(for: 0.01)
        }
        pumpAppEvents(for: 0.1)
        check(mouseIndicator.panel.frame == MouseIndicatorLayout.frame(at: fullScreenMouse, in: [screen.frame]) &&
              mouseIndicator.panel.isOnActiveSpace && window.isKeyWindow,
              "真实全屏内持续移动经屏幕同步后到达最新位置且不抢焦点")
        mouseIndicator.setEnabled(false)
        indicator.updateScreens([])
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        pumpAppEvents(for: 3)
        // Exiting can reveal another app's full-screen Space. Check this fixture's
        // actual WindowServer geometry, rather than assuming the whole desktop is normal.
        let ownWindows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]]
        let ownBounds = ownWindows?.first?[kCGWindowBounds as String] as? [String: Any]
        let ownFrame = ownBounds.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let quartzScreen = CGRect(x: screen.frame.minX, y: 0, width: screen.frame.width, height: screen.frame.height)
        check(!window.styleMask.contains(.fullScreen) && ownFrame.map {
            !FullScreenDetection.coversScreen($0, screen: quartzScreen, safeTop: screen.safeAreaInsets.top,
                                               reservedTop: max(0, screen.frame.maxY - screen.visibleFrame.maxY))
        } == true, "退出原生全屏后测试窗口不再覆盖屏幕")
        window.close()
        NSApp.setActivationPolicy(.accessory)
        previous?.activate(options: [])
    }

    private static func checkSystemSwitch() {
        guard let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let originalID = InputSource.read(original)?.id else {
            check(false, "读取原输入源")
            return
        }
        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        guard let alternate = sources.first(where: {
            guard let source = InputSource.read($0) else { return false }
            return source.id != originalID && ["zh", "en"].contains(source.language)
        }), let alternateID = InputSource.read(alternate)?.id else {
            check(false, "至少需要两个已启用的中英文输入源")
            return
        }
        let monitor = InputSourceMonitor()
        var observed: [String] = []
        monitor.onChange = { observed.append($0.source.id) }
        defer {
            check(TISSelectInputSource(original) == noErr, "恢复原始输入源")
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            check(InputSource.current()?.id == originalID, "原始输入源恢复成功")
        }
        check(TISSelectInputSource(alternate) == noErr, "切换到另一输入源")
        let deadline = Date().addingTimeInterval(2)
        while !observed.contains(alternateID) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        check(observed.contains(alternateID) && monitor.current?.source.id == alternateID, "真实系统通知触发状态更新")
        check(TISSelectInputSource(original) == noErr, "切回原始输入源")
        let restoreDeadline = Date().addingTimeInterval(2)
        while observed.last != originalID && Date() < restoreDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        check(observed.last == originalID, "切回原输入源也收到真实系统通知")
        print("切换路径：\(originalID) → \(alternateID) → \(originalID)")
    }

    private static func checkCapsLockChanges(_ source: InputSource) {
        var capsLock = false
        let monitor = InputSourceMonitor(
            readState: { InputState(source: source, capsLock: capsLock) },
            readCapsLock: { capsLock }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter()
        )
        var observed: [InputState] = []
        monitor.onChange = { observed.append($0) }
        capsLock = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        check(observed.count == 1 && observed.last?.capsLock == true,
              "输入源不变时，Caps Lock 开启仍触发提示")
        check(observed.last?.symbol == "A" && observed.last?.caption == "大写锁定已开启",
              "大写锁定显示正确文案")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(observed.count == 1, "Caps Lock 保持开启时不重复提示")
        capsLock = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.30))
        check(observed.count == 2 && observed.last?.capsLock == false && observed.last?.symbol == "a",
              "关闭 Caps Lock 后恢复当前输入法提示")
    }

    private static func checkTransientCapsLockDuringSourceSwitch() {
        let chinese = InputSource(id: "pinyin", name: "拼音", languages: ["zh-Hans"])
        let english = InputSource(id: "abc", name: "ABC", languages: ["en"])
        var state = InputState(source: chinese, capsLock: false)
        let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { state.capsLock }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
        var symbols: [String] = []
        monitor.onChange = { symbols.append($0.symbol) }

        // Caps Lock and TIS notifications are separate; either may arrive first.
        state = InputState(source: chinese, capsLock: true)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        state = InputState(source: english, capsLock: true)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        state = InputState(source: english, capsLock: false)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.40))
        check(symbols == ["a"], "中转英的临时 Caps Lock 状态不能闪出 A；实际：\(symbols)")
    }

    private static func checkSourceBeforeCapsLock() {
        let chinese = InputSource(id: "pinyin", name: "拼音", languages: ["zh-Hans"])
        let english = InputSource(id: "abc", name: "ABC", languages: ["en"])
        var state = InputState(source: chinese, capsLock: false)
        let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { state.capsLock }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
        var symbols: [String] = []
        monitor.onChange = { symbols.append($0.symbol) }
        state = InputState(source: english, capsLock: false)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        state = InputState(source: english, capsLock: true)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        state = InputState(source: english, capsLock: false)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        check(symbols == ["a"], "输入源通知先到也只显示一次 a；实际：\(symbols)")
    }

    private static func checkCancelledCapsLockAndFinalReread() {
        let english = InputSource(id: "abc", name: "ABC", languages: ["en"])
        var state = InputState(source: english, capsLock: false)
        let monitor = InputSourceMonitor(readState: { state }, readCapsLock: { state.capsLock }, sourceNotifications: NotificationCenter(), workspaceNotifications: NotificationCenter())
        var symbols: [String] = []
        monitor.onChange = { symbols.append($0.symbol) }
        state = InputState(source: english, capsLock: true)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        state = InputState(source: english, capsLock: false)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        check(symbols.isEmpty, "恢复原状态时取消待显示的大写提示")

        state = InputState(source: english, capsLock: true)
        monitor.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        state = InputState(source: english, capsLock: false)
        // No notification or explicit refresh: the deadline itself must re-read.
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        check(symbols.isEmpty && monitor.current?.capsLock == false,
              "提交前重新读取状态，不显示已经失效的 A")
    }
}

private final class FakeLoginItem: LoginItemManaging {
    var status: LoginItemStatus = .disabled
    var needsApproval = false
    var failure: Error?
    var changeCount = 0
    var openCount = 0

    func setEnabled(_ enabled: Bool) throws {
        changeCount += 1
        if let failure { throw failure }
        status = enabled ? (needsApproval ? .requiresApproval : .enabled) : .disabled
    }

    func openSystemSettings() { openCount += 1 }
}
