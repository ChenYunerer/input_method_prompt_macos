import AppKit

enum PromptStyle {
    // Use the same corner proportion for both prompt sizes, including scaled indicators.
    static func cornerRadius(for size: NSSize) -> CGFloat {
        min(size.width, size.height) * (24.0 / 148.0)
    }
}

final class PromptView: NSVisualEffectView {
    static let size = NSSize(width: 148, height: 148)
    private var appliedOpacity: CGFloat?
    private var displayedState: InputState?
    private let symbolLabel = NSTextField(labelWithString: "中")
    private let captionLabel = NSTextField(labelWithString: "中文输入")

    init(backgroundOpacity: Double) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        symbolLabel.font = .systemFont(ofSize: 54, weight: .medium)
        symbolLabel.textColor = .labelColor
        symbolLabel.alignment = .center
        symbolLabel.frame = NSRect(x: 8, y: 55, width: 132, height: 68)
        captionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.frame = NSRect(x: 8, y: 27, width: 132, height: 19)
        addSubview(symbolLabel)
        addSubview(captionLabel)
        updateBackgroundOpacity(backgroundOpacity)
    }

    required init?(coder: NSCoder) { nil }

    func display(_ input: InputState) {
        guard displayedState != input else { return }
        displayedState = input
        symbolLabel.stringValue = input.symbol
        captionLabel.stringValue = input.caption
    }

    func updateBackgroundOpacity(_ opacity: Double) {
        let alpha = CGFloat(min(1, max(0, opacity)))
        guard alpha != appliedOpacity else { return }
        appliedOpacity = alpha
        let radius = PromptStyle.cornerRadius(for: Self.size)
        // The material mask clips the WindowServer blur, without fading the labels.
        maskImage = NSImage(size: Self.size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        needsDisplay = true
    }
}
