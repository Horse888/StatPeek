import AppKit
import XCTest

final class DashboardTests: XCTestCase {
    @MainActor
    func testDashboardFitsItsContentAndScrollsOnlyWhenScreenIsShort() throws {
        let settings = SettingsViewController()
        _ = settings.view
        let scroll = try XCTUnwrap(descendants(settings.view).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        settings.fitToAvailableHeight(1400)
        XCTAssertFalse(scroll.hasVerticalScroller)
        XCTAssertEqual(scroll.contentView.bounds.height, document.frame.height, accuracy: 0.5)
        XCTAssertLessThan(settings.view.frame.height, 1400)
        settings.fitToAvailableHeight(600)
        XCTAssertLessThanOrEqual(settings.view.frame.height, 600)
        XCTAssertTrue(scroll.hasVerticalScroller)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        settings.fitToAvailableHeight(1400)
        XCTAssertFalse(scroll.hasVerticalScroller)
        XCTAssertEqual(scroll.contentView.bounds.origin, .zero)
        let quit = try XCTUnwrap(descendants(settings.view).first { $0.accessibilityIdentifier() == "quit-app" })
        XCTAssertFalse(quit.isDescendant(of: document), "Footer actions must remain reachable when content scrolls")
    }

    func testCapacityRejectsInvalidInputsAndKeepsTheWholeSnapshotConsistent() throws {
        for (total, available): (Int64, Int64) in [(0, 0), (-1, 0), (100, -1), (100, 101)] {
            XCTAssertNil(DiskCapacity(totalBytes: total, availableBytes: available))
        }
        let capacity = try XCTUnwrap(DiskCapacity(totalBytes: 1_000, availableBytes: 250))
        XCTAssertEqual(capacity.usedBytes, 750)
        XCTAssertEqual(capacity.usedPercentage, 75)
        XCTAssertEqual(DiskCapacity(totalBytes: Int64.max, availableBytes: 0)?.usedBytes, Int64.max)
        XCTAssertEqual(DiskCapacity(totalBytes: 100, availableBytes: 100)?.usedPercentage, 0)
    }

    func testCustomColorNormalizesAndPersistsOnlyItsOwnMetric() throws {
        try isolated { defaults in
            defaults.set(["disk": "neutral", "cpu": "orange", "memory": "purple", "gpu": "green"], forKey: "metricColors")
            let selection = MetricSelection(defaults: defaults)
            let color = try XCTUnwrap(MetricColor(rawValue: "#12abEF"))
            XCTAssertEqual(color.rawValue, "#12ABEF")
            selection.setColor(color, for: .cpu)
            selection.toggle(.cpu)
            let restored = MetricSelection(defaults: defaults)
            XCTAssertEqual(restored.color(for: .cpu), color)
            XCTAssertEqual(restored.color(for: .disk), .neutral)
            XCTAssertEqual(restored.color(for: .memory), .purple)
            XCTAssertEqual(restored.color(for: .gpu), .green)
            XCTAssertFalse(restored.selected.contains(.cpu))
            restored.setColor(.custom("#invalid"), for: .cpu)
            XCTAssertEqual(restored.color(for: .cpu), color)
        }
        for invalid in ["#000", "#GGGGGG", "1234567", "#１２３４５６", "#12345678"] { XCTAssertNil(MetricColor(rawValue: invalid)) }
    }

    func testPrototypeCustomColorMigrationAndCurrentPreferencePrecedence() throws {
        try isolated { defaults in
            let legacy: [String: Any] = ["visibleMetrics": ["gpu"], "metricColors": ["gpu": "#1280AF", "cpu": "red"]]
            XCTAssertEqual(MetricSelection(defaults: defaults, legacyDefaults: legacy).color(for: .gpu).rawValue, "#1280AF")
            XCTAssertEqual(MetricSelection(defaults: defaults).selected, [.gpu])
            defaults.set(["cpu": "blue"], forKey: "metricColors")
            XCTAssertEqual(MetricSelection(defaults: defaults, legacyDefaults: legacy).color(for: .cpu), .blue)
        }
    }

    @MainActor
    func testColorWellsInitializeWithoutWritingAndCommitOnlyTheirOwnMetric() throws {
        _ = NSApplication.shared
        try isolated { defaults in
            let selection = MetricSelection(defaults: defaults)
            let settings = SettingsViewController()
            var changes: [Metric] = []
            settings.onColor = { metric, color in changes.append(metric); selection.setColor(color, for: metric) }
            settings.update(snapshot: MetricSnapshot(), selection: selection)
            let cpu = try XCTUnwrap(descendants(settings.view).first { $0.accessibilityIdentifier() == "color-cpu" } as? MetricColorButton)
            let gpu = try XCTUnwrap(descendants(settings.view).first { $0.accessibilityIdentifier() == "color-gpu" } as? MetricColorButton)
            XCTAssertTrue(changes.isEmpty, "Initial rendering must not write preferences")
            cpu.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
            settings.update(snapshot: MetricSnapshot(), selection: selection)
            XCTAssertEqual(MetricColor(nsColor: cpu.color)?.rawValue, "#336699", "Live metric refresh must preserve an in-progress picker edit")
            XCTAssertTrue(cpu.sendAction(cpu.action, to: cpu.target))
            XCTAssertEqual(selection.color(for: .cpu).rawValue, "#336699")
            selection.toggle(.cpu)
            settings.update(snapshot: MetricSnapshot(), selection: selection)
            XCTAssertEqual(cpu.displayedColor, .systemGray)
            XCTAssertEqual(MetricColor(nsColor: cpu.color)?.rawValue, "#336699", "Gray presentation must not replace the stored or picker color")
            XCTAssertEqual(changes, [.cpu])
            gpu.color = NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 1)
            XCTAssertTrue(gpu.sendAction(gpu.action, to: gpu.target))
            XCTAssertEqual(MetricSelection(defaults: defaults).color(for: .gpu).rawValue, "#FF0080")
            XCTAssertEqual(selection.color(for: .cpu).rawValue, "#336699")
            selection.toggle(.cpu)
            settings.update(snapshot: MetricSnapshot(), selection: selection)
            XCTAssertEqual(cpu.displayedColor, selection.color(for: .cpu).nsColor)
            XCTAssertEqual(changes, [.cpu, .gpu])
        }
    }

    @MainActor
    func testRefreshPreservesScrollAndUncheckedPreviewAndUnavailableProgress() throws {
        try isolated { defaults in
            let selection = MetricSelection(defaults: defaults)
            selection.toggle(.gpu)
            let settings = SettingsViewController()
            let snapshot = MetricSnapshot(readings: [.gpu: "不可用", .cpu: "25.0%"], percentages: [.cpu: 25])
            settings.update(snapshot: snapshot, selection: selection)
            let scroll = try XCTUnwrap(descendants(settings.view).compactMap { $0 as? NSScrollView }.first)
            let document = try XCTUnwrap(scroll.documentView)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
            let origin = scroll.contentView.bounds.origin
            settings.update(snapshot: snapshot, selection: selection)
            XCTAssertTrue(scroll.documentView === document)
            XCTAssertEqual(scroll.contentView.bounds.origin, origin)
            let reading = try XCTUnwrap(descendants(document).first { $0.accessibilityIdentifier() == "reading-gpu" } as? NSTextField)
            XCTAssertEqual(reading.stringValue, "不可用")
            let progress = try XCTUnwrap(descendants(document).first { $0.accessibilityIdentifier() == "progress-gpu" } as? MetricProgressView)
            XCTAssertNil(progress.validPercentage)
            for invalid in [Double.nan, .infinity, -1, 101] { progress.percentage = invalid; XCTAssertNil(progress.validPercentage) }
            progress.percentage = 0
            XCTAssertEqual(progress.validPercentage, 0)
            progress.percentage = 100
            XCTAssertEqual(progress.validPercentage, 100)
        }
    }

    @MainActor
    func testExtremeCustomColorsPaintVisibleProgressAndUnknownDoesNotPaint() throws {
        for (appearanceName, background, chosen) in [(NSAppearance.Name.aqua, NSColor.white, NSColor.white),
                                                     (.darkAqua, NSColor.black, NSColor.black)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let progress = MetricProgressView(frame: NSRect(x: 0, y: 0, width: 120, height: 8))
            progress.color = chosen
            func pixels(_ percentage: Double?) throws -> [Double] {
                progress.percentage = percentage
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 8,
                                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState()
                defer { NSGraphicsContext.restoreGraphicsState() }
                NSGraphicsContext.current = context
                appearance.performAsCurrentDrawingAppearance {
                    background.setFill()
                    NSBezierPath(rect: progress.bounds).fill()
                    progress.draw(progress.bounds)
                }
                return (0..<8).flatMap { y in (0..<120).map { x in Double(bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent) } }
            }
            let unknown = try pixels(nil)
            let zero = try pixels(0)
            let half = try pixels(50)
            let full = try pixels(100)
            func changed(_ a: [Double], _ b: [Double]) -> Int { zip(a, b).filter { abs($0 - $1) > 0.02 }.count }
            XCTAssertGreaterThan(changed(unknown, zero), 50, "Known zero paints the neutral track")
            XCTAssertGreaterThan(changed(zero, half), 50, "An extreme custom color must remain visible on the track")
            XCTAssertGreaterThan(changed(half, full), 50)
            XCTAssertEqual(try pixels(.nan), unknown)
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    private func isolated(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "StatPeekDashboardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
