import AppKit
import CoreText

@main
struct NativeStatusStripVerification {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            do { try capture() } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8)); Darwin.exit(1)
            }
            Darwin.exit(0)
        }
        app.run()
    }

    @MainActor
    static func capture() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let suite = "StatPeekNativeStrip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = MetricSelection(defaults: defaults)
        let strip = StatusStripView()
        strip.update(rows: StatusLayout.rows(for: Set(Metric.allCases)),
                     readings: [.disk: "999.9G", .cpu: "100.0%", .memory: "72.0%", .gpu: "0.0%"], selection: selection)
        strip.frame = NSRect(x: 0, y: 0, width: strip.requiredWidth, height: 24)
        let window = NSPanel(contentRect: strip.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.hasShadow = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = strip
        window.setFrameOrigin(NSPoint(x: 40, y: 80))
        defer { window.contentView = nil; window.close() }
        var states: [[String: Any]] = []
        for (index, appearance) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
            window.appearance = NSAppearance(named: appearance)
            window.orderFront(nil)
            strip.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            precondition(!window.isKeyWindow && !NSApp.isActive)
            for label in strip.subviews.compactMap({ $0 as? NSTextField }).filter({ !$0.isHidden }) {
                precondition(label.cell!.cellSize.width <= label.bounds.width + 0.5, "Native status text is clipped: \(label.stringValue)")
            }
            let name = appearance == .aqua ? "status-light" : "status-dark"
            let state: [String: Any] = ["sequence": index + 1, "name": name, "window": window.windowNumber,
                                       "font": CTFontCopyPostScriptName(StatusStripText.makeFont()) as String,
                                       "width": strip.requiredWidth, "height": 24, "app_activated": NSApp.isActive,
                                       "native_label_count": strip.subviews.filter { $0 is NSTextField }.count]
            try JSONSerialization.data(withJSONObject: state).write(to: output.appendingPathComponent("state.json"), options: .atomic)
            let acknowledgement = output.appendingPathComponent("ack-\(index+1)")
            let timeout = Date().addingTimeInterval(15)
            while !FileManager.default.fileExists(atPath: acknowledgement.path), Date() < timeout {
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
            precondition(FileManager.default.fileExists(atPath: acknowledgement.path))
            states.append(state)
        }
        try JSONSerialization.data(withJSONObject: ["states": states, "fixture": true, "posted_input_events": false],
                                   options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("result.json"))
    }
}
