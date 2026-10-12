import Foundation

struct DiskSample: Equatable, Identifiable {
    var id: Int64 = 0
    let date: Date
    let availableBytes: Int64
    let volumeID: String
}

enum DiskSpaceReader {
    static func read(at date: Date) -> DiskSample? {
        guard let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityKey, .volumeUUIDStringKey, .volumeURLKey]),
              let bytes = values.volumeAvailableCapacity, bytes >= 0,
              let volume = values.volumeUUIDString ?? values.volume?.path else { return nil }
        return DiskSample(date: date, availableBytes: Int64(bytes), volumeID: volume)
    }
}

struct DiskComparison {
    let latest: DiskSample
    let previous: DiskSample?

    var deltaBytes: Int64? {
        guard let previous, previous.volumeID == latest.volumeID, latest.date > previous.date else { return nil }
        return latest.availableBytes - previous.availableBytes
    }

    var summary: String {
        guard let previous else { return "首次记录，已建立比较基准" }
        guard previous.volumeID == latest.volumeID else { return "磁盘卷已更换，重新建立基准" }
        guard let delta = deltaBytes else { return "记录时间已调整，重新建立基准" }
        if delta == 0 { return "剩余空间未变化（0.0G）" }
        let amount = Double(delta.magnitude) / 1_000_000_000
        if (amount * 10).rounded() == 0 { return "基本不变（变化小于 0.1G）" }
        let direction = delta > 0 ? "增加" : "减少"
        return "剩余空间\(direction) " + String(format: "%.1fG", amount)
    }
}

enum DiskHistoryError: LocalizedError {
    case invalidSample
    case unavailable
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .invalidSample: "磁盘记录无效，未保存"
        case .unavailable: "暂时无法读取磁盘剩余空间，历史记录已保留"
        case .storage(let message): "磁盘记录保存或读取失败：\(message)"
        }
    }
}

/// A virtual clock drives the same schedule used by the native five-minute timer.
final class DiskHistoryRecorder {
    static let interval: TimeInterval = 5 * 60
    let store: DiskHistoryStore
    private var latest: DiskSample?
    private var lastAttempt: Date?

    init(store: DiskHistoryStore) throws {
        self.store = store
        latest = try store.latestSamples().last
    }

    var nextRecordingDate: Date? {
        (lastAttempt ?? latest?.date)?.addingTimeInterval(Self.interval)
    }

    @discardableResult
    func recordIfDue(at date: Date, read: (Date) -> DiskSample?) throws -> Bool {
        if let reference = lastAttempt ?? latest?.date,
           date >= reference, date.timeIntervalSince(reference) < Self.interval { return false }
        lastAttempt = date
        guard let sample = read(date) else { throw DiskHistoryError.unavailable }
        latest = try store.append(sample)
        return true
    }
}

enum DiskHistoryRange: Int, CaseIterable {
    case day, week, all

    func startDate(at now: Date) -> Date? {
        switch self {
        case .day: now.addingTimeInterval(-24 * 60 * 60)
        case .week: now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .all: nil
        }
    }
}

enum DiskChartSampling {
    /// Keep endpoints, bucket extrema and volume/time discontinuities; storage remains untouched.
    static func reduce(_ samples: [DiskSample], limit: Int = 240) -> [DiskSample] {
        guard samples.count > max(4, limit) else { return samples }
        let buckets = max(1, (limit - 2) / 2)
        let bucketSize = Int(ceil(Double(samples.count - 2) / Double(buckets)))
        var indices: Set<Int> = [0, samples.count - 1]
        for start in stride(from: 1, to: samples.count - 1, by: bucketSize) {
            let range = start..<min(start + bucketSize, samples.count - 1)
            if let low = range.min(by: { samples[$0].availableBytes < samples[$1].availableBytes }) { indices.insert(low) }
            if let high = range.max(by: { samples[$0].availableBytes < samples[$1].availableBytes }) { indices.insert(high) }
        }
        for index in 1..<samples.count {
            if samples[index].volumeID != samples[index - 1].volumeID || samples[index].date <= samples[index - 1].date {
                indices.insert(index - 1)
                indices.insert(index)
            }
        }
        return indices.sorted().map { samples[$0] }
    }
}
