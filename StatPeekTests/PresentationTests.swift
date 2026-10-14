import AppKit
import XCTest

final class PresentationTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 870)
    private let anchor = NSRect(x: 1200, y: 870, width: 107, height: 24)

    @MainActor
    func testNativeColorPickerClosesWithParentAndCanReopenAndCommitForEveryMetric() throws {
        _ = NSApplication.shared
        let suite = "StatPeekNativePickerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = MetricSelection(defaults: defaults)
        let settings = SettingsViewController()
        let snapshot = MetricSnapshot()
        settings.onColor = { [weak settings] metric, color in
            selection.setColor(color, for: metric)
            settings?.update(snapshot: snapshot, selection: selection)
        }
        settings.update(snapshot: snapshot, selection: selection)
        settings.prepareToShow(availableHeight: 736)
        let presenter = DashboardPresentationController(contentViewController: settings, observesOutsideEvents: false)
        presenter.panel.ignoresMouseEvents = true
        let initialPanelColor = NSColorPanel.shared.color
        defer {
            presenter.close()
            NSColorPanel.shared.color = initialPanelColor
            presenter.panel.close()
        }
        func descendants(_ root: NSView) -> [NSView] { root.subviews.flatMap { [$0] + descendants($0) } }
        for metric in Metric.allCases {
            let well = try XCTUnwrap(descendants(settings.view).compactMap { $0 as? MetricColorButton }.first { $0.metric == metric })
            for phase in 0...2 {
                let before = Dictionary(uniqueKeysWithValues: Metric.allCases.map { ($0, selection.color(for: $0)) })
                presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
                RunLoop.main.run(until: Date().addingTimeInterval(0.04))
                well.performClick(nil) // Public control action within this test process, not a desktop click.
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let picker = try XCTUnwrap(pickerPopover(in: presenter.panel), "Native picker failed to reopen for \(metric), phase \(phase)")
                let pickerWindow = try XCTUnwrap(picker.contentViewController?.view.window)
                pickerWindow.ignoresMouseEvents = true
                XCTAssertTrue(picker.isShown)
                XCTAssertTrue(pickerWindow.isVisible)
                XCTAssertTrue(presenter.isShown)
                XCTAssertFalse(NSColorPanel.shared.isVisible, "This must be the native Popover, not the advanced Colors panel")
                if phase != 1 {
                    let chosen = try XCTUnwrap(MetricColor(rawValue: phase == 0 ? "#336699" : "#CC3355"))
                    // Exercise AppKit's actual color-panel-to-active-well notification path.
                    NSColorPanel.shared.color = chosen.nsColor
                    RunLoop.main.run(until: Date().addingTimeInterval(0.04))
                    XCTAssertEqual(selection.color(for: metric), chosen)
                    XCTAssertEqual(MetricSelection(defaults: defaults).color(for: metric), chosen)
                } else {
                    XCTAssertEqual(selection.color(for: metric), before[metric])
                }
                for other in Metric.allCases where other != metric {
                    XCTAssertEqual(selection.color(for: other), before[other], "Picker must keep its own metric target")
                }
                XCTAssertTrue(presenter.isShown)
                XCTAssertTrue(picker.isShown, "A metric refresh during color editing must preserve the picker")
                presenter.handleMouseDown(at: NSPoint(x: anchor.midX, y: anchor.midY), inAppWindow: false)
                presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
                XCTAssertFalse(presenter.isShown)
                XCTAssertFalse(picker.isShown, "Native dismissal must finish before hiding its parent")
                XCTAssertFalse(pickerWindow.isVisible)
                XCTAssertFalse(well.isActive)
                RunLoop.main.run(until: Date().addingTimeInterval(0.04))
                XCTAssertFalse(presenter.isShown)
                XCTAssertFalse(picker.isShown)
            }
        }
    }

    @MainActor
    private func pickerPopover(in window: NSWindow) -> NSPopover? {
        for child in window.childWindows ?? [] where child.isVisible {
            var responder: NSResponder? = child.contentView
            var visited = Set<ObjectIdentifier>()
            while let current = responder, visited.insert(ObjectIdentifier(current)).inserted {
                if let popover = current as? NSPopover { return popover }
                responder = current.nextResponder
            }
        }
        return nil
    }

    @MainActor
    func testStatusMouseDownThenActionClosesExactlyOnceWithoutReopening() {
        let presenter = fixture()
        defer { presenter.close() }
        var closes = 0
        presenter.onClose = { closes += 1 }
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        XCTAssertTrue(presenter.isShown)
        // This is the same routing called by the real mouse monitors, with no posted events.
        presenter.handleMouseDown(at: NSPoint(x: anchor.midX, y: anchor.midY), inAppWindow: false)
        presenter.handleAppDeactivation(duringStatusClick: true)
        XCTAssertTrue(presenter.isShown, "The status mouse-down must belong to its action, not outside dismissal")
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        XCTAssertFalse(presenter.isShown)
        XCTAssertEqual(closes, 1)
        XCTAssertFalse(presenter.panel.isVisible, "Close must finish synchronously, without a fade/reopen interval")
    }

    @MainActor
    func testRapidStatusClicksHaveDeterministicParityAndStayClosedAfterRunLoop() {
        let presenter = fixture()
        defer { presenter.close() }
        for click in 1...100 {
            presenter.handleMouseDown(at: NSPoint(x: anchor.midX, y: anchor.midY), inAppWindow: false)
            presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
            XCTAssertEqual(presenter.isShown, click % 2 == 1, "Click \(click)")
            XCTAssertFalse(presenter.panel.isKeyWindow)
            XCTAssertFalse(presenter.panel.isMainWindow)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(presenter.isShown, "No delayed callback may reopen the dashboard")
    }

    @MainActor
    func testAuxiliaryColorWindowKeepsParentOpenAndOutsideDismissalIsIdempotent() {
        let presenter = fixture()
        defer { presenter.close() }
        var closes = 0
        presenter.onClose = { closes += 1 }
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        let outside = NSPoint(x: 20, y: 20)
        presenter.handleMouseDown(at: outside, inAppWindow: true)
        XCTAssertTrue(presenter.isShown, "Native color picker and panel interaction must keep the parent open")
        presenter.handleMouseDown(at: outside, inAppWindow: false)
        XCTAssertFalse(presenter.isShown)
        presenter.close()
        XCTAssertEqual(closes, 1)
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        presenter.panel.cancelOperation(nil) // Calls its responder directly, never sends a keyboard event.
        XCTAssertFalse(presenter.isShown)
        XCTAssertEqual(closes, 2)
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        presenter.handleAppDeactivation(duringStatusClick: false)
        XCTAssertFalse(presenter.isShown)
        XCTAssertEqual(closes, 3)
    }

    @MainActor
    func testArrowlessPanelFitsLeadingTrailingAndOffsetScreensWithoutAnimations() {
        let presenter = fixture()
        defer { presenter.close() }
        for visible in [screen, NSRect(x: -1440, y: 200, width: 1440, height: 700)] {
            for x in [visible.minX, visible.midX, visible.maxX - 20] {
                let target = NSRect(x: x, y: visible.maxY, width: 20, height: 24)
                presenter.toggle(anchor: target, visibleFrame: visible, activate: false)
                XCTAssertTrue(visible.contains(presenter.panel.frame))
                XCTAssertEqual(presenter.panel.styleMask, .borderless)
                XCTAssertEqual(presenter.panel.animationBehavior, .none)
                XCTAssertFalse(presenter.panel.isOpaque)
                presenter.close()
            }
        }
    }

    @MainActor
    private func fixture() -> DashboardPresentationController {
        _ = NSApplication.shared
        let controller = NSViewController()
        controller.view = GlassSurfaceView(frame: NSRect(x: 0, y: 0, width: 288, height: 420), cornerRadius: 18, interactive: false)
        let presenter = DashboardPresentationController(contentViewController: controller, observesOutsideEvents: false)
        presenter.panel.ignoresMouseEvents = true
        return presenter
    }
}
