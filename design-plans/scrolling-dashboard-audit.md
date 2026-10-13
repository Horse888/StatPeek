# StatPeek 浮层审查

审查基线：5099ddd01318cf40ade2a07405b3ffe2520d6b7f；2026-10-13（Asia/Shanghai）。依据源码，未将可读性或交互体验推断当作已观察的渲染结论。

## Design language
- Audited surface: 状态栏按钮打开的 StatPeek 设置/磁盘记录浮层。
- Design sources: 本次用户明确要求；已运行表面的所有者 `StatPeek/SettingsViewController.swift`；`docs/SPEC.md` 的现有状态栏、采样和存储约定。本次需求覆盖旧页签及六段调色条设计。
- Documented decisions: 原生 AppKit、无主界面/无 Dock、两行 D/C/M/G 数值、107 点紧凑状态栏、2 秒刷新、5 分钟静默磁盘记录、真实数据、平滑渐变线条、本机持久化。
- Governing owners and consumers: `StatusBarController.swift:26` 将 `SettingsViewController` 放入 NSPopover；其 `loadView` 生成配置与历史表面；`MetricSelection` 保存选项/颜色，`SystemSampler` 供实时读数，`DiskHistoryViewController` 消费 SQLite 历史。
- Explicit exceptions: None documented.

## Findings
| # | Problem | Evidence | Proposed change | Scope | Confidence |
| --- | --- | --- | --- | --- | --- |
| 1 | 页签互斥布局不满足同页上下浏览；页脚未显示版本 | 用户指定设置在上、记录在下、上下滚动、左下角版本；`SettingsViewController.swift:31-35,110-121` 用页签控制两部分隐藏；`:88-94` 页脚仅含退出和“状态一瞥”。该控制器由实际 NSPopover 消费 | 用一个原生纵向滚动表面依次容纳设置和历史；固定页脚左侧显示 Bundle 的真实版本/构建号 | 浮层组合与页脚 | High |
| 2 | 指标只呈现文本，缺少用户要求的进度卡片和磁盘容量分解 | 用户指定每项背景、百分比进度、磁盘总/已用/剩余；`SettingsViewController.swift:40-54` 生成 checkbox 与文本；`SystemSampler.sample` 对磁盘只返回剩余量字符串，`:145-155` 将文本写入实际卡片前身 | 四个淡色背景卡片，CPU/内存/GPU 显示使用率进度；磁盘显示已用进度并列出总容量、已用、剩余，失败不伪造零 | 指标卡片及供其显示的容量快照 | High |
| 3 | 独占一行的调色条与用户要求的小圆点入口不同 | 用户已选定行尾小圆点打开系统选色器；`SettingsViewController.swift:55-65` 为每项创建 240×28 六段色条，`StatusBarController.swift:38-42` 将选择保存并更新实际状态栏 | 每项行尾小圆点打开 NSColorPanel，支持自定义颜色并兼容已有保存的预设配色 | 颜色入口及既有配色持久化 | High |

## Improve first
先完成统一滚动表面的组合（发现 1），它确定卡片和磁盘记录的上下关系以及固定版本页脚。三项均已由用户明确选定，交接计划为 `scrolling-dashboard.md`，无需再次询问选项。
