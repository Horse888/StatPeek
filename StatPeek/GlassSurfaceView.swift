import AppKit

extension NSColor {
    /// Resolve inside the drawing appearance. Applying alpha to labelColor while
    /// constructing a view can otherwise freeze its light-mode color on glass.
    static var dashboardSecondaryLabel: NSColor {
        NSColor(name: nil) { appearance in
            var resolved = NSColor.secondaryLabelColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = (NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor)
                    .withAlphaComponent(0.68)
            }
            return resolved
        }
    }
}

@MainActor
final class GlassSurfaceView: NSView {
    let content = NSView()
    private let effect: NSView
    var tintColor: NSColor? {
        didSet {
            if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
                glass.tintColor = tintColor
            }
        }
    }

    init(frame: NSRect, cornerRadius: CGFloat? = nil, interactive: Bool = true) {
        let radius = cornerRadius ?? frame.height / 2
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: frame.size))
            glass.cornerRadius = radius
            glass.style = .regular
            if #available(macOS 27.0, *) { glass.effectIsInteractive = interactive }
            effect = glass
        } else {
            let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = radius
            material.layer?.masksToBounds = true
            effect = material
        }
        super.init(frame: frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        effect.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
            glass.contentView = content
        } else {
            effect.addSubview(content)
        }
        addSubview(effect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
