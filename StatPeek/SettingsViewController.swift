import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    var onToggle: ((Metric) -> Void)?
    var onColor: ((Metric, MetricColor) -> Void)?
    var onLoginToggle: ((Bool) -> Void)?
    var onOpenLoginSettings: (() -> Void)?
    var onShowHistory: (() -> Void)?
    private let configurationView = NSView()
    private let historyController = DiskHistoryViewController()
    private let subtitle = NSTextField(labelWithString: "")
    private var pages: NSSegmentedControl!
    private var selectedPage = UserDefaults.standard.integer(forKey: "settingsPage") == 1 ? 1 : 0
    private var loginToggle: NSButton!
    private var loginHint: NSTextField!
    private var loginSettings: NSButton!
    private var loginStatus: LoginItemStatus = .notRegistered
    private var toggles: [Metric: NSButton] = [:]
    private var values: [Metric: NSTextField] = [:]
    private var swatches: [Metric: [ColorSwatchButton]] = [:]

    override func loadView() {
        view = PopoverBackgroundView(frame: NSRect(x: 0, y: 0, width: 380, height: 506))
        configurationView.frame = view.bounds
        view.addSubview(configurationView)
        addChild(historyController)
        historyController.view.frame = NSRect(x: 0, y: 42, width: 380, height: 396)
        view.addSubview(historyController.view)
        addText("StatPeek", x: 20, y: 468, size: 16, weight: .semibold)
        pages = NSSegmentedControl(labels: ["设置", "磁盘记录"], trackingMode: .selectOne,
                                   target: self, action: #selector(changePage(_:)))
        pages.frame = NSRect(x: 192, y: 468, width: 170, height: 26)
        pages.setAccessibilityIdentifier("preferences-page")
        view.addSubview(pages)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 20, y: 446, width: 340, height: 20)
        view.addSubview(subtitle)
        for (index, metric) in Metric.allCases.enumerated() {
            let y = CGFloat(380 - index * 72)
            let toggle = NSButton(checkboxWithTitle: metric.title, target: self, action: #selector(toggleMetric(_:)))
            toggle.frame = NSRect(x: 20, y: y + 32, width: 230, height: 26)
            toggle.tag = index
            toggle.setAccessibilityIdentifier("toggle-\(metric.rawValue)")
            configurationView.addSubview(toggle)
            toggles[metric] = toggle
            let value = NSTextField(labelWithString: "")
            value.frame = NSRect(x: 250, y: y + 36, width: 110, height: 18)
            value.alignment = .right
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            value.setAccessibilityIdentifier("reading-\(metric.rawValue)")
            configurationView.addSubview(value)
            values[metric] = value
            addText("颜色", x: 39, y: y + 5, size: 10, color: .secondaryLabelColor, in: configurationView)
            let palette = ColorPaletteView(frame: NSRect(x: 66, y: y - 2, width: 240, height: 28))
            palette.setAccessibilityLabel("\(metric.title)颜色选择")
            configurationView.addSubview(palette)
            for (colorIndex, color) in MetricColor.allCases.enumerated() {
                let swatch = ColorSwatchButton(color: color, metric: metric)
                swatch.frame = NSRect(x: colorIndex * 40, y: 0, width: 40, height: 28)
                swatch.target = self
                swatch.action = #selector(changeColor(_:))
                palette.addSwatch(swatch)
                swatches[metric, default: []].append(swatch)
            }
        }
        addText("内存为估算值；GPU 读数取决于驱动支持。", x: 20, y: 118, size: 10, color: .secondaryLabelColor, in: configurationView)
        let separator = NSBox(frame: NSRect(x: 20, y: 108, width: 340, height: 1))
        separator.boxType = .separator
        configurationView.addSubview(separator)
        loginToggle = NSButton(checkboxWithTitle: "开机自动启动", target: self, action: #selector(toggleLoginItem(_:)))
        loginToggle.frame = NSRect(x: 20, y: 76, width: 190, height: 26)
        loginToggle.allowsMixedState = true
        loginToggle.setAccessibilityIdentifier("launch-at-login")
        configurationView.addSubview(loginToggle)
        loginHint = NSTextField(wrappingLabelWithString: "登录此账户时自动启动")
        loginHint.font = .systemFont(ofSize: 10)
        loginHint.textColor = .secondaryLabelColor
        loginHint.frame = NSRect(x: 39, y: 42, width: 321, height: 30)
        loginHint.setAccessibilityIdentifier("login-item-status")
        configurationView.addSubview(loginHint)
        loginSettings = NSButton(title: "打开系统设置", target: self, action: #selector(openLoginSettings))
        loginSettings.bezelStyle = .rounded
        loginSettings.frame = NSRect(x: 242, y: 76, width: 120, height: 26)
        loginSettings.isHidden = true
        configurationView.addSubview(loginSettings)
        let quit = NSButton(title: "退出 StatPeek", target: self, action: #selector(quitApp))
        quit.bezelStyle = .rounded
        quit.frame = NSRect(x: 246, y: 12, width: 116, height: 28)
        quit.setAccessibilityIdentifier("quit-app")
        view.addSubview(quit)
        addText("状态一瞥", x: 20, y: 21, size: 11, color: .secondaryLabelColor)
        applyPageSelection()
    }

    func updateDiskHistory(store: DiskHistoryStore?, nextRecordingDate: Date?, error: String?) {
        historyController.store = store
        historyController.nextRecordingDate = nextRecordingDate
        historyController.recordingError = error
        if selectedPage == 1 { historyController.reload() }
    }

    func prepareToShow() {
        _ = view
        onShowHistory?()
        if selectedPage == 1 { historyController.reload() }
    }

    private func applyPageSelection() {
        pages.selectedSegment = selectedPage
        configurationView.isHidden = selectedPage == 1
        historyController.view.isHidden = selectedPage == 0
        subtitle.stringValue = selectedPage == 0 ? "勾选后直接显示在状态栏 · 每 2 秒更新" : "后台每 5 分钟记录 · 打开查看历史变化"
    }

    @objc private func changePage(_ sender: NSSegmentedControl) {
        selectedPage = sender.selectedSegment
        UserDefaults.standard.set(selectedPage, forKey: "settingsPage")
        applyPageSelection()
        if selectedPage == 1 { prepareToShow() }
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
    }

    func update(readings: [Metric: String], selection: MetricSelection) {
        _ = view
        for metric in Metric.allCases {
            let enabled = selection.selected.contains(metric)
            toggles[metric]?.state = enabled ? .on : .off
            values[metric]?.stringValue = enabled ? (readings[metric] ?? "采样中…") : "未显示"
            values[metric]?.textColor = enabled ? selection.color(for: metric).nsColor : .tertiaryLabelColor
            for swatch in swatches[metric] ?? [] {
                swatch.isChosen = swatch.color == selection.color(for: metric)
            }
        }
    }

    private func addText(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                         weight: NSFont.Weight = .regular, color: NSColor = .labelColor, in parent: NSView? = nil) {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.frame = NSRect(x: x, y: y, width: 340, height: 24)
        (parent ?? view).addSubview(label)
    }

    @objc private func toggleMetric(_ sender: NSButton) { onToggle?(Metric.allCases[sender.tag]) }
    @objc private func changeColor(_ sender: ColorSwatchButton) { onColor?(sender.metric, sender.color) }
    @objc private func toggleLoginItem(_ sender: NSButton) {
        // A pending registration can be cancelled with one click.
        onLoginToggle?(loginStatus != .enabled && loginStatus != .requiresApproval)
    }
    @objc private func openLoginSettings() { onOpenLoginSettings?() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

@MainActor
private final class PopoverBackgroundView: NSView {
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
final class ColorSwatchButton: NSButton {
    let color: MetricColor
    let metric: Metric
    var isChosen = false {
        didSet {
            guard oldValue != isChosen else { return }
            setAccessibilityValue(isChosen ? "已选" : "未选")
            if isChosen { (superview as? ColorPaletteView)?.select(self) }
            needsDisplay = true
        }
    }

    init(color: MetricColor, metric: Metric) {
        self.color = color
        self.metric = metric
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        title = ""
        toolTip = color.title
        setAccessibilityLabel("\(metric.title)颜色：\(color.title)")
        setAccessibilityIdentifier("color-\(metric.rawValue)-\(color.rawValue)")
        setAccessibilityValue("未选")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

@MainActor
private final class ColorPaletteView: NSView {
    private let selectionGlass: NSView

    override init(frame frameRect: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = SelectionGlassView()
            glass.style = .regular
            glass.cornerRadius = 9
            // A small round glass marker sits above the continuous six-color strip.
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            let checkmark = NSImageView()
            checkmark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
            checkmark.contentTintColor = .labelColor
            checkmark.imageScaling = .scaleProportionallyDown
            glass.contentView = checkmark
            selectionGlass = glass
        } else {
            selectionGlass = CompatibilityGlassView()
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        selectionGlass.wantsLayer = true
        selectionGlass.layer?.cornerRadius = 9
        selectionGlass.layer?.borderWidth = 0.75
        selectionGlass.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        selectionGlass.shadow = NSShadow()
        selectionGlass.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.18)
        selectionGlass.shadow?.shadowBlurRadius = 3
        selectionGlass.shadow?.shadowOffset = NSSize(width: 0, height: -1)
        selectionGlass.isHidden = true
        addSubview(selectionGlass)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func addSwatch(_ swatch: ColorSwatchButton) {
        addSubview(swatch, positioned: .below, relativeTo: selectionGlass)
    }

    func select(_ swatch: ColorSwatchButton) {
        selectionGlass.frame = NSRect(x: swatch.frame.midX - 9, y: swatch.frame.midY - 9,
                                     width: 18, height: 18)
        selectionGlass.isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).addClip()
        let width = bounds.width / CGFloat(MetricColor.allCases.count)
        for (index, color) in MetricColor.allCases.enumerated() {
            let rect = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
            color.nsColor.withAlphaComponent(0.72).setFill()
            NSBezierPath(rect: rect).fill()
            if index > 0 {
                NSColor.white.withAlphaComponent(0.25).setFill()
                NSBezierPath(rect: NSRect(x: rect.minX, y: 0, width: 0.5, height: bounds.height)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

@available(macOS 26.0, *)
@MainActor
private final class SelectionGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
}

@MainActor
private final class CompatibilityGlassView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let sleeve = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSGradient(starting: .white.withAlphaComponent(0.55), ending: .white.withAlphaComponent(0.08))?
            .draw(in: sleeve, angle: 90)
        let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.labelColor]))
        checkmark?.draw(in: NSRect(x: (bounds.width - 8) / 2, y: (bounds.height - 8) / 2, width: 8, height: 8))
    }
}
