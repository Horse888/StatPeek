import AppKit

/// Drives a real status-button class in our own nonactivating fixture window.
/// Events stay in this process; nothing is posted to the system input queue.
@MainActor
private final class NativeStatusAction: NSObject {
    var perform: (() -> Void)?
    var count = 0
    @objc func invoke(_ sender: NSButton) { count += 1; perform?() }
}

@main
struct StatusGestureVerification {
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
        let area = NSScreen.main!.visibleFrame
        let controls = NSPanel(contentRect: NSRect(x: area.minX + 40, y: area.maxY - 70, width: 160, height: 34),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        controls.isReleasedWhenClosed = false
        controls.ignoresMouseEvents = true
        controls.animationBehavior = .none
        let button = NSStatusBarButton(frame: NSRect(x: 8, y: 5, width: 144, height: 24))
        button.title = "StatPeek fixture"
        let action = NativeStatusAction()
        button.target = action
        button.action = #selector(NativeStatusAction.invoke(_:))
        button.sendAction(on: .leftMouseDown)
        controls.contentView!.addSubview(button)
        controls.orderFront(nil)
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 288, height: 300))
        let presenter = DashboardPresentationController(contentViewController: content, observesOutsideEvents: false)
        presenter.panel.ignoresMouseEvents = true
        let anchor = controls.convertToScreen(button.frame)
        var states: [[String: Any]] = []
        var rawActionTypes = Set<String>()
        defer { presenter.close(); presenter.panel.close(); controls.close() }
        for forwarded in [false, true] {
            for click in 1...250 {
                let before = presenter.isShown
                let timestamp = ProcessInfo.processInfo.systemUptime
                let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 60, y: 18), modifierFlags: [],
                    timestamp: timestamp, windowNumber: controls.windowNumber, context: nil,
                    eventNumber: states.count * 2 + 1, clickCount: 1, pressure: 1)!
                let up = NSEvent.mouseEvent(with: .leftMouseUp, location: down.locationInWindow, modifierFlags: [],
                    timestamp: timestamp + 0.001, windowNumber: controls.windowNumber, context: nil,
                    eventNumber: states.count * 2 + 2, clickCount: 1, pressure: 0)!
                presenter.handleMouseDown(down, inAppWindow: true)
                if before { presenter.handleAppDeactivation(duringStatusClick: false) }
                precondition(presenter.isShown == before, "Deactivation introduced an extra visibility transition")
                let previousActions = action.count
                action.perform = {
                    rawActionTypes.insert(NSApp.currentEvent.map { String(describing: $0.type) } ?? "nil")
                    let event = forwarded ? NSEvent.mouseEvent(with: .leftMouseDown, location: down.locationInWindow,
                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controls.windowNumber,
                        context: nil, eventNumber: 10000 + action.count, clickCount: 1, pressure: 1) : NSApp.currentEvent
                    presenter.toggle(anchor: anchor, visibleFrame: area, activate: false, event: event)
                }
                // NSButton's tracking loop consumes this release from our own app
                // queue. The user's cursor, keyboard and global event queue are untouched.
                NSApp.postEvent(up, atStart: true)
                button.mouseDown(with: down)
                precondition(action.count == previousActions + 1, "Native button delivered more than one action")
                precondition(presenter.isShown == !before, "Native status action failed to toggle")
                presenter.handleMouseDown(down, inAppWindow: true) // late duplicate monitor callback
                RunLoop.main.run(until: Date().addingTimeInterval(0.002))
                precondition(presenter.isShown == !before, "Late delivery reopened or closed the panel")
                precondition(!controls.isKeyWindow && !presenter.panel.isKeyWindow && !NSApp.isActive)
                states.append(["forwarded_action_event": forwarded, "click": click,
                               "before_visible": before, "after_visible": presenter.isShown,
                               "one_native_action": true, "deactivation_did_not_flash": true])
            }
            precondition(!presenter.isShown)
        }
        let result: [String: Any] = ["native_button_class": "NSStatusBarButton", "gestures": states.count,
            "native_actions": action.count, "raw_action_event_types": rawActionTypes.sorted(), "states": states,
            "system_input_events_posted": false, "in_process_release_events": true, "app_activated": false,
            "fixture_window_only": true, "physical_menu_bar_clicked": false]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("result.json"))
    }
}
