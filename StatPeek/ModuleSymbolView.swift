import AppKit
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
        // Breathe is native to SF Symbols on macOS 15+. Older systems stay static.
        if #available(macOS 15.0, *) {
            if animate {
                addSymbolEffect(.breathe.plain.byLayer, options: .repeating.speed(0.65))
            } else {
                removeAllSymbolEffects()
            }
        }
    }
}
