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
    private var dashboardContent: NSView!
    private var cards: [Metric: MetricCardView] = [:]
    private var moduleSymbols: [ModuleSymbolView] = []
    private var loginToggle: NSButton!
    private var loginStatus: LoginItemStatus = .notRegistered

    override func loadView() {
        let surface = GlassSurfaceView(frame: NSRect(x: 0, y: 0, width: 288, height: 700), cornerRadius: 18,
                                       interactive: false)
        view = surface
        dashboardContent = surface.content
        let heading = text("StatPeek", frame: NSRect(x: 14, y: 654, width: 260, height: 24), size: 18, weight: .semibold)
        let subtitle = text("勾选显示在状态栏 · 每 2 秒更新", frame: NSRect(x: 14, y: 632, width: 260, height: 18), size: 11, color: .secondaryLabelColor)
        heading.autoresizingMask = .minYMargin
        subtitle.autoresizingMask = .minYMargin
        scrollView.frame = NSRect(x: 0, y: 48, width: 288, height: 574)
        // Its height is set explicitly below. Glass content can resize again after
        // window attachment; autoresizing the height would apply the delta twice.
        scrollView.autoresizingMask = .width
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.masksToBounds = true
        scrollView.setAccessibilityIdentifier("dashboard-scroll")
        let document = FlippedDashboardView(frame: NSRect(x: 0, y: 0, width: 288, height: 1010))
        scrollView.documentView = document
        dashboardContent.addSubview(scrollView)
        var y: CGFloat = 8
        for (index, metric) in Metric.allCases.enumerated() {
            let height: CGFloat = metric == .disk ? 108 : 80
            let card = MetricCardView(metric: metric, frame: NSRect(x: 14, y: y, width: 260, height: height))
            card.toggle.tag = index
            card.toggle.target = self
            card.toggle.action = #selector(toggleMetric(_:))
            card.colorButton.target = self
            card.colorButton.action = #selector(colorChanged(_:))
            document.addSubview(card)
            cards[metric] = card
            moduleSymbols.append(card.symbol)
            y += height + 6
        }
        let historySymbol = ModuleSymbolView(name: "chart.xyaxis.line", color: .systemBlue,
                                             frame: NSRect(x: 17, y: y + 3, width: 18, height: 18))
        document.addSubview(historySymbol)
        moduleSymbols.append(historySymbol)
        text("磁盘记录", frame: NSRect(x: 39, y: y, width: 235, height: 24), size: 15, weight: .semibold, in: document)
        y += 28
        let historyCard = DashboardCardView(frame: NSRect(x: 14, y: y, width: 260, height: 320))
        document.addSubview(historyCard)
        addChild(historyController)
        historyController.contentWidth = 260
        historyController.view.frame = NSRect(x: 0, y: 8, width: 260, height: 304)
        historyCard.addSubview(historyController.view)
        y += 328
        document.setFrameSize(NSSize(width: 288, height: y + 8))
        loginToggle = NSButton(checkboxWithTitle: "开机自动启动", target: self, action: #selector(toggleLoginItem(_:)))
        loginToggle.font = .systemFont(ofSize: 10)
        loginToggle.frame = NSRect(x: 96, y: 11, width: 108, height: 26)
        loginToggle.allowsMixedState = true
        loginToggle.setAccessibilityIdentifier("launch-at-login")
        let loginMenu = NSMenu()
        let loginSettings = NSMenuItem(title: "系统登录项设置…", action: #selector(openLoginSettings), keyEquivalent: "")
        loginSettings.target = self
        loginMenu.addItem(loginSettings)
        loginToggle.menu = loginMenu
        dashboardContent.addSubview(loginToggle)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let versionLabel = text("v\(version) (\(build))", frame: NSRect(x: 14, y: 15, width: 66, height: 18), size: 10, color: .secondaryLabelColor)
        versionLabel.setAccessibilityIdentifier("app-version")
        let quitPill = glassPill(frame: NSRect(x: 220, y: 12, width: 54, height: 24))
        let quit = NSButton(title: "退出", target: self, action: #selector(quitApp))
        quit.isBordered = false
        quit.font = .systemFont(ofSize: 11, weight: .medium)
        quit.attributedTitle = NSAttributedString(string: "退出", attributes: [.foregroundColor: NSColor.systemRed,
                                                                                .font: NSFont.systemFont(ofSize: 11, weight: .medium)])
        quit.frame = NSRect(x: 0, y: 0, width: 54, height: 24)
        quit.setAccessibilityIdentifier("quit-app")
        quitPill.addSubview(quit)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSymbolMotion),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateSymbolMotion),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        fitToAvailableHeight(.greatestFiniteMagnitude)
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
            symbol.setAnimating(allowed && symbol.permitsAnimation && !symbol.visibleRect.isEmpty)
        }
    }

    func updateDiskHistory(store: DiskHistoryStore?, nextRecordingDate: Date?, error: String?) {
        historyController.store = store
        historyController.nextRecordingDate = nextRecordingDate
        historyController.recordingError = error
        if isViewLoaded, view.window != nil { historyController.reload() }
    }

    func prepareToShow(availableHeight: CGFloat) {
        _ = view
        fitToAvailableHeight(availableHeight)
        onShowHistory?()
        historyController.reload()
    }

    func fitToAvailableHeight(_ availableHeight: CGFloat) {
        guard let document = scrollView.documentView else { return }
        let fixedHeight: CGFloat = 126 // Header and footer remain visible on short screens.
        let desiredHeight = document.frame.height + fixedHeight
        let height = min(desiredHeight, max(fixedHeight + 1, availableHeight))
        view.setFrameSize(NSSize(width: 288, height: height))
        scrollView.frame = NSRect(x: 0, y: 48, width: 288, height: height - fixedHeight)
        let needsScrolling = document.frame.height > scrollView.frame.height + 0.5
        scrollView.hasVerticalScroller = needsScrolling
        scrollView.verticalScrollElasticity = needsScrolling ? .allowed : .none
        if !needsScrolling { scrollView.contentView.scroll(to: .zero) }
    }

    func updateLoginItem(status: LoginItemStatus, error: String?) {
        _ = view
        loginStatus = status
        switch status {
        case .enabled: loginToggle.state = .on
        case .requiresApproval: loginToggle.state = .mixed
        case .notRegistered, .notFound: loginToggle.state = .off
        }
        let hint: String
        switch status {
        case .enabled: hint = "已启用 · 登录此账户时自动启动"
        case .notRegistered: hint = "登录此账户时自动启动"
        case .requiresApproval: hint = "等待批准 · 请在系统设置的登录项中允许 StatPeek"
        case .notFound: hint = "未找到系统启动项；勾选后重试注册"
        }
        loginToggle.toolTip = (error ?? hint) + " · 右键打开系统登录项设置"
        loginToggle.setAccessibilityHelp(error ?? hint)
        let color: NSColor = error != nil || status == .requiresApproval ? .systemOrange :
            (status == .enabled ? .labelColor : .secondaryLabelColor)
        loginToggle.attributedTitle = NSAttributedString(string: "开机自动启动", attributes: [.foregroundColor: color,
                                                                                             .font: NSFont.systemFont(ofSize: 10)])

    }

    func update(snapshot: MetricSnapshot, selection: MetricSelection) {
        _ = view
        for metric in Metric.allCases {
            let color = selection.color(for: metric)
            cards[metric]?.update(snapshot: snapshot, selected: selection.selected.contains(metric), color: color)
        }
        updateSymbolMotion()
    }

    @objc private func colorChanged(_ sender: MetricColorButton) {
        guard let color = MetricColor(nsColor: sender.color) else { return }
        onColor?(sender.metric, color)
    }

    private func glassPill(frame: NSRect) -> NSView {
        let glass = GlassSurfaceView(frame: frame)
        dashboardContent.addSubview(glass)
        return glass.content
    }

    @discardableResult
    private func text(_ string: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor, in parent: NSView? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.frame = frame
        (parent ?? dashboardContent).addSubview(label)
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
    private let titleLabel: NSTextField
    private var renderedColor: MetricColor?

    init(metric: Metric, frame: NSRect) {
        self.metric = metric
        toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        titleLabel = NSTextField(labelWithString: metric.title)
        colorButton = MetricColorButton(metric: metric)
        let symbolName: String
        switch metric {
        case .disk: symbolName = "internaldrive.fill"
        case .cpu: symbolName = "cpu.fill"
        case .memory: symbolName = "memorychip.fill"
        case .gpu: symbolName = "cube.fill"
        }
        symbol = ModuleSymbolView(name: symbolName, color: .labelColor,
                                  frame: NSRect(x: 34, y: frame.height - 28, width: 18, height: 18), pointSize: 14)
        super.init(frame: frame)
        addSubview(symbol)
        toggle.frame = NSRect(x: 8, y: frame.height - 32, width: 24, height: 26)
        toggle.setAccessibilityLabel(metric.title)
        toggle.font = .systemFont(ofSize: 12, weight: .medium)
        toggle.setAccessibilityIdentifier("toggle-\(metric.rawValue)")
        addSubview(toggle)
        titleLabel.frame = NSRect(x: 56, y: frame.height - 28, width: metric == .disk ? 94 : 158, height: 18)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        value.alignment = .right
        value.frame = NSRect(x: 150, y: frame.height - 28, width: 68, height: 18)
        value.setAccessibilityIdentifier("reading-\(metric.rawValue)")
        if metric == .disk { addSubview(value) }
        let colorGlass = GlassSurfaceView(frame: NSRect(x: 222, y: frame.height - 32, width: 28, height: 28))
        colorButton.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        colorGlass.content.addSubview(colorButton)
        addSubview(colorGlass)
        progress.frame = NSRect(x: 14, y: frame.height - 51, width: 164, height: 6)
        progress.setAccessibilityIdentifier("progress-\(metric.rawValue)")
        addSubview(progress)
        percentage.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        percentage.alignment = .right
        percentage.frame = NSRect(x: 188, y: frame.height - 56, width: 58, height: 17)
        percentage.setAccessibilityIdentifier(metric == .disk ? "usage-disk" : "reading-\(metric.rawValue)")
        addSubview(percentage)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 14, y: 6, width: 232, height: metric == .disk ? 34 : 17)
        detail.maximumNumberOfLines = 2
        detail.setAccessibilityIdentifier("detail-\(metric.rawValue)")
        addSubview(detail)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(snapshot: MetricSnapshot, selected: Bool, color: MetricColor) {
        toggle.state = selected ? .on : .off
        tint = selected ? color.nsColor : .systemGray
        symbol.contentTintColor = tint
        symbol.permitsAnimation = selected
        // Metric refreshes must not overwrite a color being chosen in the native picker.
        if renderedColor != color {
            renderedColor = color
            colorButton.color = color.nsColor
        }
        colorButton.displayedColor = tint
        titleLabel.textColor = selected ? .labelColor : .secondaryLabelColor
        value.stringValue = snapshot.readings[metric] ?? "采样中…"
        value.textColor = selected ? .labelColor : .secondaryLabelColor
        percentage.textColor = value.textColor
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
final class MetricColorButton: NSColorWell {
    let metric: Metric
    var displayedColor: NSColor = .labelColor { didSet { needsDisplay = true } }
    init(metric: Metric) {
        self.metric = metric
        super.init(frame: .zero)
        colorWellStyle = .minimal
        isContinuous = true
        if #available(macOS 14.0, *) { supportsAlpha = false }
        toolTip = "选择\(metric.title)颜色"
        setAccessibilityLabel(toolTip)
        setAccessibilityIdentifier("color-\(metric.rawValue)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14))
        NSGraphicsContext.saveGraphicsState()
        dot.addClip()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
        displayedColor.withAlphaComponent(0.65).setFill()
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
