# StatPeek · 状态一瞥

## 名称与范围

Stat 表示系统状态，Peek 表示点开看一眼。产品、主 Target、共享 Scheme 均使用 StatPeek。
当前任务完成原生 macOS 项目、本机界面验证、应用图标、Xcode 应用信息、Applications 安装，并推送到用户授权的 GitHub 公开仓库；商标核验与 App Store 上架另行处理。

应用信息：StatPeek，Bundle ID `com.zyapps.StatPeek`，版本 0.1.0 / Build 1，Utilities 分类，最低 macOS 13.0。原型 `local.StatPeek` 的选择与配色在新标识首次启动时迁移，已有新偏好不覆盖。

图标：深蓝底板、两排彩色状态指示，见 `icon-design.md`；AppIcon 资源包含 macOS 标准 16–1024 像素尺寸。

## 用户行为

- macOS 13 或更高版本；Swift + AppKit，兼容 Apple Silicon 和 Intel 的源码构建。
- 无主窗口、无 Dock 图标，仅一个菜单栏状态项。
- 已选指标直接显示在状态栏：上下两行，每行最多两项，每项为小图标 + 数值，使用等宽数字。四项顺序为磁盘、CPU、内存、GPU；一项时垂直居中。
- 用户已明确选定「两行排列，每项图标 + 数值」布局。
- 点击状态项打开原生 NSPopover，直接给出四个复选框，无嵌套子菜单。
- 默认全部选中；勾选保存至本机 UserDefaults，重启恢复。操作即时改变状态栏，浮层保持打开。
- 每项支持蓝、橙、紫、绿、红、默认文字色六种选择，点色块立即应用并保存。默认磁盘蓝、CPU 橙、内存紫、GPU 绿。
- 全部取消时状态栏保留一个可点击图标，浮层可恢复任意选项。
- 状态栏持续每 2 秒更新，浮层打开或关闭都继续刷新，仅采样所选指标。CPU 需要两次采样，首次显示「采样中…」，紧凑状态栏显示「…」。
- 不读取失败时伪造零值；采集失败显示「不可用」。
- 浮层提供「退出 StatPeek」，点击外部关闭浮层，无其他窗口。

## 指标口径

- 磁盘：当前用户主目录所在卷的可用容量，Foundation volumeAvailableCapacity，按十进制容量统一保留一位小数，单位使用 B/K/M/G/T/P/E 单字母，例如 320.8G；状态栏、浮层和提示文字一致。APFS 共享容器可能与其他容量口径不同。
- CPU：Mach 系统 CPU ticks 两次差值，(user + system + nice) / total；系统总体百分比为 0–100%，非单进程百分比。
- 内存：Mach 活跃页 + wired 页 + compressor 页 − purgeable 页，除以物理内存；明确标为「内存使用率（估算）」，不声称与活动监视器一致。
- GPU：IOKit IOAccelerator 的 PerformanceStatistics 中 Device Utilization %；多 GPU 显示可读设备的最高值。驱动字段没有稳定的公开跨设备保证，缺失显示「不可用」，并提供菜单提示。当前机器已观察到此字段，但仍需实机对照验证。
- 不调用需要 sudo 的 powermetrics，不安装辅助进程或新增权限。

## 实现计划

1. 保存规格、验收标准、采样口径与风险。
2. 建立 XcodeGen 配置、StatPeek Target/Scheme 与无界面的应用入口。
3. 分离指标计算、系统采样、选择/颜色存储、状态栏绘制与浮层控制器。
4. 验证计算边界、计数器溢出、GPU 不可用、选择/颜色恢复、两行排列及空选择；构建项目并检查有效 Info.plist。
5. 在本机验证状态栏和浮层持续刷新、四项勾选、颜色变更、退出重启恢复；确认后安装同一份 Release 至 Applications，重新验证启动路径，只保留一份最终可运行应用。

## 验收

- [x] 启动后无主窗口与 Dock 图标，菜单栏恰好一个状态项，显示两行图标/数值。
- [x] 单击打开浮层；浮层持续打开 6 秒以上，状态栏及浮层数值仍刷新，关闭浮层后状态栏继续刷新。
- [x] 四个信息项均可直接勾选/取消；状态栏立即体现选择，浮层不关闭。
- [x] 更改颜色立即生效，退出再启动，选择及颜色保持；全取消仍能打开配置并退出。
- [ ] CPU、内存、磁盘与系统数据大致对照，遵循本文口径。
- [x] GPU 支持时显示读数，不支持时有明确提示。
- [x] 单元测试与 Release 构建通过，有效 plist 的 LSUIElement、加密声明为布尔类型。
- [x] Applications 中的最终 Release 启动成功，验证进程路径，移除测试/构建目录中的重复可运行应用。

自动测试、编译不等于菜单交互及读数的人工验收；在 VALIDATION.md 分开记录。

## 参考

- [Apple NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [Apple RunLoop.Mode.common](https://developer.apple.com/documentation/foundation/runloop/mode/common)
- [Apple LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [Apple NSPopover](https://developer.apple.com/documentation/appkit/nspopover)
