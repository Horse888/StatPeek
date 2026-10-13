import AppKit

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let selection = MetricSelection(legacyDefaults: UserDefaults.standard.persistentDomain(forName: "local.StatPeek"))
    private let sampler = SystemSampler()
    private let strip = StatusStripView()
    private let popover = NSPopover()
    private let settings = SettingsViewController()
    private let loginItem = LoginItemController()
    private var diskRecording: DiskRecordingController?
    private var snapshot = MetricSnapshot()
    private var readings: [Metric: String] { snapshot.readings }
    private var timer: Timer?

    override init() {
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityIdentifier("status-toggle")
            button.addSubview(strip)
        }
        // Keep settings visible when a window of this app (the color panel) gains focus.
        popover.behavior = .semitransient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = settings
        NotificationCenter.default.addObserver(self, selector: #selector(closeOnDeactivation),
                                               name: NSApplication.didResignActiveNotification, object: NSApp)
        settings.onToggle = { [weak self] metric in
            guard let self else { return }
            self.selection.toggle(metric)
            if metric == .cpu, !self.popover.isShown { self.sampler.resetCPU() }
            self.refresh()
        }
        settings.onColor = { [weak self] metric, color in
            guard let self else { return }
            self.selection.setColor(color, for: metric)
            self.render()
        }
        settings.onLoginToggle = { [weak self] enabled in
            guard let self else { return }
            self.loginItem.setEnabled(enabled)
            self.updateLoginItem()
        }
        settings.onOpenLoginSettings = { [weak self] in self?.loginItem.openSystemSettings() }
        settings.onShowHistory = { [weak self] in
            guard let self, let diskRecording = self.diskRecording else { return }
            diskRecording.recordIfDue()
            self.updateDiskHistory()
        }
        setUpDiskRecording()
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.timer = timer
    }

    private func setUpDiskRecording() {
        do {
            let store = try DiskHistoryStore(url: DiskHistoryStore.defaultURL)
            let recording = try DiskRecordingController(store: store)
            diskRecording = recording
            recording.onChange = { [weak self] _ in self?.updateDiskHistory() }
            recording.recordIfDue()
            updateDiskHistory()
        } catch {
            settings.updateDiskHistory(store: nil, nextRecordingDate: nil, error: error.localizedDescription)
        }
    }

    private func updateDiskHistory() {
        guard let diskRecording else { return }
        settings.updateDiskHistory(store: diskRecording.recorder.store,
                                   nextRecordingDate: diskRecording.recorder.nextRecordingDate,
                                   error: diskRecording.errorMessage)
    }

    private func refresh() {
        snapshot = sampler.sample(popover.isShown ? Set(Metric.allCases) : selection.selected)
        render()
    }

    private func render() {
        let rows = StatusLayout.rows(for: selection.selected)
        strip.update(rows: rows, readings: readings, selection: selection)
        let width = strip.requiredWidth
        statusItem.length = width
        if let button = statusItem.button {
            strip.frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
            let summary = Metric.allCases.filter { selection.selected.contains($0) }
                .map { "\($0.title)：\(readings[$0] ?? "采样中…")" }.joined(separator: "；")
            button.toolTip = "StatPeek · 状态一瞥\n" + (summary.isEmpty ? "点击选择显示信息" : summary)
            button.setAccessibilityLabel("StatPeek · " + (summary.isEmpty ? "未选择信息项" : summary))
            button.setAccessibilityValue(summary)
        }
        settings.update(snapshot: snapshot, selection: selection)
        if popover.isShown { updateLoginItem() }
    }

    private func updateLoginItem() {
        settings.updateLoginItem(status: loginItem.status, error: loginItem.errorMessage)
    }

    func popoverDidClose(_ notification: Notification) {
        if !selection.selected.contains(.cpu) { sampler.resetCPU() }
    }

    @objc private func closeOnDeactivation() {
        if popover.isShown { popover.performClose(nil) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            updateLoginItem()
            let screen = button.window?.screen ?? NSScreen.main
            settings.prepareToShow(availableHeight: (screen?.visibleFrame.height ?? 900) - 32)
            popover.contentSize = settings.view.frame.size
            NSApp.activate(ignoringOtherApps: true)
            if !selection.selected.contains(.cpu) { sampler.resetCPU() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            refresh()
        }
    }
}
