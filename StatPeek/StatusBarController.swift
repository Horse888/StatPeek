import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let selection = MetricSelection(legacyDefaults: UserDefaults.standard.persistentDomain(forName: "local.StatPeek"))
    private let sampler = SystemSampler()
    private let strip = StatusStripView()
    private let settings = SettingsViewController()
    private lazy var presentation = DashboardPresentationController(contentViewController: settings)
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
            button.sendAction(on: .leftMouseDown)
            button.setAccessibilityIdentifier("status-toggle")
            button.addSubview(strip)
        }
        presentation.onClose = { [weak self] in
            guard let self else { return }
            self.settings.stopSymbolMotion()
            if !self.selection.selected.contains(.cpu) { self.sampler.resetCPU() }
        }
        settings.onToggle = { [weak self] metric in
            guard let self else { return }
            self.selection.toggle(metric)
            if metric == .cpu, !self.presentation.isShown { self.sampler.resetCPU() }
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
        snapshot = sampler.sample(presentation.isShown ? Set(Metric.allCases) : selection.selected)
        render()
    }

    private func render() {
        let rows = StatusLayout.rows(for: selection.selected)
        strip.update(rows: rows, readings: readings, selection: selection)
        let width = strip.requiredWidth
        if statusItem.length != width { statusItem.length = width }
        if let button = statusItem.button {
            let frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
            if strip.frame != frame { strip.frame = frame }
            let summary = Metric.allCases.filter { selection.selected.contains($0) }
                .map { "\($0.title)：\(readings[$0] ?? "采样中…")" }.joined(separator: "；")
            button.toolTip = "StatPeek · 状态一瞥\n" + (summary.isEmpty ? "点击选择显示信息" : summary)
            button.setAccessibilityLabel("StatPeek · " + (summary.isEmpty ? "未选择信息项" : summary))
            button.setAccessibilityValue(summary)
            if let window = button.window, let screen = window.screen {
                let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
                presentation.updateAnchor(anchor, visibleFrame: screen.visibleFrame)
            }
        }
        settings.update(snapshot: snapshot, selection: selection)
        if presentation.isShown { updateLoginItem() }
    }

    private func updateLoginItem() {
        settings.updateLoginItem(status: loginItem.status, error: loginItem.errorMessage)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return }
        if !presentation.isShown {
            updateLoginItem()
            settings.prepareToShow(availableHeight: screen.visibleFrame.height - 32)
            if !selection.selected.contains(.cpu) { sampler.resetCPU() }
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        presentation.toggle(anchor: anchor, visibleFrame: screen.visibleFrame, event: NSApp.currentEvent)
        if presentation.isShown { refresh() }
    }
}
