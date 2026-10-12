import AppKit

extension MetricColor {
    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .orange: .systemOrange
        case .purple: .systemPurple
        case .green: .systemGreen
        case .red: .systemRed
        case .neutral: .labelColor
        }
    }
}

@MainActor
final class StatusStripView: NSView {
    private var rows: [[Metric]] = []
    private var readings: [Metric: String] = [:]
    private var colors: [Metric: MetricColor] = [:]
    private var layout = StatusStripLayout(rows: [], readings: [:])
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
        let top = (bounds.height - CGFloat(rows.count) * rowHeight) / 2
        for (rowIndex, metrics) in rows.enumerated() {
            for (columnIndex, metric) in metrics.enumerated() {
                let color = (colors[metric] ?? .neutral).nsColor
                let x = layout.origin(of: columnIndex)
                let y = top + CGFloat(rowIndex) * rowHeight
                drawSymbol(metric.symbol, color: color, in: NSRect(x: x, y: y + 1, width: 10, height: 9))
                let text = NSAttributedString(string: metric.compact(readings[metric]), attributes: [
                    .font: StatusStripLayout.font,
                    .foregroundColor: color
                ])
                text.draw(at: NSPoint(x: x + StatusStripLayout.iconWidth + StatusStripLayout.iconGap, y: y - 0.5))
            }
        }
    }

    private func drawSymbol(_ name: String, color: NSColor, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
