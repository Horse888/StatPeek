import Foundation
import XCTest

final class StatPeekTests: XCTestCase {
    func testCPUUsesIntervalAndIncludesNiceTime() throws {
        let before = CPUTicks(user: 100, system: 200, idle: 300, nice: 400)
        let after = CPUTicks(user: 120, system: 210, idle: 360, nice: 410)
        XCTAssertEqual(try XCTUnwrap(after.utilization(since: before)), 40, accuracy: 0.001)
    }

    func testCPUIdleAndFullLoad() {
        let before = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        XCTAssertEqual(CPUTicks(user: 0, system: 0, idle: 10, nice: 0).utilization(since: before), 0)
        XCTAssertEqual(CPUTicks(user: 10, system: 0, idle: 0, nice: 0).utilization(since: before), 100)
    }

    func testCPUCounterWrap() throws {
        let before = CPUTicks(user: UInt32.max - 4, system: 0, idle: 100, nice: 0)
        let after = CPUTicks(user: 5, system: 0, idle: 110, nice: 0)
        XCTAssertEqual(try XCTUnwrap(after.utilization(since: before)), 50, accuracy: 0.001)
    }

    func testCPUUnchangedCountersHaveNoReading() {
        let ticks = CPUTicks(user: 10, system: 10, idle: 10, nice: 10)
        XCTAssertNil(ticks.utilization(since: ticks))
    }

    func testMemoryFormulaAndBounds() throws {
        XCTAssertEqual(try XCTUnwrap(MetricMath.memoryUsage(active: 30, wired: 20, compressed: 10,
                                                          purgeable: 10, pageSize: 4096, physical: 409600)),
                       50, accuracy: 0.001)
        XCTAssertEqual(MetricMath.memoryUsage(active: 0, wired: 0, compressed: 0,
                                              purgeable: 10, pageSize: 4096, physical: 409600), 0)
        XCTAssertEqual(MetricMath.memoryUsage(active: 200, wired: 0, compressed: 0,
                                              purgeable: 0, pageSize: 4096, physical: 409600), 100)
        XCTAssertNil(MetricMath.memoryUsage(active: 0, wired: 0, compressed: 0,
                                            purgeable: 0, pageSize: 4096, physical: 0))
    }

    func testGPUUnavailableAndInvalidValuesAreNotZero() {
        XCTAssertNil(MetricMath.gpuUsage(from: []))
        XCTAssertNil(MetricMath.gpuUsage(from: [.nan, .infinity, -1, 101]))
        XCTAssertEqual(MetricMath.gpuUsage(from: [0, 20, 60]), 60)
        XCTAssertEqual(MetricMath.percentage(nil), "不可用")
        XCTAssertEqual(MetricMath.percentage(.nan), "不可用")
        XCTAssertEqual(MetricMath.percentage(0), "0.0%")
    }

    func testSelectionDefaultsAndRelaunchPersistence() throws {
        try withIsolatedDefaults { defaults in
            let selection = MetricSelection(defaults: defaults)
            XCTAssertEqual(selection.selected, Set(Metric.allCases))
            selection.toggle(.gpu)
            XCTAssertFalse(MetricSelection(defaults: defaults).selected.contains(.gpu))
            selection.toggle(.gpu)
            XCTAssertEqual(MetricSelection(defaults: defaults).selected, Set(Metric.allCases))
        }
    }

    func testEmptySelectionIsPreserved() throws {
        try withIsolatedDefaults { defaults in
            let selection = MetricSelection(defaults: defaults)
            Metric.allCases.forEach(selection.toggle)
            XCTAssertTrue(MetricSelection(defaults: defaults).selected.isEmpty)
        }
    }

    func testUnknownStoredMetricsAreIgnored() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(["cpu", "futureMetric"], forKey: "visibleMetrics")
            XCTAssertEqual(MetricSelection(defaults: defaults).selected, [.cpu])
        }
    }

    func testSamplerOnlyReturnsRequestedMetricsAndResetsCPU() {
        let sampler = SystemSampler()
        XCTAssertTrue(sampler.sample([]).isEmpty)
        XCTAssertEqual(sampler.sample([.cpu]), [.cpu: "采样中…"])
        sampler.resetCPU()
        XCTAssertEqual(sampler.sample([.cpu]), [.cpu: "采样中…"])
        let values = sampler.sample([.disk, .memory, .gpu])
        XCTAssertEqual(Set(values.keys), [.disk, .memory, .gpu])
        XCTAssertNotEqual(values[.disk], "不可用")
        XCTAssertNotEqual(values[.memory], "不可用")
        XCTAssertFalse(values[.gpu, default: ""].isEmpty)
    }

    func testPrototypePreferencesMigrateWithoutOverwritingCurrentChoices() throws {
        try withIsolatedDefaults { defaults in
            let legacy: [String: Any] = ["visibleMetrics": ["cpu"], "metricColors": ["cpu": "red"]]
            let selection = MetricSelection(defaults: defaults, legacyDefaults: legacy)
            XCTAssertEqual(selection.selected, [.cpu])
            XCTAssertEqual(selection.color(for: .cpu), .red)
            XCTAssertEqual(MetricSelection(defaults: defaults).selected, [.cpu])
            selection.toggle(.disk)
            selection.setColor(.blue, for: .cpu)
            let relaunched = MetricSelection(defaults: defaults, legacyDefaults: legacy)
            XCTAssertEqual(relaunched.selected, [.disk, .cpu])
            XCTAssertEqual(relaunched.color(for: .cpu), .blue)
        }
    }

    func testEmptyPrototypeSelectionMigratesAsEmpty() throws {
        try withIsolatedDefaults { defaults in
            let selection = MetricSelection(defaults: defaults, legacyDefaults: ["visibleMetrics": [String]()])
            XCTAssertTrue(selection.selected.isEmpty)
            XCTAssertTrue(MetricSelection(defaults: defaults).selected.isEmpty)
        }
    }

    func testDiskFormatUsesOneDecimalAndSingleLetterUnits() {
        XCTAssertEqual(DiskFormatter.format(bytes: 320_840_000_000), "320.8G")
        XCTAssertEqual(DiskFormatter.format(bytes: 1_260_000_000_000), "1.3T")
        XCTAssertEqual(DiskFormatter.format(bytes: 1_200_000), "1.2M")
        XCTAssertEqual(DiskFormatter.format(bytes: 999_999_999), "1.0G")
        XCTAssertEqual(DiskFormatter.format(bytes: 0), "0.0B")
        XCTAssertEqual(DiskFormatter.format(bytes: -1), "不可用")
    }

    func testEverySelectionFitsTwoRowsWithoutDroppingOrReorderingMetrics() {
        for bits in 0..<16 {
            let ordered = Metric.allCases.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element)
            let rows = StatusLayout.rows(for: Set(ordered))
            XCTAssertLessThanOrEqual(rows.count, 2)
            XCTAssertTrue(rows.allSatisfy { $0.count <= 2 })
            XCTAssertEqual(rows.flatMap { $0 }, ordered)
        }
        XCTAssertEqual(StatusLayout.rows(for: Set(Metric.allCases)), [[.disk, .cpu], [.memory, .gpu]])
    }

    func testMetricColorsSurviveRelaunchAndSelectionChanges() throws {
        try withIsolatedDefaults { defaults in
            let selection = MetricSelection(defaults: defaults)
            XCTAssertEqual(selection.color(for: .cpu), .orange)
            selection.setColor(.red, for: .cpu)
            selection.toggle(.cpu)
            let relaunched = MetricSelection(defaults: defaults)
            XCTAssertEqual(relaunched.color(for: .cpu), .red)
            XCTAssertFalse(relaunched.selected.contains(.cpu))
            XCTAssertEqual(relaunched.color(for: .disk), .blue)
            relaunched.toggle(.cpu)
            XCTAssertEqual(relaunched.color(for: .cpu), .red)
        }
    }

    func testUnknownColorsFallBackAndCompactValuesPreserveUnavailable() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(["gpu": "futureColor"], forKey: "metricColors")
            XCTAssertEqual(MetricSelection(defaults: defaults).color(for: .gpu), .green)
        }
        XCTAssertEqual(Metric.disk.compact("320.84 GB"), "320.84GB")
        XCTAssertEqual(Metric.cpu.compact("不可用"), "—")
        XCTAssertEqual(Metric.cpu.compact("采样中…"), "…")
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "local.StatPeekTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
