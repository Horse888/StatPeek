import AppKit
import QuartzCore
import Symbols

/// Decorative symbols stay inside the popover; status-bar labels remain D/C/M/G.
@MainActor
final class ModuleSymbolView: NSImageView {
    private var isAnimating = false

    init(name: String, color: NSColor, frame: NSRect) {
        super.init(frame: frame)
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        contentTintColor = color
        imageScaling = .scaleProportionallyDown
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setAnimating(_ animate: Bool) {
        guard animate != isAnimating else { return }
        isAnimating = animate
        if #available(macOS 14.0, *) {
            if animate {
                addSymbolEffect(.pulse.wholeSymbol, options: .repeating.speed(0.45))
            } else {
                removeAllSymbolEffects()
            }
        } else {
            wantsLayer = true
            if animate {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 0.65
                pulse.toValue = 1.0
                pulse.duration = 1.5
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer?.add(pulse, forKey: "module-pulse")
            } else {
                layer?.removeAnimation(forKey: "module-pulse")
            }
        }
    }
}
