import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let selection = MetricSelection(legacyDefaults: UserDefaults.standard.persistentDomain(forName: "local.StatPeek"))
    private let sampler = SystemSampler()
    private let strip = StatusStripView()
    private let popover = NSPopover()
    private let settings = SettingsViewController()
    private let loginItem = LoginItemController()
    private var diskRecording: DiskRecordingController?
    private var readings: [Metric: String] = [:]
    private var timer: Timer?

    override init() {
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityIdentifier("status-toggle")
            button.addSubview(strip)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = settings
        settings.onToggle = { [weak self] metric in
            guard let self else { return }
            self.selection.toggle(metric)
            if metric == .cpu { self.sampler.resetCPU() }
            if self.selection.selected.contains(metric) {
                self.readings.merge(self.sampler.sample([metric])) { _, new in new }
            } else {
                self.readings.removeValue(forKey: metric)
            }
            self.render()
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
        readings = sampler.sample(selection.selected)
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
        settings.update(readings: readings, selection: selection)
        if popover.isShown { updateLoginItem() }
    }

    private func updateLoginItem() {
        settings.updateLoginItem(status: loginItem.status, error: loginItem.errorMessage)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            updateLoginItem()
            settings.prepareToShow()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
