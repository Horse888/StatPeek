import AppKit
import Charts
import SwiftUI

@MainActor
final class DiskHistoryViewController: NSViewController {
    var contentWidth: CGFloat = 340
    var store: DiskHistoryStore?
    var nextRecordingDate: Date?
    var recordingError: String?
    private var range: DiskHistoryRange = .day
    private let amount = NSTextField(labelWithString: "暂无记录")
    private let change = NSTextField(labelWithString: "")
    private let timestamp = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let note = NSTextField(wrappingLabelWithString: "")
    private var chart: NSHostingView<DiskHistoryChart>?
    private var rangeButtons: [NSButton] = []
    private var rangeSurfaces: [GlassSurfaceView] = []

    override func loadView() {
        let innerWidth = contentWidth - 28
        view = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 304))
        let heading = NSTextField(labelWithString: "最近记录的剩余空间")
        heading.font = .systemFont(ofSize: 10)
        heading.textColor = .dashboardSecondaryLabel
        heading.frame = NSRect(x: 14, y: 284, width: innerWidth, height: 16)
        view.addSubview(heading)
        amount.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        amount.frame = NSRect(x: 14, y: 252, width: innerWidth, height: 30)
        amount.textColor = .systemTeal
        amount.setAccessibilityIdentifier("disk-history-amount")
        view.addSubview(amount)
        change.font = .systemFont(ofSize: 11, weight: .medium)
        change.frame = NSRect(x: 14, y: 232, width: innerWidth, height: 18)
        change.setAccessibilityIdentifier("disk-history-change")
        view.addSubview(change)
        timestamp.font = .systemFont(ofSize: 10)
        timestamp.textColor = .dashboardSecondaryLabel
        timestamp.lineBreakMode = .byWordWrapping
        timestamp.maximumNumberOfLines = 2
        timestamp.frame = NSRect(x: 14, y: 206, width: innerWidth, height: 24)
        view.addSubview(timestamp)
        for (index, label) in ["24 小时", "7 天", "全部"].enumerated() {
            let width = (innerWidth - 12) / 3
            let surface = GlassSurfaceView(frame: NSRect(x: 14 + CGFloat(index) * (width + 6), y: 178, width: width, height: 24))
            let button = NSButton(title: label, target: self, action: #selector(changeRange(_:)))
            button.isBordered = false
            button.tag = index
            button.frame = surface.content.bounds
            button.setAccessibilityIdentifier("history-range-\(index)")
            surface.content.addSubview(button)
            view.addSubview(surface)
            rangeButtons.append(button)
            rangeSurfaces.append(surface)
        }
        updateRangeControls()
        let unit = NSTextField(labelWithString: "剩余空间（G）")
        unit.font = .systemFont(ofSize: 10)
        unit.textColor = .dashboardSecondaryLabel
        unit.frame = NSRect(x: 14, y: 160, width: innerWidth, height: 16)
        view.addSubview(unit)
        let hosting = NSHostingView(rootView: DiskHistoryChart(samples: [], range: range, now: Date()))
        hosting.frame = NSRect(x: 14, y: 54, width: innerWidth, height: 104)
        hosting.setAccessibilityIdentifier("disk-history-chart")
        view.addSubview(hosting)
        chart = hosting
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .dashboardSecondaryLabel
        footer.lineBreakMode = .byWordWrapping
        footer.maximumNumberOfLines = 2
        footer.frame = NSRect(x: 14, y: 28, width: innerWidth, height: 22)
        footer.setAccessibilityIdentifier("disk-history-schedule")
        view.addSubview(footer)
        note.font = .systemFont(ofSize: 10)
        note.frame = NSRect(x: 14, y: 0, width: innerWidth, height: 26)
        note.setAccessibilityIdentifier("disk-history-note")
        view.addSubview(note)
    }

    func reload() {
        _ = view
        let now = Date()
        do {
            let latest = try store?.latestSamples() ?? []
            let samples = try store?.samples(since: range.startDate(at: now)) ?? []
            let count = try store?.count() ?? 0
            if let last = latest.last {
                let comparison = DiskComparison(latest: last, previous: latest.count > 1 ? latest[0] : nil)
                amount.stringValue = DiskFormatter.format(bytes: last.availableBytes)
                change.stringValue = comparison.summary
                // Direction is conveyed by text, with a stable neutral reading for contrast.
                change.textColor = .labelColor
                let previousTime = comparison.deltaBytes == nil ? "" : " · 对比 " + time(latest[0].date)
                timestamp.stringValue = "记录于 " + time(last.date) + previousTime
            } else {
                amount.stringValue = "暂无记录"
                change.stringValue = "首次成功采样后建立比较基准"
                timestamp.stringValue = ""
            }
            chart?.rootView = DiskHistoryChart(samples: DiskChartSampling.reduce(samples), range: range, now: now)
            let next = nextRecordingDate.map { " · 下次 " + time($0) } ?? ""
            footer.stringValue = "累计 \(count) 条记录" + next
            note.stringValue = recordingError ?? "每 5 分钟记录 · 只保存在本机，不自动弹出提示"
            note.textColor = recordingError == nil ? .dashboardSecondaryLabel : .systemRed
            note.toolTip = note.stringValue
        } catch {
            note.stringValue = error.localizedDescription
            note.textColor = .systemRed
            note.toolTip = error.localizedDescription
        }
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func updateRangeControls() {
        for (index, button) in rangeButtons.enumerated() {
            let selected = index == range.rawValue
            button.state = selected ? .on : .off
            button.attributedTitle = NSAttributedString(string: button.title,
                attributes: [.foregroundColor: selected ? NSColor.controlAccentColor : NSColor.labelColor,
                             .font: NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .regular)])
            rangeSurfaces[index].tintColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.12) : nil
        }
    }

    @objc private func changeRange(_ sender: NSButton) {
        range = DiskHistoryRange(rawValue: sender.tag) ?? .day
        updateRangeControls()
        reload()
    }
}

private struct DiskChartPoint: Identifiable {
    let sample: DiskSample
    let segment: Int
    var id: Int64 { sample.id }
}

private struct DiskHistoryChart: View {
    let samples: [DiskSample]
    let range: DiskHistoryRange
    let now: Date

    private var lineGradient: LinearGradient {
        let domain = timeDomain
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let first = samples.map(\.date).min() ?? domain.lowerBound
        let last = samples.map(\.date).max() ?? domain.upperBound
        // Keep the gradient across the actual history, even within a sparse 24-hour view.
        let start = UnitPoint(x: first.timeIntervalSince(domain.lowerBound) / span, y: 0.5)
        let end = UnitPoint(x: last.timeIntervalSince(domain.lowerBound) / span, y: 0.5)
        return LinearGradient(colors: [.blue, .indigo, .purple],
                              startPoint: first < last ? start : .leading,
                              endPoint: first < last ? end : .trailing)
    }

    private var points: [DiskChartPoint] {
        var segment = 0
        return samples.enumerated().map { index, sample in
            if index > 0, sample.volumeID != samples[index - 1].volumeID || sample.date <= samples[index - 1].date {
                segment += 1
            }
            return DiskChartPoint(sample: sample, segment: segment)
        }
    }

    private var timeDomain: ClosedRange<Date> {
        let lower = range.startDate(at: now) ?? samples.map(\.date).min() ?? now.addingTimeInterval(-1800)
        let upper = max(now, samples.map(\.date).max() ?? now)
        return min(lower, upper.addingTimeInterval(-1800))...upper
    }

    private var axisDateFormat: Date.FormatStyle {
        if range == .day { return .dateTime.hour().minute() }
        let calendar = Calendar.current
        if range == .all,
           calendar.component(.year, from: timeDomain.lowerBound) != calendar.component(.year, from: timeDomain.upperBound) {
            return .dateTime.year().month(.twoDigits).day(.twoDigits)
        }
        return .dateTime.month(.twoDigits).day(.twoDigits)
    }

    private var spaceDomain: ClosedRange<Double> {
        let values = samples.map { Double($0.availableBytes) / 1_000_000_000 }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max(0.1, (high - low) * 0.15)
        return max(0, low - padding)...(high + padding)
    }

    var body: some View {
        VStack(spacing: 4) {
            if samples.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                    Text("此范围暂无记录")
                    Text("后台每 5 分钟采样一次").font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("时间", point.sample.date),
                             y: .value("剩余空间 G", Double(point.sample.availableBytes) / 1_000_000_000),
                             series: .value("连续记录", point.segment))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(lineGradient)
                    .alignsMarkStylesWithPlotArea()
                    if samples.count <= 48 {
                        PointMark(x: .value("时间", point.sample.date),
                                  y: .value("剩余空间 G", Double(point.sample.availableBytes) / 1_000_000_000))
                        .foregroundStyle(lineGradient)
                        .alignsMarkStylesWithPlotArea()
                        .symbolSize(12)
                    }
                }
                .chartXScale(domain: timeDomain)
                .chartYScale(domain: spaceDomain)
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: axisDateFormat)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) { Text(String(format: "%.1f", amount)).foregroundStyle(.secondary) }
                        }
                    }
                }
                .accessibilityLabel("磁盘剩余空间历史曲线")
                if samples.count == 1 {
                    Text("已有 1 条记录，再次采样后显示变化曲线")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
