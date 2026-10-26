import AppKit

/// Owns the window lifecycle so a status click cannot be both an outside dismissal and a reopen.
@MainActor
final class DashboardPresentationController {
    let panel: NSPanel
    var onClose: (() -> Void)?
    var isShown: Bool { panel.isVisible }
    private var anchorRect = NSRect.zero
    private let observesOutsideEvents: Bool
    private var localMonitor: Any?
    private var escapeMonitor: Any?
    private var globalMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var shownAt: TimeInterval?
    private var hiddenAt: TimeInterval?
    private var lastStatusClick: (timestamp: TimeInterval, number: Int)?
    private var pendingStatusPress: (timestamp: TimeInterval, number: Int)?

    init(contentViewController: NSViewController, observesOutsideEvents: Bool = true) {
        self.observesOutsideEvents = observesOutsideEvents
        let window = DashboardPanel(contentRect: contentViewController.view.bounds, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        // Liquid Glass owns its silhouette. A second WindowServer shadow can
        // expose another contour outside the glass's rounded corners.
        if #available(macOS 26.0, *) { window.hasShadow = false }
        else { window.hasShadow = true }
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.title = "StatPeek"
        window.setAccessibilityIdentifier("statpeek-dashboard")
        window.contentViewController = contentViewController
        panel = window
        window.onCancel = { [weak self] in self?.cancel() }
    }

    func toggle(anchor: NSRect, visibleFrame: NSRect, activate: Bool = true, event: NSEvent? = nil) {
        // The monitor sees the original press before AppKit forwards the button
        // action. Preserve that intent even if currentEvent is nil or replaced.
        var shouldClose = pendingStatusPress != nil || isShown
        if pendingStatusPress == nil, let event, event.type == .leftMouseDown {
            if let lastStatusClick,
               event.timestamp < lastStatusClick.timestamp
                || (event.timestamp == lastStatusClick.timestamp && event.eventNumber == lastStatusClick.number) { return }
            lastStatusClick = (event.timestamp, event.eventNumber)
            // A deactivation/outside callback can hide the panel before this action is delivered.
            // Honor visibility when the click began instead of turning that close into a reopen.
            if let shownAt, let hiddenAt, (shownAt...hiddenAt).contains(event.timestamp) {
                shouldClose = true
            }
        }
        if let pendingStatusPress {
            lastStatusClick = pendingStatusPress
            if let event, event.type == .leftMouseDown, event.timestamp >= pendingStatusPress.timestamp {
                lastStatusClick = (event.timestamp, event.eventNumber)
            }
        }
        pendingStatusPress = nil
        if shouldClose {
            close()
        } else {
            anchorRect = anchor
            let size = panel.contentViewController!.view.frame.size
            panel.setContentSize(size)
            panel.setFrameOrigin(Self.origin(contentSize: size, anchor: anchor, visibleFrame: visibleFrame))
            panel.alphaValue = 1
            shownAt = ProcessInfo.processInfo.systemUptime
            hiddenAt = nil
            if activate {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFront(nil)
            }
            installDismissalObservers()
        }
    }

    private func cancel() {
        guard isShown else { return }
        // Escape may reach this panel through the color picker's responder chain.
        // Keep the dashboard session and outside-dismissal observers until the next Escape.
        let closedChild = closeChildPopovers(of: panel)
        let colorPanelVisible = NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible
        if closedChild || colorPanelVisible {
            if let root = panel.contentView { deactivateColorWells(in: root) }
            if colorPanelVisible { NSColorPanel.shared.orderOut(nil) }
            return
        }
        close()
    }

    func close() {
        pendingStatusPress = nil
        let wasShown = isShown
        removeDismissalObservers()
        guard wasShown else { return }
        // Finish each native popover's presentation before deactivating its color well.
        // Hiding/closing its NSWindow alone leaves NSPopover.isShown stale on reopen.
        closeChildPopovers(of: panel)
        if let root = panel.contentView { deactivateColorWells(in: root) }
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
        panel.orderOut(nil)
        hiddenAt = ProcessInfo.processInfo.systemUptime
        onClose?()
    }

    /// Both event monitors use this route. Status-bar mouse-down belongs to the toggle action,
    /// and auxiliary windows (the native color picker) belong to this app's dashboard interaction.
    func handleMouseDown(at point: NSPoint, inAppWindow: Bool) {
        guard isShown, !anchorRect.contains(point), !panel.frame.contains(point), !inAppWindow else { return }
        close()
    }

    /// Shared adapter for AppKit's local/global mouse monitors.
    func handleMouseDown(_ event: NSEvent, inAppWindow: Bool) {
        guard isShown, event.timestamp >= (shownAt ?? 0) else { return }
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        if event.type == .leftMouseDown, anchorRect.contains(point) {
            if let lastStatusClick, event.timestamp <= lastStatusClick.timestamp { return }
            pendingStatusPress = (event.timestamp, event.eventNumber)
            return
        }
        handleMouseDown(at: point, inAppWindow: inAppWindow)
    }

    func handleAppDeactivation(duringStatusClick: Bool) {
        if !duringStatusClick && pendingStatusPress == nil { close() }
    }

    /// Consume Escape before the native picker can hide only its NSWindow and leave isShown stale.
    /// Other windows keep their own keyboard handling.
    @discardableResult
    func handleEscape(in window: NSWindow?) -> Bool {
        guard isShown, let window else { return false }
        var ancestor: NSWindow? = window
        while let current = ancestor {
            if current === panel {
                cancel()
                return true
            }
            ancestor = current.parent
        }
        if NSColorPanel.sharedColorPanelExists, window === NSColorPanel.shared, window.isVisible {
            cancel()
            return true
        }
        return false
    }

    func updateAnchor(_ anchor: NSRect, visibleFrame: NSRect) {
        anchorRect = anchor
        if isShown {
            let origin = Self.origin(contentSize: panel.frame.size, anchor: anchor, visibleFrame: visibleFrame)
            if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        }
    }

    static func origin(contentSize: NSSize, anchor: NSRect, visibleFrame: NSRect) -> NSPoint {
        let margin: CGFloat = 6
        let x = min(max(anchor.midX - contentSize.width / 2, visibleFrame.minX + margin),
                    visibleFrame.maxX - contentSize.width - margin)
        let y = max(visibleFrame.minY + margin,
                    min(anchor.minY - contentSize.height - margin, visibleFrame.maxY - contentSize.height - margin))
        return NSPoint(x: x, y: y)
    }

    private func installDismissalObservers() {
        removeDismissalObservers()
        guard observesOutsideEvents else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseDown(event, inAppWindow: event.window != nil)
            }
            return event
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                event.keyCode == 53 && self?.handleEscape(in: event.window ?? NSApp.keyWindow) == true
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseDown(event, inAppWindow: false)
            }
        }
        deactivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                      object: NSApp, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let statusClick = NSEvent.pressedMouseButtons & 1 != 0 && self.anchorRect.contains(NSEvent.mouseLocation)
                self.handleAppDeactivation(duringStatusClick: statusClick)
            }
        }
        // A nonactivating panel leaves the current app active. Cmd-Tab is thus
        // observed at the workspace boundary rather than by activating StatPeek.
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let activatedPID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let activatedPID, activatedPID != ProcessInfo.processInfo.processIdentifier else { return }
                    self?.handleAppDeactivation(duringStatusClick: false)
                }
            }
    }

    private func removeDismissalObservers() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        if let workspaceActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver) }
        localMonitor = nil
        escapeMonitor = nil
        globalMonitor = nil
        deactivationObserver = nil
        workspaceActivationObserver = nil
    }

    private func deactivateColorWells(in view: NSView) {
        (view as? NSColorWell)?.deactivate()
        view.subviews.forEach { deactivateColorWells(in: $0) }
    }

    @discardableResult
    private func closeChildPopovers(of window: NSWindow) -> Bool {
        var dismissed = false
        for child in window.childWindows ?? [] {
            dismissed = closeChildPopovers(of: child) || child.isVisible || dismissed
            var responder: NSResponder? = child.contentView
            var visited = Set<ObjectIdentifier>()
            var closedPopover = false
            while let current = responder, visited.insert(ObjectIdentifier(current)).inserted {
                if let popover = current as? NSPopover {
                    dismissed = popover.isShown || dismissed
                    let animated = popover.animates
                    popover.animates = false
                    popover.close()
                    if !popover.isShown { popover.animates = animated }
                    closedPopover = true
                    break
                }
                responder = current.nextResponder
            }
            if !closedPopover { child.close() }
        }
        return dismissed
    }
}

@MainActor
private final class DashboardPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
