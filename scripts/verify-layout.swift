import AppKit

// A standalone rendering fixture: it never activates, becomes key, or posts input events.
@main
struct LayoutVerification {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            do { try render() } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                Darwin.exit(1)
            }
            Darwin.exit(0)
        }
        app.run()
    }

    @MainActor
    static func render() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "StatPeekIndependentLayout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var store: DiskHistoryStore? = try DiskHistoryStore(url: output.appendingPathComponent("fixture.sqlite"))
        let start = Date().addingTimeInterval(-2400)
        for (index, free) in [310, 308, 309, 306, 307, 312, 310, 311].enumerated() {
            try store!.append(DiskSample(date: start.addingTimeInterval(Double(index) * 300),
                                        availableBytes: Int64(free) * 1_000_000_000, volumeID: "synthetic-independent-layout"))
        }
        let controller = SettingsViewController()
        defer {
            controller.updateDiskHistory(store: nil, nextRecordingDate: nil, error: nil)
            store = nil
        }
        let selection = MetricSelection(defaults: defaults)
        let snapshot = MetricSnapshot(readings: [.disk: "311.0G", .cpu: "100.0%", .memory: "100.0%", .gpu: "100.0%"],
                                      percentages: [.disk: 37.8, .cpu: 100, .memory: 100, .gpu: 100],
                                      disk: DiskCapacity(totalBytes: 500_000_000_000, availableBytes: 311_000_000_000))
        controller.update(snapshot: snapshot, selection: selection)
        controller.updateLoginItem(status: .enabled, error: nil)
        controller.updateDiskHistory(store: store, nextRecordingDate: start.addingTimeInterval(2700), error: nil)
        let fields = descendants(controller.view).compactMap { $0 as? NSTextField }
        fields.first { $0.accessibilityIdentifier() == "app-version" }?.stringValue = "v0.3.5 (10)"
        let scroll = descendants(controller.view).compactMap { $0 as? NSScrollView }.first!
        let document = scroll.documentView!
        var states: [[String: Any]] = []
        var sequence = 0
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let presentation = DashboardPresentationController(contentViewController: controller, observesOutsideEvents: false)
            presentation.onClose = { controller.stopSymbolMotion() }
            let window = presentation.panel
            window.ignoresMouseEvents = true
            window.animationBehavior = .none
            window.appearance = NSAppearance(named: appearance)
            defer { presentation.close(); window.contentViewController = nil; window.close() }
            for limit: CGFloat in [1378, 736, 568, 448] {
                presentation.close()
                controller.prepareToShow(availableHeight: limit)
                let area = NSRect(x: 30, y: 80, width: 320, height: controller.view.frame.height + 12)
                let anchor = NSRect(x: 100, y: area.maxY, width: 107, height: 24)
                presentation.toggle(anchor: anchor, visibleFrame: area, activate: false)
                let maximumOffset = max(0, document.frame.height - scroll.contentView.bounds.height)
                for (position, offset) in [("top", CGFloat.zero), ("middle", maximumOffset / 2), ("bottom", maximumOffset)] {
                    if maximumOffset == 0 && position != "top" { continue }
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    controller.update(snapshot: snapshot, selection: selection)
                    controller.view.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                    precondition(!window.isKeyWindow && !window.isMainWindow)
                    let appInForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                    precondition(!appInForeground, "The fixture must not replace the user's foreground app")
                    precondition(abs(scroll.contentView.bounds.origin.y - offset) < 0.5)
                    sequence += 1
                    let name = "\(appearance == .aqua ? "light" : "dark")-\(Int(limit))-\(position)"
                    let state: [String: Any] = ["sequence": sequence, "name": name, "window": window.windowNumber,
                                               "limit": limit, "actual_height": controller.view.frame.height,
                                               "document_height": document.frame.height, "viewport_height": scroll.contentView.bounds.height,
                                               "scrolling": scroll.hasVerticalScroller, "offset": scroll.contentView.bounds.origin.y,
                                               "is_key": window.isKeyWindow, "is_main": window.isMainWindow,
                                               "app_in_foreground": appInForeground, "ignores_mouse": window.ignoresMouseEvents]
                    try JSONSerialization.data(withJSONObject: state).write(to: output.appendingPathComponent("state.json"), options: .atomic)
                    let acknowledgement = output.appendingPathComponent("ack-\(sequence)")
                    let timeout = Date().addingTimeInterval(15)
                    while !FileManager.default.fileExists(atPath: acknowledgement.path), Date() < timeout {
                        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                    }
                    precondition(FileManager.default.fileExists(atPath: acknowledgement.path), "Screenshot driver did not acknowledge")
                    states.append(state)
                }
            }
            presentation.close()
            let anchor = NSRect(x: 100, y: 700, width: 107, height: 24)
            let area = NSRect(x: 30, y: 80, width: 1440, height: 700)
            for click in 1...100 {
                presentation.handleMouseDown(at: NSPoint(x: anchor.midX, y: anchor.midY), inAppWindow: false)
                presentation.handleAppDeactivation(duringStatusClick: true)
                presentation.toggle(anchor: anchor, visibleFrame: area, activate: false)
                precondition(presentation.isShown == (click % 2 == 1))
                precondition(!window.isKeyWindow && !window.isMainWindow)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            precondition(!presentation.isShown)
        }
        let measurements: [[String: Any]] = fields.compactMap { field in
            guard !field.stringValue.isEmpty, let cell = field.cell else { return nil }
            let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.bounds.width, height: 10000))
            return ["text": field.stringValue, "frame": NSStringFromRect(field.frame),
                    "natural": NSStringFromSize(cell.cellSize), "needed": NSStringFromSize(needed)]
        }
        let result: [String: Any] = ["states": states, "text_measurements": measurements, "fixture": true, "posted_input_events": false, "arrowless_panel": true, "rapid_toggles": 200, "delayed_reopen": false]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("result.json"))
    }

    @MainActor
    static func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
