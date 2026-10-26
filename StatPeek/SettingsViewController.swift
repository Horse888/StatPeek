import AppKit
import SwiftUI

@MainActor
final class SettingsViewController: NSViewController {
    static let headerHeight: CGFloat = 64
    static let footerHeight: CGFloat = 44
    static var chromeHeight: CGFloat { headerHeight + footerHeight }
    var applicationIcon: NSImage?
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
        let icon = NSImageView(image: applicationIcon ?? NSImage(named: NSImage.applicationIconName)
                               ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        icon.frame = NSRect(x: 14, y: 660, width: 28, height: 28)
        icon.imageScaling = .scaleProportionallyDown
        icon.autoresizingMask = .minYMargin
        icon.setAccessibilityElement(false)
        icon.setAccessibilityIdentifier("app-icon")
        dashboardContent.addSubview(icon)
        let heading = text("StatPeek", frame: NSRect(x: 50, y: 662, width: 224, height: 24), size: 18, weight: .semibold)
        let subtitle = text("勾选显示在状态栏 · 每 2 秒更新", frame: NSRect(x: 14, y: 640, width: 260, height: 16), size: 11, color: .dashboardSecondaryLabel)
        heading.autoresizingMask = .minYMargin
        subtitle.autoresizingMask = .minYMargin
        scrollView.frame = NSRect(x: 0, y: Self.footerHeight, width: 288, height: 700 - Self.chromeHeight)
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
        var y: CGFloat = 4
        for (index, metric) in Metric.allCases.enumerated() {
            let height: CGFloat = metric == .disk ? 88 : 70
            let card = MetricCardView(metric: metric, frame: NSRect(x: 14, y: y, width: 260, height: height))
            card.toggle.tag = index
            card.toggle.target = self
            card.toggle.action = #selector(toggleMetric(_:))
            card.colorButton.target = self
            card.colorButton.action = #selector(colorChanged(_:))
            document.addSubview(card)
            cards[metric] = card
            moduleSymbols.append(card.symbol)
            y += height + 4
        }
        let historySymbol = ModuleSymbolView(name: "chart.xyaxis.line", color: .systemBlue,
                                             frame: NSRect(x: 17, y: y + 3, width: 18, height: 18))
        document.addSubview(historySymbol)
        moduleSymbols.append(historySymbol)
        text("磁盘记录", frame: NSRect(x: 39, y: y, width: 235, height: 22), size: 15, weight: .semibold, in: document)
        y += 24
        let historyCard = DashboardCardView(frame: NSRect(x: 14, y: y, width: 260, height: 304))
        document.addSubview(historyCard)
        addChild(historyController)
        historyController.contentWidth = 260
        historyController.view.frame = NSRect(x: 0, y: 8, width: 260, height: 288)
        historyCard.contentView?.addSubview(historyController.view)
        y += 312
        document.setFrameSize(NSSize(width: 288, height: y + 4))
        loginToggle = NSButton(checkboxWithTitle: "开机自动启动", target: self, action: #selector(toggleLoginItem(_:)))
        loginToggle.font = .systemFont(ofSize: 10)
        loginToggle.frame = NSRect(x: 96, y: 9, width: 108, height: 26)
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
        let versionLabel = text("v\(version) (\(build))", frame: NSRect(x: 14, y: 13, width: 66, height: 18), size: 10, color: .dashboardSecondaryLabel)
        versionLabel.setAccessibilityIdentifier("app-version")
        let quit = NSButton(title: "退出", target: self, action: #selector(quitApp))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        if #available(macOS 26.0, *) {
            quit.bezelStyle = .glass
            quit.borderShape = .capsule
        }
        quit.font = .systemFont(ofSize: 11, weight: .medium)
        quit.attributedTitle = NSAttributedString(string: "退出", attributes: [
            .foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 11, weight: .medium)])
        quit.frame = NSRect(x: 220, y: 10, width: 54, height: 24)
        quit.setAccessibilityIdentifier("quit-app")
        dashboardContent.addSubview(quit)
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
        stopSymbolMotion()
        super.viewWillDisappear()
    }

    func stopSymbolMotion() {
        moduleSymbols.forEach { $0.setAnimating(false) }
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
        let fixedHeight = Self.chromeHeight // Header and footer remain visible on short screens.
        let desiredHeight = document.frame.height + fixedHeight
        let height = min(desiredHeight, max(fixedHeight + 1, availableHeight))
        view.setFrameSize(NSSize(width: 288, height: height))
        scrollView.frame = NSRect(x: 0, y: Self.footerHeight, width: 288, height: height - fixedHeight)
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
private class DashboardCardView: NSBox {
    var tint: NSColor = .labelColor { didSet { updateFill() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        boxType = .custom
        titlePosition = .noTitle
        contentViewMargins = .zero
        cornerRadius = 12
        borderWidth = 0.5
        borderColor = .separatorColor
        updateFill()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }
    private func updateFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fillColor = tint.withAlphaComponent(0.22)
        }
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
        contentView?.addSubview(symbol)
        toggle.frame = NSRect(x: 8, y: frame.height - 32, width: 24, height: 26)
        toggle.setAccessibilityLabel(metric.title)
        toggle.font = .systemFont(ofSize: 12, weight: .medium)
        toggle.setAccessibilityIdentifier("toggle-\(metric.rawValue)")
        contentView?.addSubview(toggle)
        titleLabel.frame = NSRect(x: 56, y: frame.height - 28, width: metric == .disk ? 94 : 158, height: 18)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.setAccessibilityElement(false)
        contentView?.addSubview(titleLabel)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        value.alignment = .right
        value.frame = NSRect(x: 150, y: frame.height - 28, width: 68, height: 18)
        value.setAccessibilityIdentifier("reading-\(metric.rawValue)")
        if metric == .disk { contentView?.addSubview(value) }
        colorButton.frame = NSRect(x: 226, y: frame.height - 28, width: 20, height: 20)
        contentView?.addSubview(colorButton)
        progress.frame = NSRect(x: 14, y: frame.height - 42, width: 164, height: 6)
        progress.setAccessibilityIdentifier("progress-\(metric.rawValue)")
        contentView?.addSubview(progress)
        percentage.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        percentage.alignment = .right
        percentage.frame = NSRect(x: 188, y: frame.height - 47, width: 58, height: 17)
        percentage.setAccessibilityIdentifier(metric == .disk ? "usage-disk" : "reading-\(metric.rawValue)")
        contentView?.addSubview(percentage)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .dashboardSecondaryLabel
        detail.frame = NSRect(x: 14, y: metric == .disk ? 8 : 6, width: 232, height: metric == .disk ? 28 : 17)
        detail.maximumNumberOfLines = 2
        detail.setAccessibilityIdentifier("detail-\(metric.rawValue)")
        contentView?.addSubview(detail)
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
        colorButton.alphaValue = selected ? 1 : 0.5
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
    init(metric: Metric) {
        self.metric = metric
        super.init(frame: .zero)
        colorWellStyle = .minimal
        controlSize = .small
        isContinuous = true
        if #available(macOS 14.0, *) { supportsAlpha = false }
        toolTip = "选择\(metric.title)颜色"
        setAccessibilityLabel(toolTip)
        setAccessibilityIdentifier("color-\(metric.rawValue)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class MetricProgressView: NSView {
    private var hosting: NSHostingView<NativeMetricProgress>!
    var color: NSColor = .labelColor { didSet { updateProgress() } }
    var percentage: Double? {
        didSet {
            setAccessibilityValue(validPercentage.map { MetricMath.percentage($0) } ?? "不可用")
            updateProgress()
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        hosting = NSHostingView(rootView: NativeMetricProgress(percentage: nil, color: color))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateProgress() {
        hosting?.rootView = NativeMetricProgress(percentage: validPercentage, color: color)
    }
    var validPercentage: Double? {
        guard let percentage, percentage.isFinite, (0...100).contains(percentage) else { return nil }
        return percentage
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .progressIndicator }
}

private struct NativeMetricProgress: View {
    let percentage: Double?
    let color: NSColor
    var body: some View {
        if let percentage {
            ProgressView(value: percentage, total: 100)
                .progressViewStyle(.linear)
                .tint(Color(nsColor: color))
        }
    }
}
