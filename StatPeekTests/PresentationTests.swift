import AppKit
import XCTest

final class PresentationTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 870)
    private let anchor = NSRect(x: 1200, y: 870, width: 107, height: 24)

    @MainActor
    func testObservedStatusPressClosesWhenButtonActionHasNoCurrentMouseEvent() throws {
        try assertObservedStatusPressCloses(forwardsNewEvent: false)
    }

    @MainActor
    func testObservedStatusPressClosesWhenButtonActionForwardsAnotherEvent() throws {
        try assertObservedStatusPressCloses(forwardsNewEvent: true)
    }

    @MainActor
    func testObservedPressTakesPrecedenceOverAStaleCurrentEvent() throws {
        let presenter = fixture()
        defer { presenter.close() }
        let stale = try mouseEvent(at: NSPoint(x: anchor.midX, y: anchor.midY), number: 1)
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: stale)
        let down = try mouseEvent(at: stale.locationInWindow, number: 2)
        presenter.handleMouseDown(down, inAppWindow: false)
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: stale)
        XCTAssertFalse(presenter.isShown, "The original monitored press is authoritative over NSApp.currentEvent")
    }

    @MainActor
    private func assertObservedStatusPressCloses(forwardsNewEvent: Bool) throws {
        let presenter = fixture()
        defer { presenter.close() }
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        let down = try mouseEvent(at: NSPoint(x: anchor.midX, y: anchor.midY), number: 1)
        presenter.handleMouseDown(down, inAppWindow: false)
        presenter.handleAppDeactivation(duringStatusClick: false)
        XCTAssertTrue(presenter.isShown, "The pending status action owns this transition; deactivation must not cause a flash")
        // Native action forwarding need not preserve NSApp.currentEvent's identity.
        let forwarded = forwardsNewEvent ? try mouseEvent(at: down.locationInWindow, number: 2) : nil
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: forwarded)
        XCTAssertFalse(presenter.isShown, "One status press must close, even across deactivation and action forwarding")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(presenter.isShown, "The completed close must not flash back open")
    }

    @MainActor
    func testFreshClickOpensAfterOutsideCloseAndOldOutsideEventCannotCloseNewSession() throws {
        let presenter = fixture()
        defer { presenter.close() }
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        let outside = try mouseEvent(at: NSPoint(x: 20, y: 20), number: 1)
        presenter.handleMouseDown(outside, inAppWindow: false)
        XCTAssertFalse(presenter.isShown)
        let fresh = try mouseEvent(at: NSPoint(x: anchor.midX, y: anchor.midY), number: 2)
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: fresh)
        XCTAssertTrue(presenter.isShown, "A genuinely new click must open immediately without a debounce timeout")
        presenter.handleMouseDown(outside, inAppWindow: false)
        XCTAssertTrue(presenter.isShown, "An outside event from the previous session cannot close a new panel")
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: outside)
        XCTAssertTrue(presenter.isShown, "Older actions cannot override a newer click")
    }

    @MainActor
    func testRapidNativeEventActionsRetainParityAcrossInterleavedDeactivationAndDuplicateDelivery() throws {
        let presenter = fixture()
        defer { presenter.close() }
        for click in 1...200 {
            let stale = try mouseEvent(at: NSPoint(x: 20, y: 20), number: -click)
            let event = try mouseEvent(at: NSPoint(x: anchor.midX, y: anchor.midY), number: click)
            presenter.handleMouseDown(event, inAppWindow: false)
            if click % 4 == 0 { presenter.handleAppDeactivation(duringStatusClick: false) }
            presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: event)
            presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: event)
            presenter.handleMouseDown(stale, inAppWindow: false)
            XCTAssertEqual(presenter.isShown, click % 2 == 1, "Click \(click)")
            XCTAssertFalse(presenter.panel.isKeyWindow || presenter.panel.isMainWindow)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(presenter.isShown)
    }

    @MainActor
    private func mouseEvent(at point: NSPoint, number: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            eventNumber: number, clickCount: 1, pressure: 1))
    }

    @MainActor
    func testStatusClickDoesNotReopenWhenDeactivationClosesBeforeButtonAction() throws {
        let presenter = fixture()
        defer { presenter.close() }
        for observedMouseDown in [false, true] {
            presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                location: NSPoint(x: anchor.midX, y: anchor.midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                context: nil, eventNumber: observedMouseDown ? 2 : 1, clickCount: 1, pressure: 1))
            if observedMouseDown { presenter.handleMouseDown(event, inAppWindow: false) }
            // Deactivation can be delivered after button release but before its action.
            presenter.handleAppDeactivation(duringStatusClick: false)
            XCTAssertEqual(presenter.isShown, observedMouseDown, "An observed status press waits for its single toggle action")
            presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: event)
            XCTAssertFalse(presenter.isShown, "A click that began with a visible panel must finish closed")
            presenter.close()
        }
    }

    @MainActor
    func testOneNativeMouseEventCannotToggleTwice() throws {
        let presenter = fixture()
        defer { presenter.close() }
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: anchor.midX, y: anchor.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: event)
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: event)
        XCTAssertTrue(presenter.isShown, "Repeated delivery of one mouse-down must produce just one transition")
    }

    @MainActor
    func testStatusEventKeepsItsClickPositionWhenPointerHasMovedBeforeDelivery() throws {
        let presenter = fixture()
        defer { presenter.close() }
        // Keep both fixture windows and the recorded click away from the user's current pointer.
        let pointer = NSEvent.mouseLocation
        let area = NSRect(x: pointer.x + 4000, y: pointer.y + 4000, width: 1440, height: 870)
        let target = NSRect(x: area.minX + 700, y: area.maxY, width: 107, height: 24)
        presenter.toggle(anchor: target, visibleFrame: area, activate: false)
        XCTAssertFalse(presenter.panel.frame.contains(pointer))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: target.midX, y: target.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        // Constructing this value never posts input to the system or dispatches it to another app.
        presenter.handleMouseDown(event, inAppWindow: false)
        presenter.toggle(anchor: target, visibleFrame: area, activate: false)
        XCTAssertFalse(presenter.isShown, "A recorded status click must close, even after the pointer has moved")
    }

    @MainActor
    func testEscapeDismissesNativePickerBeforeParentAndOutsideDismissesBoth() throws {
        _ = NSApplication.shared
        let suite = "StatPeekEscapeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = MetricSelection(defaults: defaults)
        let settings = SettingsViewController()
        settings.onColor = { metric, color in selection.setColor(color, for: metric) }
        settings.update(snapshot: MetricSnapshot(), selection: selection)
        settings.prepareToShow(availableHeight: 736)
        let presenter = DashboardPresentationController(contentViewController: settings, observesOutsideEvents: false)
        presenter.panel.ignoresMouseEvents = true
        let originalColor = NSColorPanel.shared.color
        defer {
            presenter.close()
            NSColorPanel.shared.color = originalColor
            presenter.panel.close()
        }
        func descendants(_ root: NSView) -> [NSView] { root.subviews.flatMap { [$0] + descendants($0) } }
        var closes = 0
        presenter.onClose = { closes += 1 }
        for metric in Metric.allCases {
            let well = try XCTUnwrap(descendants(settings.view).compactMap { $0 as? MetricColorButton }.first { $0.metric == metric })
            let before = selection.color(for: metric)
            for route in ["panel-escape", "picker-escape", "outside"] {
                presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
                well.performClick(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                let picker = try XCTUnwrap(pickerPopover(in: presenter.panel))
                let child = try XCTUnwrap(picker.contentViewController?.view.window)
                child.ignoresMouseEvents = true
                XCTAssertTrue(picker.isShown && presenter.isShown)
                let previousCloses = closes
                if route == "outside" {
                    let chosen = try XCTUnwrap(MetricColor(rawValue: "#338866"))
                    NSColorPanel.shared.color = chosen.nsColor
                    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                    XCTAssertEqual(MetricSelection(defaults: defaults).color(for: metric), chosen)
                    presenter.handleMouseDown(at: NSPoint(x: 20, y: 20), inAppWindow: false)
                } else {
                    // Escape's cancelOperation command reaches the owning panel; no keyboard event is posted.
                    if route == "picker-escape" {
                        XCTAssertTrue(presenter.handleEscape(in: child))
                    } else {
                        presenter.panel.cancelOperation(nil)
                    }
                    XCTAssertTrue(presenter.isShown, "First Escape must keep the main panel open")
                    XCTAssertEqual(closes, previousCloses, "Closing a picker must not end the dashboard session")
                    XCTAssertFalse(picker.isShown || child.isVisible || well.isActive, "\(metric) \(route): picker=\(picker.isShown), child=\(child.isVisible), active=\(well.isActive)")
                    XCTAssertEqual(selection.color(for: metric), before)
                    presenter.panel.cancelOperation(nil)
                }
                XCTAssertFalse(presenter.isShown || picker.isShown || child.isVisible || well.isActive, "\(metric) \(route): parent=\(presenter.isShown), picker=\(picker.isShown), child=\(child.isVisible), active=\(well.isActive)")
                XCTAssertEqual(closes, previousCloses + 1)
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                XCTAssertFalse(presenter.isShown || picker.isShown)
            }
        }
    }

    @MainActor
    func testEscapeDoesNotConsumeCommandsFromUnrelatedWindows() {
        let presenter = fixture()
        let other = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        defer { presenter.close(); other.close() }
        XCTAssertFalse(presenter.handleEscape(in: presenter.panel))
        presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false)
        XCTAssertFalse(presenter.handleEscape(in: nil))
        XCTAssertFalse(presenter.handleEscape(in: other))
        XCTAssertTrue(presenter.isShown)
        XCTAssertTrue(presenter.handleEscape(in: presenter.panel))
        XCTAssertFalse(presenter.isShown)
    }

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
                let statusClick = try mouseEvent(at: NSPoint(x: anchor.midX, y: anchor.midY), number: phase)
                presenter.handleMouseDown(statusClick, inAppWindow: false)
                if phase == 2 { presenter.handleAppDeactivation(duringStatusClick: false) }
                presenter.toggle(anchor: anchor, visibleFrame: screen, activate: false, event: statusClick)
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
                XCTAssertEqual(presenter.panel.styleMask, [.borderless, .nonactivatingPanel])
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
