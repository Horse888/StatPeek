import AppKit
import Charts
import SwiftUI

@MainActor
final class DiskHistoryViewController: NSViewController {
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

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 396))
        let heading = NSTextField(labelWithString: "最近记录的剩余空间")
        heading.font = .systemFont(ofSize: 12)
        heading.textColor = .secondaryLabelColor
        heading.frame = NSRect(x: 20, y: 366, width: 340, height: 20)
        view.addSubview(heading)
        amount.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        amount.frame = NSRect(x: 20, y: 326, width: 340, height: 36)
        amount.setAccessibilityIdentifier("disk-history-amount")
        view.addSubview(amount)
        change.font = .systemFont(ofSize: 14, weight: .medium)
        change.frame = NSRect(x: 20, y: 294, width: 340, height: 24)
        change.setAccessibilityIdentifier("disk-history-change")
        view.addSubview(change)
        timestamp.font = .systemFont(ofSize: 11)
        timestamp.textColor = .secondaryLabelColor
        timestamp.frame = NSRect(x: 20, y: 270, width: 340, height: 20)
        view.addSubview(timestamp)
        let ranges = NSSegmentedControl(labels: ["24 小时", "7 天", "全部"], trackingMode: .selectOne,
                                        target: self, action: #selector(changeRange(_:)))
        ranges.selectedSegment = range.rawValue
        ranges.frame = NSRect(x: 20, y: 236, width: 225, height: 26)
        ranges.setAccessibilityIdentifier("disk-history-range")
        view.addSubview(ranges)
        let unit = NSTextField(labelWithString: "剩余空间（G）")
        unit.font = .systemFont(ofSize: 10)
        unit.textColor = .secondaryLabelColor
        unit.frame = NSRect(x: 20, y: 213, width: 340, height: 18)
        view.addSubview(unit)
        let hosting = NSHostingView(rootView: DiskHistoryChart(samples: [], range: range, now: Date()))
        hosting.frame = NSRect(x: 20, y: 60, width: 340, height: 150)
        view.addSubview(hosting)
        chart = hosting
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.frame = NSRect(x: 20, y: 30, width: 340, height: 20)
        footer.setAccessibilityIdentifier("disk-history-schedule")
        view.addSubview(footer)
        note.font = .systemFont(ofSize: 10)
        note.frame = NSRect(x: 20, y: 0, width: 340, height: 28)
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
            note.textColor = recordingError == nil ? .secondaryLabelColor : .systemRed
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

    @objc private func changeRange(_ sender: NSSegmentedControl) {
        range = DiskHistoryRange(rawValue: sender.selectedSegment) ?? .day
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
                    .foregroundStyle(Color.accentColor)
                    if samples.count <= 48 {
                        PointMark(x: .value("时间", point.sample.date),
                                  y: .value("剩余空间 G", Double(point.sample.availableBytes) / 1_000_000_000))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(12)
                    }
                }
                .chartXScale(domain: timeDomain)
                .chartYScale(domain: spaceDomain)
                .chartLegend(.hidden)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) { Text(String(format: "%.1f", amount)) }
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
