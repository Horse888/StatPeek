import AppKit
import XCTest

final class PresentationTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 870)
    private let anchor = NSRect(x: 1200, y: 870, width: 107, height: 24)

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
