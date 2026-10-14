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
    private var globalMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?

    init(contentViewController: NSViewController, observesOutsideEvents: Bool = true) {
        self.observesOutsideEvents = observesOutsideEvents
        let window = DashboardPanel(contentRect: contentViewController.view.bounds, styleMask: .borderless,
                                    backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.title = "StatPeek"
        window.setAccessibilityIdentifier("statpeek-dashboard")
        window.contentViewController = contentViewController
        panel = window
        window.onCancel = { [weak self] in self?.close() }
    }

    func toggle(anchor: NSRect, visibleFrame: NSRect, activate: Bool = true) {
        if isShown {
            close()
        } else {
            anchorRect = anchor
            let size = panel.contentViewController!.view.frame.size
            panel.setContentSize(size)
            panel.setFrameOrigin(Self.origin(contentSize: size, anchor: anchor, visibleFrame: visibleFrame))
            panel.alphaValue = 1
            if activate {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFront(nil)
            }
            installDismissalObservers()
        }
    }

    func close() {
        let wasShown = isShown
        removeDismissalObservers()
        guard wasShown else { return }
        // Deactivate only this dashboard's wells before hiding their parent.
        if let root = panel.contentView { deactivateColorWells(in: root) }
        panel.childWindows?.forEach { $0.orderOut(nil) }
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
        panel.orderOut(nil)
        onClose?()
    }

    /// Both event monitors use this route. Status-bar mouse-down belongs to the toggle action,
    /// and auxiliary windows (the native color picker) belong to this app's dashboard interaction.
    func handleMouseDown(at point: NSPoint, inAppWindow: Bool) {
        guard isShown, !anchorRect.contains(point), !panel.frame.contains(point), !inAppWindow else { return }
        close()
    }

    func handleAppDeactivation(duringStatusClick: Bool) {
        if !duringStatusClick { close() }
    }

    func updateAnchor(_ anchor: NSRect, visibleFrame: NSRect) {
        anchorRect = anchor
        if isShown {
            panel.setFrameOrigin(Self.origin(contentSize: panel.frame.size, anchor: anchor, visibleFrame: visibleFrame))
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
                self?.handleMouseDown(at: NSEvent.mouseLocation, inAppWindow: event.window != nil)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseDown(at: NSEvent.mouseLocation, inAppWindow: false)
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
    }

    private func removeDismissalObservers() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        localMonitor = nil
        globalMonitor = nil
        deactivationObserver = nil
    }

    private func deactivateColorWells(in view: NSView) {
        (view as? NSColorWell)?.deactivate()
        view.subviews.forEach { deactivateColorWells(in: $0) }
    }
}

@MainActor
private final class DashboardPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
