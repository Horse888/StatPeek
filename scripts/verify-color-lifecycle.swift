import AppKit

/// Uses public control actions and AppKit's native color model; never posts input events.
@main
struct ColorLifecycleVerification {
    enum Failure: Error { case check(String) }

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            do { try verify() } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                Darwin.exit(1)
            }
            Darwin.exit(0)
        }
        app.run()
    }

    @MainActor
    static func verify() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let layeredDismissal = CommandLine.arguments.contains("--layered-dismissal")
        let suite = "StatPeekColorLifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = MetricSelection(defaults: defaults)
        let settings = SettingsViewController()
        let snapshot = MetricSnapshot(readings: [.disk: "311.0G", .cpu: "25.0%", .memory: "50.0%", .gpu: "12.0%"],
                                      percentages: [.disk: 37.8, .cpu: 25, .memory: 50, .gpu: 12],
                                      disk: DiskCapacity(totalBytes: 500_000_000_000, availableBytes: 311_000_000_000))
        settings.onColor = { [weak settings] metric, color in
            selection.setColor(color, for: metric)
            settings?.update(snapshot: snapshot, selection: selection)
        }
        settings.update(snapshot: snapshot, selection: selection)
        settings.prepareToShow(availableHeight: 736)
        descendants(settings.view).compactMap { $0 as? NSTextField }
            .first { $0.accessibilityIdentifier() == "app-version" }?.stringValue = "v0.3.9 (14)"
        let host = DashboardPresentationController(contentViewController: settings, observesOutsideEvents: false)
        host.panel.ignoresMouseEvents = true
        host.panel.appearance = NSAppearance(named: .darkAqua)
        let originalColor = NSColorPanel.shared.color
        defer {
            host.close()
            NSColorPanel.shared.color = originalColor
            host.panel.close()
        }
        let area = NSRect(x: 0, y: 0, width: 1440, height: 1100)
        let anchor = NSRect(x: 400, y: 1100, width: 107, height: 24)
        var states: [[String: Any]] = []
        var closes = 0
        host.onClose = { closes += 1 }
        for metric in Metric.allCases {
            let well = descendants(settings.view).compactMap { $0 as? MetricColorButton }.first { $0.metric == metric }!
            for phase in 0...2 {
                let before = Dictionary(uniqueKeysWithValues: Metric.allCases.map { ($0, selection.color(for: $0)) })
                host.toggle(anchor: anchor, visibleFrame: area, activate: false)
                RunLoop.main.run(until: Date().addingTimeInterval(0.06))
                well.performClick(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.12))
                guard let picker = pickerPopover(in: host.panel),
                      let child = picker.contentViewController?.view.window else { throw Failure.check("Native picker did not reopen: \(metric), phase \(phase)") }
                child.ignoresMouseEvents = true
                try check(picker.isShown && child.isVisible && host.isShown, "Opening picker hid its parent")
                try check(!NSColorPanel.shared.isVisible, "Expected native Popover, not advanced Colors panel")
                if phase != 1 {
                    let chosen = MetricColor(rawValue: phase == 0 ? "#336699" : "#CC3355")!
                    NSColorPanel.shared.color = chosen.nsColor
                    RunLoop.main.run(until: Date().addingTimeInterval(0.06))
                    try check(selection.color(for: metric) == chosen, "Native AppKit color callback did not commit")
                    try check(MetricSelection(defaults: defaults).color(for: metric) == chosen, "Color did not persist in isolated defaults")
                } else {
                    try check(selection.color(for: metric) == before[metric], "Cancel changed the stored color")
                }
                for other in Metric.allCases where other != metric {
                    try check(selection.color(for: other) == before[other], "Color leaked to another metric")
                }
                try check(picker.isShown && child.isVisible && host.isShown, "Refresh interrupted editing")
                let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                try check(!foreground && !host.panel.isKeyWindow && !child.isKeyWindow, "Fixture must not take focus")
                let sequence = layeredDismissal ? states.count * 2 + 1 : states.count + 1
                var state: [String: Any] = ["sequence": sequence, "name": "\(metric.rawValue)-phase-\(phase)", "window": child.windowNumber,
                                            "metric": metric.rawValue, "phase": phase, "saved_color": selection.color(for: metric).rawValue,
                                            "parent_visible": host.isShown, "picker_visible": child.isVisible, "picker_shown": picker.isShown,
                                            "is_key": host.panel.isKeyWindow, "is_main": host.panel.isMainWindow,
                                            "app_in_foreground": foreground, "ignores_mouse": host.panel.ignoresMouseEvents,
                                            "other_metrics_unchanged": true]
                try capture(state, output: output)
                if layeredDismissal && phase < 2 {
                    let previousCloses = closes
                    if phase == 0 {
                        host.panel.cancelOperation(nil)
                    } else {
                        try check(host.handleEscape(in: child), "Native picker Escape was not routed to its owning dashboard")
                    }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                    state["first_escape_parent_visible"] = host.isShown
                    state["first_escape_picker_closed"] = !picker.isShown && !child.isVisible
                    state["first_escape_well_deactivated"] = !well.isActive
                    state["first_escape_did_not_close_session"] = closes == previousCloses
                    try check(host.isShown && !picker.isShown && !child.isVisible && !well.isActive && closes == previousCloses,
                              "First Escape must dismiss only the native picker")
                    var parentState = state
                    parentState["sequence"] = sequence + 1
                    parentState["name"] = "\(metric.rawValue)-phase-\(phase)-after-first-escape"
                    parentState["window"] = host.panel.windowNumber
                    parentState["picker_visible"] = child.isVisible
                    parentState["picker_shown"] = picker.isShown
                    try capture(parentState, output: output)
                    host.panel.cancelOperation(nil)
                    try check(closes == previousCloses + 1, "Second Escape must close the dashboard session exactly once")
                } else if layeredDismissal {
                    host.handleMouseDown(at: NSPoint(x: area.minX + 5, y: area.minY + 5), inAppWindow: false)
                    state["outside_closed_both"] = !host.isShown && !picker.isShown && !child.isVisible
                } else {
                    let click = NSEvent.mouseEvent(with: .leftMouseDown,
                        location: NSPoint(x: anchor.midX, y: anchor.midY), modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                        context: nil, eventNumber: sequence, clickCount: 1, pressure: 1)!
                    host.handleMouseDown(click, inAppWindow: false)
                    if phase == 2 { host.handleAppDeactivation(duringStatusClick: false) }
                    host.toggle(anchor: anchor, visibleFrame: area, activate: false, event: click)
                    host.toggle(anchor: anchor, visibleFrame: area, activate: false, event: click)
                }
                state["parent_closed"] = !host.isShown
                state["picker_closed"] = !picker.isShown && !child.isVisible
                state["well_deactivated"] = !well.isActive
                try check(!host.isShown && !picker.isShown && !child.isVisible && !well.isActive, "Parent close left stale native picker state")
                try check(MetricSelection(defaults: defaults).color(for: metric).rawValue == state["saved_color"] as? String,
                          "Dismissal changed the saved color")
                RunLoop.main.run(until: Date().addingTimeInterval(0.06))
                try check(!host.isShown && !picker.isShown, "Delayed close state regressed")
                states.append(state)
                try JSONSerialization.data(withJSONObject: ["scenario": layeredDismissal ? "layered-dismissal" : "color-lifecycle", "states": states,
                    "isolated_preferences": true, "native_color_model": true, "posted_input_events": false], options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("result.json"), options: .atomic)
            }
        }
    }

    @MainActor
    static func capture(_ state: [String: Any], output: URL) throws {
        try check(NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
                  && !NSApp.windows.contains { $0.isKeyWindow || $0.isMainWindow }, "Fixture must never take focus")
        try JSONSerialization.data(withJSONObject: state).write(to: output.appendingPathComponent("state.json"), options: .atomic)
        let ack = output.appendingPathComponent("ack-\(state["sequence"]!)")
        let timeout = Date().addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath: ack.path), Date() < timeout {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        try check(FileManager.default.fileExists(atPath: ack.path), "Screenshot driver timed out")
    }

    @MainActor
    static func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    @MainActor
    static func pickerPopover(in window: NSWindow) -> NSPopover? {
        for child in window.childWindows ?? [] where child.isVisible {
            var current: NSResponder? = child.contentView
            var visited = Set<ObjectIdentifier>()
            while let responder = current, visited.insert(ObjectIdentifier(responder)).inserted {
                if let picker = responder as? NSPopover { return picker }
                current = responder.nextResponder
            }
        }
        return nil
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }
}
