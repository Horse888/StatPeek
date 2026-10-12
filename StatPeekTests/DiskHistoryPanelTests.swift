import AppKit
import XCTest

final class DiskHistoryPanelTests: XCTestCase {
    @MainActor
    func testPanelShowsBaselineThenIncreaseAndDecreaseFromStoredRecords() throws {
        try withPanel { store, panel in
            let start = Date()
            try store.append(DiskSample(date: start, availableBytes: 300_000_000_000, volumeID: "test"))
            panel.reload()
            XCTAssertEqual(field("disk-history-amount", in: panel.view)?.stringValue, "300.0G")
            XCTAssertEqual(field("disk-history-change", in: panel.view)?.stringValue, "首次记录，已建立比较基准")
            try store.append(DiskSample(date: start.addingTimeInterval(300), availableBytes: 301_200_000_000, volumeID: "test"))
            panel.reload()
            XCTAssertEqual(field("disk-history-change", in: panel.view)?.stringValue, "剩余空间增加 1.2G")
            try store.append(DiskSample(date: start.addingTimeInterval(600), availableBytes: 299_200_000_000, volumeID: "test"))
            panel.reload()
            XCTAssertEqual(field("disk-history-change", in: panel.view)?.stringValue, "剩余空间减少 2.0G")
            XCTAssertTrue(field("disk-history-schedule", in: panel.view)?.stringValue.contains("累计 3 条") == true)
        }
    }

    @MainActor
    func testPanelPreservesReadingAndShowsStorageFailureWithToolTip() throws {
        try withPanel { store, panel in
            try store.append(DiskSample(date: Date(), availableBytes: 1_200_000_000, volumeID: "test"))
            panel.recordingError = "测试保存失败，历史已保留"
            panel.reload()
            XCTAssertEqual(field("disk-history-amount", in: panel.view)?.stringValue, "1.2G")
            XCTAssertEqual(field("disk-history-note", in: panel.view)?.stringValue, panel.recordingError)
            XCTAssertEqual(field("disk-history-note", in: panel.view)?.toolTip, panel.recordingError)
            XCTAssertEqual(try store.count(), 1)
        }
    }

    @MainActor
    func testEmptyPanelDoesNotPretendFreeSpaceIsZero() throws {
        try withPanel { _, panel in
            panel.reload()
            XCTAssertEqual(field("disk-history-amount", in: panel.view)?.stringValue, "暂无记录")
            XCTAssertEqual(field("disk-history-change", in: panel.view)?.stringValue, "首次成功采样后建立比较基准")
        }
    }

    @MainActor
    func testFixtureCurveRendersInNativePanelAtItsActualSize() throws {
        _ = NSApplication.shared
        try withPanel { store, panel in
            let now = Date()
            for (index, free) in [310, 308, 309, 306, 307, 312, 310, 311].enumerated() {
                try store.append(DiskSample(date: now.addingTimeInterval(Double(index - 7) * 300),
                                            availableBytes: Int64(free) * 1_000_000_000, volumeID: "synthetic-test-volume"))
            }
            panel.reload()
            let window = NSWindow(contentRect: panel.view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = panel.view
            panel.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window.displayIfNeeded()
            let image = try XCTUnwrap(panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds))
            panel.view.cacheDisplay(in: panel.view.bounds, to: image)
            let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "Synthetic disk trend in native history view"
            attachment.lifetime = .keepAlways
            add(attachment)
            let scaleX = CGFloat(image.pixelsWide) / panel.view.bounds.width
            let scaleY = CGFloat(image.pixelsHigh) / panel.view.bounds.height
            var coloredPlotPixels = 0
            for y in stride(from: Int(186 * scaleY), to: Int(336 * scaleY), by: 2) {
                for x in stride(from: Int(20 * scaleX), to: Int(360 * scaleX), by: 2) {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    if color.alphaComponent > 0.5, (channels.max() ?? 0) - (channels.min() ?? 0) > 0.3 {
                        coloredPlotPixels += 1
                    }
                }
            }
            XCTAssertGreaterThan(coloredPlotPixels, 10, "The chart must paint actual data, not just an empty frame")
        }
    }

    @MainActor
    private func field(_ identifier: String, in view: NSView) -> NSTextField? {
        view.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == identifier }
    }

    @MainActor
    private func withPanel(_ body: (DiskHistoryStore, DiskHistoryViewController) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StatPeekPanelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DiskHistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        let panel = DiskHistoryViewController()
        panel.store = store
        try body(store, panel)
    }
}
