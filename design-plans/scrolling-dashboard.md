# StatPeek 可滚动进度仪表盘

> 历史设计与验收计划：以下版本、安装位置和 GUI 验证步骤保留作为当时记录，不作为当前操作指令。现行本机交付以 [项目 AGENTS](../AGENTS.md) 为准，固定安装位置为 `~/Applications/StatPeek.app`；验证使用独立窗口，不操作用户鼠标键盘。旧生成证据按[全局产物规则](/Users/zy/.codex/development-guidelines/artifacts.md)核查必要性后处理，不要求永久保留。当前任务的明确限制优先。

Written against: 5099ddd01318cf40ade2a07405b3ffe2520d6b7f

## Evidence chain
- Surface: `StatPeek/SettingsViewController.swift`，由 `StatPeek/StatusBarController.swift` 实际 NSPopover 加载。
- Problem: 用户 2026-10-13 明确要求重新设计为上方设置、下方磁盘历史的上下滚动页面；左下角版本；各项淡背景与百分比进度；磁盘总量、已用、剩余；颜色用行尾小圆点，点击打开系统颜色选择器。
- Design evidence: `scrolling-dashboard-audit.md` 的三条直接需求/源码证据；`docs/SPEC.md` 的现有指标口径、真实数据、持久化及固定安装约定。
- Owner: `SettingsViewController` 负责组合，`MetricSelection` 负责偏好，`SystemSampler` 负责瞬时指标；历史继续由现有 DiskHistory 模块负责。
- Scope and affected surfaces: 设置浮层、卡片、配色入口；状态栏仅继承自定义颜色，不改变两行文字/宽度；历史曲线继承新布局，不改变采样或数据。
- Uncertainty: AppKit 系统颜色面板和 transient 浮层的实际共存/焦点需真实验证；小屏幕高度、滚动与页脚需实际验证。

## Design decision
实现一个 380 点宽、约 620 点高的原生可滚动仪表盘。固定顶部应用标题/简短说明，固定底部左侧版本号、右侧退出；中央 NSScrollView 包含设置卡片、启动设置，再是磁盘记录。移除互斥页签和大色条。保留已验证的原生产品身份与实时/持久化语义。

## Reuse
- `Metric` 的顺序/标题、`StatusLayout`、`StatusStripLayout` 的 9 点字母数字和紧凑宽度。
- `MetricSelection` 的选择/旧颜色偏好键与原型迁移。
- 现有 AppKit NSColor 语义色；淡色仅用于卡片底色/小色点，数值文字和进度需保持可见。
- `DiskFormatter` 一位小数与单字母单位。
- `DiskHistoryViewController` 和平滑蓝-靛蓝-紫曲线，SQLite 全量保留及 5 分钟记录控制器。
- `LoginItemController` 的真实系统状态与失败提示。
- Exemplar: `StatPeek/StatusStripView.swift` 的指标配色，`StatPeek/DiskHistoryViewController.swift` 的真实记录文本和曲线。
- 需要新增的能力：现有六值颜色枚举不能表示系统选择器的任意颜色；在原有偏好所有者中增加可验证的 RGB/sRGB 保存格式，兼容旧枚举字符串。卡片/进度视图属于这一个浮层，不创建全仓库 UI 库。

## Changes
1. `StatPeek/SettingsViewController.swift`
   - 用纵向 NSScrollView 替代页签。设置位于上方，磁盘记录位于下方；滚动能访问全部内容，刷新不重建滚动文档或把位置跳回顶部。
   - 顶部保留 StatPeek 与说明“勾选显示在状态栏”；底部固定版本（从 Bundle 读取，建议显示 `v0.3.0 (5)`），用户先说右侧后纠正为左下角，以左下角为准；退出仍在右。
   - 四项各有独立淡色背景卡片。首行复选框/名称、实时数值、行尾小圆点；下方是使用率进度。内存仍标明估算，GPU 不可用仍说明。
   - 颜色小圆点可点击面积保持易操作（约 28 点），视觉圆点约 12–14 点；不再展示六段长色条。
   - 点击小圆点打开系统 `NSColorPanel.shared`。用户变色后即时更新目标指标与状态栏，并保存；切换指标时目标正确，初始化选择器不应意外覆盖旧配色。不需要颜色透明度（关闭 alpha）。即使浮层暂时关闭，选色器回调仍正确保存；正常外部点击关闭浮层语义需保留。
   - Preserve: 四项选择、真实启动项、原始错误/不可用提示、用户当前偏好；历史完全复用，不另建数据库或删除数据。
2. `StatPeek/SystemSampler.swift`、相关容量/进度计算模型
   - 使用用户目录所在卷的真实总容量与可用容量，同一快照计算已用 = 总 - 可用、已用百分比；一位小数/单字母显示总、已用、剩余。
   - 容量无效（总≤0、可用<0、可用>总、读取失败）应显示不可用，不能产生负数/NaN、伪造零进度或与状态栏剩余量不同口径。
   - CPU/内存/GPU 使用率进度只有有效 0–100% 才绘制；采样中/不可用显示真实状态，不画成已知 0%。
   - 设置打开时可刷新四项用于卡片预览，勾选仅决定状态栏显示；浮层关闭后继续只采样选中项节约开销。明确记录这项行为。CPU 打开前若停止采样，应重新建立间隔基线。
   - Preserve: 状态栏 2 秒刷新、背景 5 分钟磁盘历史与原始 SQLite 数据、GPU/内存既有口径。
3. `StatPeek/MetricSelection.swift`、`Metrics.swift` 或专用颜色文件、`StatusStripView.swift`
   - 支持任意系统选色器 RGB（例如规范化 #RRGGBB）并持久化。旧的 blue/orange/purple/green/red/neutral 仍可解析，旧用户的颜色和选择不丢失，neutral 保持语义颜色。
   - 只修改必要颜色接口。新值无效则回退原默认，避免读取任意档案/非验证数据。单项变色不修改其他项；显示选择的开关不清除配色。
   - Preserve: D/C/M/G、107 点宽度、全取消仍可打开。
4. `DiskHistoryViewController` 组合与自适应
   - 将现有历史视图放入下方区域/卡片，调整宽度以匹配新卡片；复用真实读数、上次差值、范围、曲线、记录数/下次采样时间。保留其独立错误、首次记录和空范围状态。
   - 版式变窄时不能裁切文本或曲线；针对现有原生绘图测试如需调整，应保持实际绘图像素验证有效。

## Scope
- Inherit: 本机菜单栏浮层的新版布局、状态栏任意颜色。
- Verify: 全四项/全取消、实时卡片和状态栏、颜色选择目标切换、退出重启、启动项当前状态、磁盘已有历史、上下滚动、左下角版本、浅/深模式。
- Exclude: 无新主窗口、无网络/通知/后台辅助进程、无 App Store/公证发布、无删除真实用户记录、无需实际重启电脑。

## Validation
- Product: 首次打开看到设置卡片；可向下滚动到既有磁盘历史；固定版本始终在左下角；点击小色点打开真正系统颜色面板，变色即时且重启保持。
- Interface: 四项背景/进度/行尾色点层级清楚；磁盘总/已用/剩余一致；GPU 不可用不画假零；滚动时 2 秒刷新不丢位置，记录每 5 分钟静默继续。
- System: 复用现有历史、选择和启动所有者；对原型/旧颜色迁移、自定义颜色隔离/持久化、容量验证/计算、百分比不可用及面板交互写有意义测试。不要仅为 UI 常量写镜像测试。
- Repository: `xcodebuild -project StatPeek.xcodeproj -scheme StatPeek -configuration Release -destination 'platform=macOS' test` → 全部相关检查通过。不得加自选 DerivedData。
- Native GUI: 用 System Events 的真实辅助功能操作，记录实际启动、滚动、勾选、系统选色器、重启。原有脚本页签/24色块定位已失效，需要依据新 AX 树定位；不要沿用旧固定 button 索引。
- Screenshots: 应用/区域真实截图；先存临时路径再检查；窗口截图有时会捕获黑图或丢文字，此时使用确实可见的应用区域截图，避免把旁边私人内容提交到公共仓库。不要重绘/伪造截图。

## Delivery
- 用户此前明确授权本项目验证后更新 Applications 并推送公开 GitHub，本次延续该已授权交付，无需重新询问。
- 当前真实确认：安装 0.2.1 (4)，源树干净 HEAD 5099ddd01318cf40ade2a07405b3ffe2520d6b7f；当前选择全四项，旧配色 blue/orange/purple/green。启动服务实际状态需现场读，不从记忆推断；验收应恢复测试前偏好。
- 推荐本次版本 0.3.0 (5)，更新 project.yml 和一致的 Xcode 项目生成结果（使用项目现有 XcodeGen 流程，禁止手工读/改 pbxproj/Info.plist）。Xcode MCP 若可响应则用原生元数据工具，先确定有效 workspaceIdentifier；上次传绝对路径失败且工具曾无响应，不要无止境重试。
- 从实际 Xcode 配置解析 DerivedData；此前路径 `/Users/zy/Library/Developer/Xcode/DerivedData/StatPeek-anhklmjworinrafslgbpzsjdncrx` 需重查。项目已有 `/Users/zy/.local/bin/apple-derived-data-configure.mjs` 可解析/persist 配置。
- Release → 测试/签名/双架构/布尔 plist → 真实新 UI 验收 → 同一二进制复制至固定 `/Applications/StatPeek.app` → 验证一个运行实例、版本、已有记录与偏好 → 删除本次验证/备份/构建目录中重复 StatPeek.app，保留源/用户数据。
- 更新 README、SPEC、VALIDATION、真实截图/证据；保留历史证据标记版本，不把过去全套测试冒称本次已运行。
- GitHub 是 `https://github.com/Horse888/StatPeek`、main、origin HTTPS；提交/推送任务变更（包含本计划），验证远端 SHA 和干净状态。可用 `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin main`。网络失败先遵循 /Users/zy/AGENTS.md 的代理同步规则。

## Stop conditions
- 用户数据损坏/容量口径不可证明时保留原数据，报告真实不可用原因；不要用删除真实数据库修复。
- 未经用户明确要求不得为界面改版扩大为 App Store 发布、移除真实开机设置或系统重启。
- 与真实用户并行操作导致 transient 浮层关闭时重新打开进行独立原子验证，不将关闭误报为已通过的持续打开；无需重写正常的外部点击关闭行为来通过脚本。

## Design documentation
- After acceptance and validation: 将新上下布局、任意颜色、小圆点入口、容量口径、打开时全项预览/关闭时仅选中采样、版本位置记录到 docs/SPEC.md 和 README；真实验证记录到 docs/VALIDATION.md。
