# 系统原生控件与状态栏字体 · 2026-10-26

用户要求 Segment 使用系统液态玻璃样式，所有 UI 使用系统原生组件；后续补充状态栏使用系统默认字体并将 design 设为等宽。

## 实施合同

- Segment 不再固定旧 rounded 外观，使用 automatic、系统 capsule 边框形状及支持系统上的 tabs 角色；使用系统玻璃材质，保留三个范围的单选行为。
- 手绘卡片换为 NSBox；手绘进度换为原生 SwiftUI ProgressView；颜色井不再覆盖 draw，使用 NSColorWell.minimal；退出按钮直接使用 NSButton.glass，不叠加自建按钮背景。系统旧版本使用其支持的原生样式。
- 状态栏使用 NSTextField / NSImageView，字体由 NSFont.monospacedSystemFont 工厂获取，Regular 9 点。移除固定 Menlo 与手工 CTLineDraw；宽度计算仍使用同一系统字体，并为原生标签留出 cell 内边距。
- 保留布局层级、文案、两行 D/C/M/G、选择/配色回调、采样/存储以及此前状态栏关闭修复。系统自身按窗口活跃状态处理控件显示，不伪造材质或重绘系统皮肤。

## 验证与交付

先以独立非激活窗口核对原生组件，再进行 Release 测试；覆盖状态栏 16 种选择、7 种配色、浅深/1x/2x 原生渲染，以及颜色井回调、进度有效/无效值、三段切换、短屏布局、选色/分层关闭与独立原生按钮手势。截图明确为合成数据；用户桌面鼠标键盘不操作。

每次实际 App build 递增编号。按项目 AGENTS 后台替换个人 Applications，核对签名、哈希、唯一进程、设置和历史保留后清理本次重复副本，提交并推送。

依据：[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[AppKit 新设计](https://developer.apple.com/videos/play/wwdc2025/310/)、[macOS 27 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)及本机 macOS 27 SDK 声明。官方样式 API 与实窗效果分别核对。
