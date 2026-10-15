import AppKit
import XCTest

final class StatusStripRenderingTests: XCTestCase {
    func testMonospacedNumbersAndLabelsFitReservedSpace() {
        XCTAssertEqual(StatusStripText.width("111.1%"), StatusStripText.width("888.8%"), accuracy: 0.01)
        for metric in Metric.allCases {
            XCTAssertGreaterThan(StatusStripText.width(metric.abbreviation), 0)
            XCTAssertLessThan(StatusStripText.width(metric.abbreviation), StatusStripLayout.labelWidth)
        }
        for value in ["…", "—", "999.9G", "100.0%"] {
            XCTAssertTrue(StatusStripText.width(value).isFinite)
            XCTAssertGreaterThan(StatusStripText.width(value), 0)
        }
    }

    @MainActor
    func testNativeDrawingForEverySelectionColorAppearanceAndScale() throws {
        _ = NSApplication.shared
        let suite = "StatPeekStripDrawing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = MetricSelection(defaults: defaults)
        let view = StatusStripView()
        let readings: [Metric: String] = [.disk: "999.9G", .cpu: "100.0%", .memory: "…", .gpu: "—"]
        let colors = MetricColor.allCases + [try XCTUnwrap(MetricColor(rawValue: "#00C7FC"))]
        var frames = 0
        for color in colors {
            for metric in Metric.allCases { selection.setColor(color, for: metric) }
            for bits in 0..<16 {
                let metrics = Set(Metric.allCases.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element))
                let rows = StatusLayout.rows(for: metrics)
                view.update(rows: rows, readings: readings, selection: selection)
                view.frame = NSRect(x: 0, y: 0, width: view.requiredWidth, height: 24)
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    view.appearance = NSAppearance(named: appearance)
                    for scale in [1, 2] {
                        let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                            pixelsWide: Int(view.bounds.width) * scale, pixelsHigh: 24 * scale,
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                        image.size = view.bounds.size
                        view.appearance?.performAsCurrentDrawingAppearance {
                            view.cacheDisplay(in: view.bounds, to: image)
                        }
                        var ink = [0, 0]
                        var chromaticPixels = 0
                        for y in 0..<image.pixelsHigh {
                            for x in 0..<image.pixelsWide {
                                guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                                      pixel.alphaComponent > 0.1 else { continue }
                                ink[y < image.pixelsHigh / 2 ? 0 : 1] += 1
                                let components = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent]
                                if components.max()! - components.min()! > 0.1 { chromaticPixels += 1 }
                            }
                        }
                        XCTAssertGreaterThan(ink.reduce(0, +), 0, "Drawing must produce visible glyphs")
                        if metrics.count >= 2 {
                            XCTAssertGreaterThan(ink[0], 0, "First row must remain visible")
                            XCTAssertGreaterThan(ink[1], 0, "Second row must remain visible")
                        }
                        if !metrics.isEmpty && color != .neutral {
                            XCTAssertGreaterThan(chromaticPixels, 0, "Selected color must reach the rendered pixels")
                        }
                        frames += 1
                    }
                }
            }
        }
        XCTAssertEqual(frames, 448)
    }
}
