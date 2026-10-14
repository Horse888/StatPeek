import AppKit
import XCTest

final class DashboardTests: XCTestCase {
    @MainActor
    func testIndependentWindowLayoutAndScrollAtDifferentScreenHeights() throws {
        _ = NSApplication.shared
        try isolated { defaults in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StatPeekLayoutTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            var store: DiskHistoryStore? = try DiskHistoryStore(url: directory.appendingPathComponent("history.sqlite"))
            let date = Date().addingTimeInterval(-2400)
            for (index, free) in [310, 308, 309, 306, 307, 312, 310, 311].enumerated() {
                try store!.append(DiskSample(date: date.addingTimeInterval(Double(index) * 300),
                                           availableBytes: Int64(free) * 1_000_000_000, volumeID: "synthetic-layout-test"))
            }
            let settings = SettingsViewController()
            defer {
                settings.updateDiskHistory(store: nil, nextRecordingDate: nil, error: nil)
                store = nil
            }
            let selection = MetricSelection(defaults: defaults)
            let snapshot = MetricSnapshot(readings: [.disk: "311.0G", .cpu: "100.0%", .memory: "100.0%", .gpu: "100.0%"],
                                          percentages: [.disk: 37.8, .cpu: 100, .memory: 100, .gpu: 100],
                                          disk: DiskCapacity(totalBytes: 500_000_000_000, availableBytes: 311_000_000_000))
            settings.update(snapshot: snapshot, selection: selection)
            settings.updateLoginItem(status: .enabled, error: nil)
            settings.updateDiskHistory(store: store, nextRecordingDate: date.addingTimeInterval(2400), error: nil)
            let version = try XCTUnwrap(descendants(settings.view).first { $0.accessibilityIdentifier() == "app-version" } as? NSTextField)
            version.stringValue = "v0.3.8 (13)"
            let scroll = try XCTUnwrap(descendants(settings.view).compactMap { $0 as? NSScrollView }.first)
            let document = try XCTUnwrap(scroll.documentView)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                // Hidden independent windows never activate or receive desktop input.
                let window = NSWindow(contentRect: settings.view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.ignoresMouseEvents = true
                window.animationBehavior = .none
                window.setFrameOrigin(NSPoint(x: 30, y: 80))
                window.appearance = NSAppearance(named: appearance)
                window.contentView = settings.view
                defer { window.contentView = nil; window.close() }
                for height: CGFloat in [1378, 736, 568, 448] {
                    settings.prepareToShow(availableHeight: height)
                    window.setContentSize(settings.view.frame.size)
                    XCTAssertFalse(window.isKeyWindow)
                    XCTAssertFalse(window.isMainWindow)
                    settings.view.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
                    XCTAssertEqual(scroll.frame.minY, 48, accuracy: 0.5)
                    XCTAssertEqual(scroll.frame.maxY, settings.view.bounds.height - 78, accuracy: 0.5,
                                   "Window attachment must not resize the explicit scroll viewport a second time")
                    XCTAssertLessThanOrEqual(settings.view.frame.height, height)
                    XCTAssertEqual(scroll.hasVerticalScroller, document.frame.height > scroll.contentView.bounds.height + 0.5)
                    let maximumOffset = max(0, document.frame.height - scroll.contentView.bounds.height)
                    for (position, offset) in [("top", CGFloat.zero), ("middle", maximumOffset / 2), ("bottom", maximumOffset)] {
                        if maximumOffset == 0 && position != "top" { continue }
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        settings.update(snapshot: snapshot, selection: selection)
                        assertLabelsFit(in: settings.view)
                        XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 0.5, "Refresh must preserve scroll position")
                        let footer = try XCTUnwrap(descendants(settings.view).first { $0.accessibilityIdentifier() == "quit-app" })
                        let footerFrame = settings.view.convert(footer.bounds, from: footer)
                        XCTAssertTrue(settings.view.bounds.contains(footerFrame))
                        XCTAssertLessThanOrEqual(footerFrame.maxY, scroll.frame.minY)
                        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
                        let image = try XCTUnwrap(settings.view.bitmapImageRepForCachingDisplay(in: settings.view.bounds))
                        settings.view.cacheDisplay(in: settings.view.bounds, to: image)
                        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
                        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                        attachment.name = "Independent layout fixture - \(appearance.rawValue) - \(Int(height)) - \(position)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
                let measurements: [[String: Any]] = descendants(settings.view).compactMap { item in
                    guard let field = item as? NSTextField, !field.stringValue.isEmpty, let cell = field.cell else { return nil }
                    let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000))
                    return ["text": field.stringValue, "frame": NSStringFromRect(field.frame),
                            "natural": NSStringFromSize(cell.cellSize), "needed": NSStringFromSize(needed)]
                }
                let measurement = XCTAttachment(data: try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted]), uniformTypeIdentifier: "public.json")
                measurement.name = "Independent text measurement - \(appearance.rawValue)"
                measurement.lifetime = .keepAlways
                add(measurement)
                settings.update(snapshot: MetricSnapshot(readings: [.disk: "采样中…", .cpu: "采样中…", .memory: "不可用", .gpu: "不可用"]), selection: selection)
                settings.updateDiskHistory(store: nil, nextRecordingDate: nil, error: "暂时无法读取磁盘剩余空间，历史记录已保留")
                settings.prepareToShow(availableHeight: 568)
                assertLabelsFit(in: settings.view)
                settings.update(snapshot: snapshot, selection: selection)
                settings.updateDiskHistory(store: store, nextRecordingDate: date.addingTimeInterval(2700), error: nil)
            }
        }
    }

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
    private func assertLabelsFit(in root: NSView, file: StaticString = #filePath, line: UInt = #line) {
        for item in descendants(root) {
            guard let field = item as? NSTextField, !field.stringValue.isEmpty, let cell = field.cell else { continue }
            let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000))
            XCTAssertLessThanOrEqual(size.width, field.bounds.width + 0.5, "Truncated width: \(field.stringValue)", file: file, line: line)
            XCTAssertLessThanOrEqual(size.height, field.bounds.height + 0.5, "Truncated height: \(field.stringValue)", file: file, line: line)
        }
        for parent in [root] + descendants(root) {
            let labels = parent.subviews.compactMap { $0 as? NSTextField }.filter { !$0.stringValue.isEmpty }
            for (index, label) in labels.enumerated() {
                for other in labels.dropFirst(index + 1) {
                    XCTAssertFalse(label.frame.intersects(other.frame), "Overlapping labels: \(label.stringValue) / \(other.stringValue)", file: file, line: line)
                }
            }
            guard let symbol = parent.subviews.compactMap({ $0 as? ModuleSymbolView }).first,
                  let title = labels.first(where: { Metric.allCases.map(\.title).contains($0.stringValue) }) else { continue }
            XCTAssertEqual(symbol.frame.midY, title.frame.midY, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(title.frame.minX - symbol.frame.maxX, 4, accuracy: 0.5, file: file, line: line)
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
