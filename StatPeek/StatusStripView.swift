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
    private var stripLayout = StatusStripLayout(rows: [], readings: [:])
    private var fields: [Metric: (label: NSTextField, value: NSTextField)] = [:]
    private let emptySymbol = NSImageView()
    override var isFlipped: Bool { true }
    var requiredWidth: CGFloat { stripLayout.width }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for metric in Metric.allCases {
            let label = Self.textField()
            let value = Self.textField()
            fields[metric] = (label, value)
            addSubview(label)
            addSubview(value)
        }
        emptySymbol.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil)
        emptySymbol.contentTintColor = .labelColor
        emptySymbol.imageScaling = .scaleProportionallyDown
        emptySymbol.setAccessibilityElement(false)
        addSubview(emptySymbol)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func textField() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = StatusStripText.nativeFont()
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.setAccessibilityElement(false)
        return field
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func update(rows: [[Metric]], readings: [Metric: String], selection: MetricSelection) {
        self.rows = rows
        stripLayout = StatusStripLayout(rows: rows, readings: readings)
        let visible = Set(rows.flatMap { $0 })
        for metric in Metric.allCases {
            guard let pair = fields[metric] else { continue }
            pair.label.stringValue = metric.abbreviation
            pair.value.stringValue = metric.compact(readings[metric])
            pair.label.textColor = selection.color(for: metric).nsColor
            pair.value.textColor = pair.label.textColor
            pair.label.isHidden = !visible.contains(metric)
            pair.value.isHidden = pair.label.isHidden
        }
        emptySymbol.isHidden = !rows.isEmpty
        layoutLabels()
    }

    /// Native controls draw once per reading update. The status item displays
    /// only this image, so AppKit replica snapshots cannot relayout these fields.
    func snapshotImage(appearance: NSAppearance) -> NSImage {
        self.appearance = appearance
        let image = NSImage(size: bounds.size)
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = bounds.size
            appearance.performAsCurrentDrawingAppearance { cacheDisplay(in: bounds, to: bitmap) }
            image.addRepresentation(bitmap)
        }
        image.isTemplate = false
        return image
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLabels()
    }

    override func layout() {
        super.layout()
        layoutLabels()
    }

    private func layoutLabels() {
        // Status-item replica snapshots can invoke layout again. Reassigning an
        // unchanged native control frame requests another replica and never idles.
        let emptyFrame = NSRect(x: (bounds.width - 14) / 2, y: (bounds.height - 14) / 2, width: 14, height: 14)
        if emptySymbol.frame != emptyFrame { emptySymbol.frame = emptyFrame }
        let rowHeight: CGFloat = 12
        let top = (bounds.height - CGFloat(rows.count) * rowHeight) / 2
        for (rowIndex, metrics) in rows.enumerated() {
            for (columnIndex, metric) in metrics.enumerated() {
                guard let pair = fields[metric] else { continue }
                let x = stripLayout.origin(of: columnIndex)
                let y = top + CGFloat(rowIndex) * rowHeight
                let labelFrame = NSRect(x: x, y: y, width: StatusStripLayout.labelWidth, height: rowHeight)
                let valueFrame = NSRect(x: x + StatusStripLayout.labelWidth + StatusStripLayout.labelGap,
                                        y: y, width: stripLayout.columnWidths[columnIndex] - StatusStripLayout.labelWidth - StatusStripLayout.labelGap,
                                        height: rowHeight)
                if pair.label.frame != labelFrame { pair.label.frame = labelFrame }
                if pair.value.frame != valueFrame { pair.value.frame = valueFrame }
            }
        }
    }
}
