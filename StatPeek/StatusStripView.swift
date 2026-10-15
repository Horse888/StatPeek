import AppKit

extension MetricColor {
    init?(nsColor: NSColor) {
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard channels.allSatisfy({ $0.isFinite }) else { return nil }
        let bytes = channels.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        self.init(rawValue: String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]))
    }

    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .orange: .systemOrange
        case .purple: .systemPurple
        case .green: .systemGreen
        case .red: .systemRed
        case .neutral: .labelColor
        case .custom(let hex):
            if let number = UInt32(hex.dropFirst(), radix: 16) {
                NSColor(srgbRed: CGFloat((number >> 16) & 255) / 255,
                        green: CGFloat((number >> 8) & 255) / 255,
                        blue: CGFloat(number & 255) / 255, alpha: 1)
            } else { NSColor.labelColor }
        }
    }
}

@MainActor
final class StatusStripView: NSView {
    private var rows: [[Metric]] = []
    private var readings: [Metric: String] = [:]
    private var colors: [Metric: MetricColor] = [:]
    private var layout = StatusStripLayout(rows: [], readings: [:])
    private let textFont = StatusStripText.makeFont()
    override var isFlipped: Bool { true }
    var requiredWidth: CGFloat { layout.width }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func update(rows: [[Metric]], readings: [Metric: String], selection: MetricSelection) {
        self.rows = rows
        self.readings = readings
        layout = StatusStripLayout(rows: rows, readings: readings)
        self.colors = Dictionary(uniqueKeysWithValues: Metric.allCases.map { ($0, selection.color(for: $0)) })
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if rows.isEmpty {
            drawSymbol("chart.bar", color: .labelColor,
                       in: NSRect(x: (bounds.width - 14) / 2, y: (bounds.height - 14) / 2, width: 14, height: 14))
            return
        }
        let rowHeight: CGFloat = 11
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let top = (bounds.height - CGFloat(rows.count) * rowHeight) / 2
        for (rowIndex, metrics) in rows.enumerated() {
            for (columnIndex, metric) in metrics.enumerated() {
                let color = ((colors[metric] ?? .neutral).nsColor.usingColorSpace(.sRGB) ?? .black).cgColor
                let x = layout.origin(of: columnIndex)
                let y = top + CGFloat(rowIndex) * rowHeight
                StatusStripText.draw(metric.abbreviation, at: NSPoint(x: x, y: y - 0.5),
                                     font: textFont, color: color, in: context)
                StatusStripText.draw(metric.compact(readings[metric]),
                                     at: NSPoint(x: x + StatusStripLayout.labelWidth + StatusStripLayout.labelGap, y: y - 0.5),
                                     font: textFont, color: color, in: context)
            }
        }
    }

    private func drawSymbol(_ name: String, color: NSColor, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
