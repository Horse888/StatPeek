import AppKit

/// Aligns the two rows while reserving room for full utilization and disk unit changes.
struct StatusStripLayout {
    static let sidePadding: CGFloat = 2
    static let labelWidth: CGFloat = 10
    static let labelGap: CGFloat = 2
    static let columnGap: CGFloat = 3
    let columnWidths: [CGFloat]

    init(rows: [[Metric]], readings: [Metric: String]) {
        var widths: [CGFloat] = []
        for column in 0..<(rows.map(\.count).max() ?? 0) {
            var widest: CGFloat = 0
            for row in rows where column < row.count {
                let metric = row[column]
                let reserved = metric == .disk
                    ? ["B", "K", "M", "G", "T", "P", "E"].map { "999.9" + $0 }
                    : ["100.0%"]
                for text in reserved + [metric.compact(readings[metric])] {
                    widest = max(widest, Self.textWidth(text))
                }
            }
            widths.append(Self.labelWidth + Self.labelGap + ceil(widest))
        }
        columnWidths = widths
    }

    var width: CGFloat {
        columnWidths.isEmpty ? 22 : Self.sidePadding * 2 + columnWidths.reduce(0, +)
            + CGFloat(columnWidths.count - 1) * Self.columnGap
    }

    func origin(of column: Int) -> CGFloat {
        Self.sidePadding + columnWidths.prefix(column).reduce(0, +) + CGFloat(column) * Self.columnGap
    }

    static func textWidth(_ text: String) -> CGFloat {
        StatusStripText.width(text) + 4 // Native NSTextField cell insets.
    }
}
