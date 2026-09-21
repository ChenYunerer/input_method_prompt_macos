import AppKit

enum SelfCheck {
    static func run() -> Int32 {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }
        func wait(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }

        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let overlay = Overlay()
        let chinese = InputSource(id: "test.zh", name: "拼音", languages: ["zh-Hans"])
        let english = InputSource(id: "test.en", name: "ABC", languages: ["en"])
        check(InputSource.current() != nil, "能够读取系统真实输入源")
        overlay.show(chinese)
        check(overlay.panel.isVisible, "中央提示可见")
        check(!overlay.panel.canBecomeKey && overlay.panel.ignoresMouseEvents, "提示不接收键盘或鼠标输入")
        check(overlay.panel.alphaValue == 0, "首次显示从透明开始")
        wait(0.05)
        let enteringAlpha = overlay.panel.alphaValue
        check(enteringAlpha > 0 && enteringAlpha < 1, "出现时逐渐淡入")
        overlay.show(english)
        check(overlay.panel.alphaValue == enteringAlpha, "淡入期间切换不重置透明度")
        wait(0.25)
        check(overlay.panel.isVisible && overlay.panel.alphaValue == 1, "淡入完成后完整显示")
        overlay.show(english)
        wait(0.30)
        check(overlay.panel.isVisible, "连续切换后，旧计时器不会提前关闭新提示")
        wait(0.28)
        check(overlay.panel.isVisible && overlay.panel.alphaValue > 0 && overlay.panel.alphaValue < 1,
              "停留 0.5 秒后进入渐隐过程")
        let leavingAlpha = overlay.panel.alphaValue
        overlay.show(chinese)
        check(overlay.panel.alphaValue == leavingAlpha, "淡出过程中再次切换从当前透明度平滑恢复")
        wait(0.25)
        check(overlay.panel.isVisible && overlay.panel.alphaValue == 1, "旧动画不会隐藏新提示")
        wait(0.60)
        check(!overlay.panel.isVisible, "淡出完成后关闭窗口")
        check(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost, "原来的前台应用保持不变")
        print("自检完成，失败数：\(failures)")
        return failures == 0 ? 0 : 1
    }
}
