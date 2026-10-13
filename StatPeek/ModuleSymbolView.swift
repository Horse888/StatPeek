import AppKit
import Symbols

/// Decorative symbols stay inside the popover; status-bar labels remain D/C/M/G.
@MainActor
final class ModuleSymbolView: NSImageView {
    var permitsAnimation = true
    private var isAnimating = false

    init(name: String, color: NSColor, frame: NSRect, pointSize: CGFloat = 16) {
        super.init(frame: frame)
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
        contentTintColor = color
        imageScaling = .scaleProportionallyDown
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setAnimating(_ animate: Bool) {
        guard animate != isAnimating else { return }
        isAnimating = animate
        // Play the native entrance once per visible presentation, never on metric refresh.
        if #available(macOS 14.0, *) {
            if animate {
                addSymbolEffect(.bounce.byLayer, options: .nonRepeating.speed(0.8))
            } else {
                removeAllSymbolEffects(animated: false)
            }
        }
    }
}
