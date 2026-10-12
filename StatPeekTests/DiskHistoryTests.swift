import AppKit
import Foundation
import XCTest

final class DiskHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstBaselineAndExactFiveMinuteBoundary() throws {
        try withStore { store in
            let recorder = try DiskHistoryRecorder(store: store)
            XCTAssertTrue(try recorder.recordIfDue(at: start) { self.sample(at: $0, bytes: 300_000_000_000) })
            var calls = 0
            XCTAssertFalse(try recorder.recordIfDue(at: start.addingTimeInterval(299)) { date in
                calls += 1
                return self.sample(at: date, bytes: 0)
            })
            XCTAssertEqual(calls, 0)
            XCTAssertTrue(try recorder.recordIfDue(at: start.addingTimeInterval(300)) {
                self.sample(at: $0, bytes: 301_200_000_000)
            })
            let saved = try store.latestSamples()
            XCTAssertEqual(try store.count(), 2)
            XCTAssertEqual(DiskComparison(latest: saved[1], previous: saved[0]).summary, "剩余空间增加 1.2G")
            XCTAssertEqual(recorder.nextRecordingDate, start.addingTimeInterval(600))
        }
    }

    func testRealDatabaseReopenPreservesHistoryAndRemainingSchedule() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        do {
            let store = try DiskHistoryStore(url: url)
            try DiskHistoryRecorder(store: store).recordIfDue(at: start) { self.sample(at: $0, bytes: 123_400_000_000) }
        }
        let reopened = try DiskHistoryStore(url: url)
        let recorder = try DiskHistoryRecorder(store: reopened)
        XCTAssertEqual(try reopened.count(), 1)
        XCTAssertEqual(try reopened.latestSamples().last?.availableBytes, 123_400_000_000)
        XCTAssertEqual(recorder.nextRecordingDate, start.addingTimeInterval(300))
        XCTAssertFalse(try recorder.recordIfDue(at: start.addingTimeInterval(60)) { _ in
            XCTFail("Restart must not sample again before the saved deadline")
            return nil
        })
    }

    func testWakeAfterMissedIntervalsRecordsOneRealSampleWithoutBackfilling() throws {
        try withStore { store in
            let recorder = try DiskHistoryRecorder(store: store)
            try recorder.recordIfDue(at: start) { self.sample(at: $0, bytes: 300_000_000_000) }
            let wake = start.addingTimeInterval(4 * 3600)
            XCTAssertTrue(try recorder.recordIfDue(at: wake) { self.sample(at: $0, bytes: 299_000_000_000) })
            let rows = try store.samples(since: nil)
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows.map(\.date), [start, wake])
            XCTAssertEqual(recorder.nextRecordingDate, wake.addingTimeInterval(300))
        }
    }

    func testFailedReadingPreservesLastValidRecordAndRetriesOnNextInterval() throws {
        try withStore { store in
            let recorder = try DiskHistoryRecorder(store: store)
            try recorder.recordIfDue(at: start) { self.sample(at: $0, bytes: 300_000_000_000) }
            XCTAssertThrowsError(try recorder.recordIfDue(at: start.addingTimeInterval(300)) { _ in nil })
            XCTAssertEqual(try store.count(), 1)
            XCTAssertEqual(try store.latestSamples().last?.availableBytes, 300_000_000_000)
            XCTAssertFalse(try recorder.recordIfDue(at: start.addingTimeInterval(301)) { _ in
                XCTFail("Failed reads should not be retried every two-second UI refresh")
                return nil
            })
            XCTAssertTrue(try recorder.recordIfDue(at: start.addingTimeInterval(600)) {
                self.sample(at: $0, bytes: 298_000_000_000)
            })
            let rows = try store.latestSamples()
            XCTAssertEqual(DiskComparison(latest: rows[1], previous: rows[0]).summary, "剩余空间减少 2.0G")
        }
    }

    func testComparisonHandlesNoChangeTinyChangesAndNewBaselines() {
        let before = sample(at: start, bytes: 300_000_000_000)
        let unchanged = sample(at: start.addingTimeInterval(300), bytes: before.availableBytes)
        XCTAssertEqual(DiskComparison(latest: unchanged, previous: before).summary, "剩余空间未变化（0.0G）")
        for delta: Int64 in [-1_000_000, 1_000_000] {
            let tiny = sample(at: unchanged.date, bytes: before.availableBytes + delta)
            XCTAssertEqual(DiskComparison(latest: tiny, previous: before).summary, "基本不变（变化小于 0.1G）")
        }
        let otherVolume = sample(at: unchanged.date, bytes: 500_000_000_000, volume: "volume-B")
        XCTAssertNil(DiskComparison(latest: otherVolume, previous: before).deltaBytes)
        XCTAssertEqual(DiskComparison(latest: otherVolume, previous: before).summary, "磁盘卷已更换，重新建立基准")
        XCTAssertEqual(DiskComparison(latest: before, previous: nil).summary, "首次记录，已建立比较基准")
    }

    func testClockRollbackCreatesANewBaselineAndFutureDeadline() throws {
        try withStore { store in
            let recorder = try DiskHistoryRecorder(store: store)
            try recorder.recordIfDue(at: start) { self.sample(at: $0, bytes: 300_000_000_000) }
            let earlier = start.addingTimeInterval(-60)
            XCTAssertTrue(try recorder.recordIfDue(at: earlier) { self.sample(at: $0, bytes: 299_000_000_000) })
            let rows = try store.latestSamples()
            XCTAssertEqual(rows[1].date, earlier)
            XCTAssertEqual(DiskComparison(latest: rows[1], previous: rows[0]).summary, "记录时间已调整，重新建立基准")
            XCTAssertEqual(recorder.nextRecordingDate, earlier.addingTimeInterval(300))
        }
    }

    func testAllRecordsAreRetainedAndRangeQueriesDoNotDeleteAnything() throws {
        try withStore { store in
            for index in 0..<500 {
                try store.append(sample(at: start.addingTimeInterval(Double(index) * 300), bytes: Int64(index)))
            }
            XCTAssertEqual(try store.count(), 500)
            XCTAssertEqual(try store.samples(since: nil).first?.date, start)
            let cutoff = start.addingTimeInterval(490 * 300)
            XCTAssertEqual(try store.samples(since: cutoff).count, 10)
            XCTAssertEqual(try store.count(), 500)
            XCTAssertEqual(try store.latestSamples().map(\.availableBytes), [498, 499])
        }
    }

    func testInvalidSamplesDoNotDamageExistingHistory() throws {
        try withStore { store in
            try store.append(sample(at: start, bytes: 42))
            for invalid in [sample(at: start, bytes: -1), sample(at: start, bytes: 0, volume: ""),
                            sample(at: Date(timeIntervalSince1970: .infinity), bytes: 0)] {
                XCTAssertThrowsError(try store.append(invalid))
            }
            XCTAssertEqual(try store.count(), 1)
            XCTAssertEqual(try store.latestSamples().last?.availableBytes, 42)
        }
    }

    func testCorruptDatabaseIsReportedWithoutOverwritingIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.sqlite")
        let sentinel = Data("corrupted test database; preserve this data".utf8)
        try sentinel.write(to: url)
        XCTAssertThrowsError(try DiskHistoryStore(url: url))
        XCTAssertEqual(try Data(contentsOf: url), sentinel)
    }

    func testChartDownsamplingPreservesPeaksEndpointsAndVolumeBoundaries() {
        var rows = (0..<1000).map { index in
            DiskSample(id: Int64(index + 1), date: start.addingTimeInterval(Double(index) * 300),
                       availableBytes: 100, volumeID: index < 700 ? "A" : "B")
        }
        rows[111] = DiskSample(id: 112, date: rows[111].date, availableBytes: 900, volumeID: "A")
        rows[222] = DiskSample(id: 223, date: rows[222].date, availableBytes: 1, volumeID: "A")
        let chart = DiskChartSampling.reduce(rows)
        XCTAssertEqual(chart.first, rows.first)
        XCTAssertEqual(chart.last, rows.last)
        XCTAssertTrue(chart.contains(rows[111]))
        XCTAssertTrue(chart.contains(rows[222]))
        XCTAssertTrue(chart.contains(rows[699]))
        XCTAssertTrue(chart.contains(rows[700]))
        XCTAssertLessThanOrEqual(chart.count, 242)
        XCTAssertEqual(chart.map(\.id), chart.map(\.id).sorted())
        XCTAssertEqual(rows.count, 1000)
    }

    private func sample(at date: Date, bytes: Int64, volume: String = "volume-A") -> DiskSample {
        DiskSample(date: date, availableBytes: bytes, volumeID: volume)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StatPeekTests-\(UUID().uuidString)")
    }

    private func withStore(_ body: (DiskHistoryStore) throws -> Void) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(DiskHistoryStore(url: directory.appendingPathComponent("history.sqlite")))
    }
}
