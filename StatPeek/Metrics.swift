import Foundation

enum Metric: String, CaseIterable {
    case disk, cpu, memory, gpu

    var title: String {
        switch self {
        case .disk: "磁盘剩余空间"
        case .cpu: "CPU 使用率"
        case .memory: "内存使用率（估算）"
        case .gpu: "GPU 使用率"
        }
    }
}

extension Metric {
    var abbreviation: String {
        switch self {
        case .disk: "D"
        case .cpu: "C"
        case .memory: "M"
        case .gpu: "G"
        }
    }

    func compact(_ value: String?) -> String {
        guard let value else { return "…" }
        if value == "采样中…" { return "…" }
        if value == "不可用" { return "—" }
        return value.replacingOccurrences(of: " ", with: "")
    }
}

enum MetricColor: Equatable, CaseIterable, RawRepresentable {
    case blue, orange, purple, green, red, neutral
    case custom(String)

    static let allCases: [MetricColor] = [.blue, .orange, .purple, .green, .red, .neutral]

    init?(rawValue: String) {
        switch rawValue {
        case "blue": self = .blue
        case "orange": self = .orange
        case "purple": self = .purple
        case "green": self = .green
        case "red": self = .red
        case "neutral": self = .neutral
        default:
            guard rawValue.count == 7, rawValue.first == "#",
                  rawValue.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            self = .custom(rawValue.uppercased())
        }
    }

    var rawValue: String {
        switch self {
        case .blue: "blue"
        case .orange: "orange"
        case .purple: "purple"
        case .green: "green"
        case .red: "red"
        case .neutral: "neutral"
        case .custom(let hex): hex
        }
    }

    var title: String {
        switch self {
        case .blue: "蓝色"
        case .orange: "橙色"
        case .purple: "紫色"
        case .green: "绿色"
        case .red: "红色"
        case .neutral: "默认文字色"
        case .custom(let hex): hex
        }
    }

    static func defaultColor(for metric: Metric) -> MetricColor {
        switch metric {
        case .disk: .blue
        case .cpu: .orange
        case .memory: .purple
        case .gpu: .green
        }
    }
}

enum StatusLayout {
    static func rows(for selected: Set<Metric>) -> [[Metric]] {
        let ordered = Metric.allCases.filter { selected.contains($0) }
        guard !ordered.isEmpty else { return [] }
        let split = (ordered.count + 1) / 2
        return [Array(ordered.prefix(split)), Array(ordered.dropFirst(split))].filter { !$0.isEmpty }
    }
}

enum DiskFormatter {
    static func format(bytes: Int64) -> String {
        guard bytes >= 0 else { return "不可用" }
        let units = ["B", "K", "M", "G", "T", "P", "E"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        // Keep one decimal and promote values that round across a unit boundary.
        if (value * 10).rounded() / 10 >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return String(format: "%.1f%@", value, units[unit])
    }
}

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func utilization(since previous: CPUTicks) -> Double? {
        // Mach tick counters are unsigned 32-bit and may wrap.
        let busy = UInt64(user &- previous.user)
            + UInt64(system &- previous.system) + UInt64(nice &- previous.nice)
        let total = busy + UInt64(idle &- previous.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total) * 100
    }
}

enum MetricMath {
    static func memoryUsage(active: UInt64, wired: UInt64, compressed: UInt64,
                            purgeable: UInt64, pageSize: UInt64, physical: UInt64) -> Double? {
        guard physical > 0, pageSize > 0 else { return nil }
        let pages = Double(active) + Double(wired) + Double(compressed) - Double(purgeable)
        return min(100, max(0, pages * Double(pageSize) / Double(physical) * 100))
    }

    static func gpuUsage(from values: [Double]) -> Double? {
        values.filter { $0.isFinite && (0...100).contains($0) }.max()
    }

    static func percentage(_ value: Double?) -> String {
        guard let value, value.isFinite, (0...100).contains(value) else { return "不可用" }
        return String(format: "%.1f%%", value)
    }
}

/// All capacity numbers share one validated volume snapshot.
struct DiskCapacity: Equatable {
    let totalBytes: Int64
    let availableBytes: Int64

    init?(totalBytes: Int64, availableBytes: Int64) {
        guard totalBytes > 0, availableBytes >= 0, availableBytes <= totalBytes else { return nil }
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    var usedBytes: Int64 { totalBytes - availableBytes }
    var usedPercentage: Double { Double(usedBytes) / Double(totalBytes) * 100 }
}

struct MetricSnapshot {
    var readings: [Metric: String] = [:]
    var percentages: [Metric: Double] = [:]
    var disk: DiskCapacity?
}
