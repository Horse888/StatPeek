import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    var onToggle: ((Metric) -> Void)?
    var onColor: ((Metric, MetricColor) -> Void)?
    var onLoginToggle: ((Bool) -> Void)?
    var onOpenLoginSettings: (() -> Void)?
    private var loginToggle: NSButton!
    private var loginHint: NSTextField!
    private var loginSettings: NSButton!
    private var loginStatus: LoginItemStatus = .notRegistered
    private var toggles: [Metric: NSButton] = [:]
    private var values: [Metric: NSTextField] = [:]
    private var swatches: [Metric: [ColorSwatchButton]] = [:]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 506))
        addText("StatPeek", x: 20, y: 468, size: 19, weight: .semibold)
        addText("勾选后直接显示在状态栏 · 每 2 秒更新", x: 20, y: 446, size: 11, color: .secondaryLabelColor)
        for (index, metric) in Metric.allCases.enumerated() {
            let y = CGFloat(380 - index * 72)
            let toggle = NSButton(checkboxWithTitle: metric.title, target: self, action: #selector(toggleMetric(_:)))
            toggle.frame = NSRect(x: 20, y: y + 32, width: 230, height: 26)
            toggle.tag = index
            toggle.setAccessibilityIdentifier("toggle-\(metric.rawValue)")
            view.addSubview(toggle)
            toggles[metric] = toggle
            let value = NSTextField(labelWithString: "")
            value.frame = NSRect(x: 250, y: y + 36, width: 110, height: 18)
            value.alignment = .right
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            value.setAccessibilityIdentifier("reading-\(metric.rawValue)")
            view.addSubview(value)
            values[metric] = value
            addText("颜色", x: 39, y: y + 5, size: 10, color: .secondaryLabelColor)
            for (colorIndex, color) in MetricColor.allCases.enumerated() {
                let swatch = ColorSwatchButton(color: color, metric: metric)
                swatch.frame = NSRect(x: 66 + colorIndex * 40, y: Int(y) - 6, width: 40, height: 40)
                swatch.target = self
                swatch.action = #selector(changeColor(_:))
                view.addSubview(swatch)
                swatches[metric, default: []].append(swatch)
            }
        }
        addText("内存为估算值；GPU 读数取决于驱动支持。", x: 20, y: 118, size: 10, color: .secondaryLabelColor)
        let separator = NSBox(frame: NSRect(x: 20, y: 108, width: 340, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
        loginToggle = NSButton(checkboxWithTitle: "开机自动启动", target: self, action: #selector(toggleLoginItem(_:)))
        loginToggle.frame = NSRect(x: 20, y: 76, width: 190, height: 26)
        loginToggle.allowsMixedState = true
        loginToggle.setAccessibilityIdentifier("launch-at-login")
        view.addSubview(loginToggle)
        loginHint = NSTextField(wrappingLabelWithString: "登录此账户时自动启动")
        loginHint.font = .systemFont(ofSize: 10)
        loginHint.textColor = .secondaryLabelColor
        loginHint.frame = NSRect(x: 39, y: 42, width: 321, height: 30)
        loginHint.setAccessibilityIdentifier("login-item-status")
        view.addSubview(loginHint)
        loginSettings = NSButton(title: "打开系统设置", target: self, action: #selector(openLoginSettings))
        loginSettings.bezelStyle = .rounded
        loginSettings.frame = NSRect(x: 242, y: 76, width: 120, height: 26)
        loginSettings.isHidden = true
        view.addSubview(loginSettings)
        let quit = NSButton(title: "退出 StatPeek", target: self, action: #selector(quitApp))
        quit.bezelStyle = .rounded
        quit.frame = NSRect(x: 246, y: 12, width: 116, height: 28)
        quit.setAccessibilityIdentifier("quit-app")
        view.addSubview(quit)
        addText("状态一瞥", x: 20, y: 21, size: 11, color: .secondaryLabelColor)
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
                         weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.frame = NSRect(x: x, y: y, width: 340, height: 24)
        view.addSubview(label)
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
final class ColorSwatchButton: NSButton {
    let color: MetricColor
    let metric: Metric
    var isChosen = false {
        didSet {
            setAccessibilityValue(isChosen ? "已选" : "未选")
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 14, dy: 14))
        color.nsColor.setFill()
        circle.fill()
        if isChosen {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 10, dy: 10))
            color.nsColor.setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
        }
    }
}
