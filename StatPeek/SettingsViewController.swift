import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    var onToggle: ((Metric) -> Void)?
    var onColor: ((Metric, MetricColor) -> Void)?
    var onLoginToggle: ((Bool) -> Void)?
    var onOpenLoginSettings: (() -> Void)?
    var onShowHistory: (() -> Void)?
    private let historyController = DiskHistoryViewController()
    private let scrollView = NSScrollView()
    private var cards: [Metric: MetricCardView] = [:]
    private var moduleSymbols: [ModuleSymbolView] = []
    private var loginSymbol: ModuleSymbolView!
    private var loginToggle: NSButton!
    private var loginHint: NSTextField!
    private var loginSettings: NSButton!
    private var loginStatus: LoginItemStatus = .notRegistered
    private var colors: [Metric: MetricColor] = [:]
    private(set) var colorTarget: Metric?

    override func loadView() {
        view = DashboardBackgroundView(frame: NSRect(x: 0, y: 0, width: 380, height: 620))
        text("StatPeek", frame: NSRect(x: 20, y: 574, width: 340, height: 24), size: 18, weight: .semibold)
        text("勾选显示在状态栏 · 每 2 秒更新", frame: NSRect(x: 20, y: 552, width: 340, height: 18), size: 11, color: .secondaryLabelColor)
        scrollView.frame = NSRect(x: 0, y: 48, width: 380, height: 494)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.setAccessibilityIdentifier("dashboard-scroll")
        let document = FlippedDashboardView(frame: NSRect(x: 0, y: 0, width: 380, height: 1010))
        scrollView.documentView = document
        view.addSubview(scrollView)
        var y: CGFloat = 8
        for (index, metric) in Metric.allCases.enumerated() {
            let height: CGFloat = metric == .disk ? 108 : 80
            let card = MetricCardView(metric: metric, frame: NSRect(x: 20, y: y, width: 340, height: height))
            card.toggle.tag = index
            card.toggle.target = self
            card.toggle.action = #selector(toggleMetric(_:))
            card.colorButton.target = self
            card.colorButton.action = #selector(showColorPanel(_:))
            document.addSubview(card)
            cards[metric] = card
            moduleSymbols.append(card.symbol)
            y += height + 6
        }
        let historySymbol = ModuleSymbolView(name: "chart.xyaxis.line", color: .systemBlue,
                                             frame: NSRect(x: 20, y: y + 3, width: 18, height: 18))
        document.addSubview(historySymbol)
        moduleSymbols.append(historySymbol)
        text("磁盘记录", frame: NSRect(x: 46, y: y, width: 314, height: 24), size: 15, weight: .semibold, in: document)
        y += 28
        let historyCard = DashboardCardView(frame: NSRect(x: 20, y: y, width: 340, height: 412))
        document.addSubview(historyCard)
        addChild(historyController)
        historyController.view.frame = NSRect(x: 0, y: 8, width: 340, height: 396)
        historyCard.addSubview(historyController.view)
        y += 420
        let loginCard = DashboardCardView(frame: NSRect(x: 20, y: y, width: 340, height: 72))
        document.addSubview(loginCard)
        loginSymbol = ModuleSymbolView(name: "power", color: .secondaryLabelColor,
                                       frame: NSRect(x: 12, y: 44, width: 18, height: 18))
        loginCard.addSubview(loginSymbol)
        moduleSymbols.append(loginSymbol)
        loginToggle = NSButton(checkboxWithTitle: "开机自动启动", target: self, action: #selector(toggleLoginItem(_:)))
        loginToggle.frame = NSRect(x: 38, y: 40, width: 164, height: 26)
        loginToggle.allowsMixedState = true
        loginToggle.setAccessibilityIdentifier("launch-at-login")
        loginCard.addSubview(loginToggle)
        loginHint = NSTextField(wrappingLabelWithString: "登录此账户时自动启动")
        loginHint.font = .systemFont(ofSize: 10)
        loginHint.textColor = .secondaryLabelColor
        loginHint.frame = NSRect(x: 32, y: 6, width: 292, height: 30)
        loginHint.setAccessibilityIdentifier("login-item-status")
        loginCard.addSubview(loginHint)
        loginSettings = NSButton(title: "系统设置", target: self, action: #selector(openLoginSettings))
        loginSettings.bezelStyle = .rounded
        loginSettings.frame = NSRect(x: 234, y: 40, width: 96, height: 26)
        loginSettings.isHidden = true
        loginCard.addSubview(loginSettings)
        y += 86
        document.setFrameSize(NSSize(width: 380, height: y))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let versionLabel = text("v\(version) (\(build))", frame: NSRect(x: 20, y: 16, width: 200, height: 20), size: 11, color: .secondaryLabelColor)
        versionLabel.setAccessibilityIdentifier("app-version")
        let quit = NSButton(title: "退出 StatPeek", target: self, action: #selector(quitApp))
        quit.bezelStyle = .rounded
        quit.frame = NSRect(x: 246, y: 10, width: 116, height: 28)
        quit.setAccessibilityIdentifier("quit-app")
        view.addSubview(quit)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSymbolMotion),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateSymbolMotion),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateSymbolMotion()
    }

    override func viewWillDisappear() {
        moduleSymbols.forEach { $0.setAnimating(false) }
        super.viewWillDisappear()
    }

    @objc private func updateSymbolMotion() {
        let allowed = view.window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for symbol in moduleSymbols {
            symbol.setAnimating(allowed && !symbol.visibleRect.isEmpty)
        }
    }

    func updateDiskHistory(store: DiskHistoryStore?, nextRecordingDate: Date?, error: String?) {
        historyController.store = store
        historyController.nextRecordingDate = nextRecordingDate
        historyController.recordingError = error
        if isViewLoaded, view.window != nil { historyController.reload() }
    }

    func prepareToShow() {
        _ = view
        onShowHistory?()
        historyController.reload()
    }

    func updateLoginItem(status: LoginItemStatus, error: String?) {
        _ = view
        loginStatus = status
        switch status {
        case .enabled: loginToggle.state = .on
        case .requiresApproval: loginToggle.state = .mixed
        case .notRegistered, .notFound: loginToggle.state = .off
        }
        loginSettings.isHidden = status != .requiresApproval
        let hint: String
        switch status {
        case .enabled: hint = "已启用 · 登录此账户时自动启动"
        case .notRegistered: hint = "登录此账户时自动启动"
        case .requiresApproval: hint = "等待批准 · 请在系统设置的登录项中允许 StatPeek"
        case .notFound: hint = "未找到系统启动项；勾选后重试注册"
        }
        loginHint.stringValue = error ?? hint
        loginHint.toolTip = error ?? hint
        loginHint.textColor = error == nil ? .secondaryLabelColor : .systemRed
        loginSymbol.contentTintColor = status == .enabled ? .systemGreen : .secondaryLabelColor
    }

    func update(snapshot: MetricSnapshot, selection: MetricSelection) {
        _ = view
        for metric in Metric.allCases {
            let color = selection.color(for: metric)
            colors[metric] = color
            cards[metric]?.update(snapshot: snapshot, selected: selection.selected.contains(metric), color: color)
        }
        updateSymbolMotion()
    }

    @objc private func showColorPanel(_ sender: MetricColorButton) {
        let panel = NSColorPanel.shared
        // Setting the initial color must not mutate the previous target's preference.
        panel.setTarget(nil)
        panel.setAction(nil)
        colorTarget = sender.metric
        panel.showsAlpha = false
        let initialColor = (colors[sender.metric] ?? .defaultColor(for: sender.metric)).nsColor
        panel.color = initialColor.usingColorSpace(.sRGB) ?? initialColor
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        guard let metric = colorTarget, let color = MetricColor(nsColor: sender.color) else { return }
        onColor?(metric, color)
    }

    @discardableResult
    private func text(_ string: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor, in parent: NSView? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.frame = frame
        (parent ?? view).addSubview(label)
        return label
    }

    @objc private func toggleMetric(_ sender: NSButton) { onToggle?(Metric.allCases[sender.tag]) }
    @objc private func toggleLoginItem(_ sender: NSButton) { onLoginToggle?(loginStatus != .enabled && loginStatus != .requiresApproval) }
    @objc private func openLoginSettings() { onOpenLoginSettings?() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

@MainActor
private final class FlippedDashboardView: NSView { override var isFlipped: Bool { true } }

@MainActor
private final class DashboardBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: dirtyRect).fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
private class DashboardCardView: NSView {
    var tint: NSColor = .labelColor { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        tint.withAlphaComponent(0.075).setFill()
        shape.fill()
        tint.withAlphaComponent(0.13).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
private final class MetricCardView: DashboardCardView {
    let metric: Metric
    let toggle: NSButton
    let colorButton: MetricColorButton
    let symbol: ModuleSymbolView
    private let value = NSTextField(labelWithString: "采样中…")
    private let progress = MetricProgressView()
    private let detail = NSTextField(labelWithString: "")
    private let percentage = NSTextField(labelWithString: "")

    init(metric: Metric, frame: NSRect) {
        self.metric = metric
        toggle = NSButton(checkboxWithTitle: metric.title, target: nil, action: nil)
        colorButton = MetricColorButton(metric: metric)
        let symbolName: String
        switch metric {
        case .disk: symbolName = "internaldrive"
        case .cpu: symbolName = "cpu"
        case .memory: symbolName = "memorychip"
        case .gpu: symbolName = "cpu.fill"
        }
        symbol = ModuleSymbolView(name: symbolName, color: .labelColor,
                                  frame: NSRect(x: 12, y: frame.height - 28, width: 18, height: 18))
        super.init(frame: frame)
        addSubview(symbol)
        toggle.frame = NSRect(x: 38, y: frame.height - 32, width: 183, height: 26)
        toggle.font = .systemFont(ofSize: 12, weight: .medium)
        toggle.setAccessibilityIdentifier("toggle-\(metric.rawValue)")
        addSubview(toggle)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        value.alignment = .right
        value.frame = NSRect(x: 222, y: frame.height - 28, width: 72, height: 18)
        value.setAccessibilityIdentifier("reading-\(metric.rawValue)")
        if metric == .disk { addSubview(value) }
        colorButton.frame = NSRect(x: 300, y: frame.height - 32, width: 28, height: 28)
        addSubview(colorButton)
        progress.frame = NSRect(x: 16, y: frame.height - 51, width: 240, height: 6)
        progress.setAccessibilityIdentifier("progress-\(metric.rawValue)")
        addSubview(progress)
        percentage.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        percentage.alignment = .right
        percentage.frame = NSRect(x: 266, y: frame.height - 56, width: 58, height: 17)
        percentage.setAccessibilityIdentifier(metric == .disk ? "usage-disk" : "reading-\(metric.rawValue)")
        addSubview(percentage)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 16, y: 6, width: 310, height: metric == .disk ? 34 : 17)
        detail.maximumNumberOfLines = 2
        detail.setAccessibilityIdentifier("detail-\(metric.rawValue)")
        addSubview(detail)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(snapshot: MetricSnapshot, selected: Bool, color: MetricColor) {
        toggle.state = selected ? .on : .off
        tint = color.nsColor
        symbol.contentTintColor = tint
        colorButton.color = tint
        value.stringValue = snapshot.readings[metric] ?? "采样中…"
        value.textColor = .labelColor
        progress.color = tint
        progress.percentage = snapshot.percentages[metric]
        percentage.stringValue = snapshot.percentages[metric].map { MetricMath.percentage($0) } ?? value.stringValue
        if metric == .disk, let disk = snapshot.disk {
            detail.stringValue = "总容量 \(DiskFormatter.format(bytes: disk.totalBytes)) · 已用 \(DiskFormatter.format(bytes: disk.usedBytes))\n剩余 \(DiskFormatter.format(bytes: disk.availableBytes)) · 进度为已用比例"
        } else if metric == .disk { detail.stringValue = "暂时无法读取磁盘容量" }
        else if metric == .memory { detail.stringValue = "估算使用量 · 不含可清除内存" }
        else if metric == .gpu { detail.stringValue = value.stringValue == "不可用" ? "驱动未提供有效使用率" : "设备使用率 · 取决于驱动支持" }
        else { detail.stringValue = value.stringValue == "采样中…" ? "正在建立两次采样之间的基准" : "两次采样之间的处理器使用率" }
        detail.toolTip = detail.stringValue
    }
}

@MainActor
final class MetricColorButton: NSButton {
    let metric: Metric
    var color: NSColor = .labelColor { didSet { needsDisplay = true } }
    init(metric: Metric) {
        self.metric = metric
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        title = ""
        toolTip = "选择\(metric.title)颜色"
        setAccessibilityLabel(toolTip)
        setAccessibilityIdentifier("color-\(metric.rawValue)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14))
        color.withAlphaComponent(0.65).setFill()
        dot.fill()
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        dot.lineWidth = 0.75
        dot.stroke()
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

@MainActor
final class MetricProgressView: NSView {
    var color: NSColor = .labelColor { didSet { needsDisplay = true } }
    var percentage: Double? {
        didSet {
            setAccessibilityValue(validPercentage.map { MetricMath.percentage($0) } ?? "不可用")
            needsDisplay = true
        }
    }
    var validPercentage: Double? {
        guard let percentage, percentage.isFinite, (0...100).contains(percentage) else { return nil }
        return percentage
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .progressIndicator }
    override func draw(_ dirtyRect: NSRect) {
        guard let value = validPercentage else { return }
        let track = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        track.fill()
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        track.lineWidth = 0.75
        track.stroke()
        guard value > 0 else { return }
        let fill = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: max(0, (bounds.width - 1) * value / 100), height: bounds.height - 1), xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.85).setFill()
        fill.fill()
        NSColor.labelColor.withAlphaComponent(0.22).setStroke()
        fill.lineWidth = 0.75
        fill.stroke()
    }
}
