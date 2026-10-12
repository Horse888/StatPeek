# 验证记录

日期：2026-10-12（Asia/Shanghai）。环境：本机 Apple Silicon、Xcode 27.1、Swift 6.4。应用最低 macOS 13。

## 自动检查

- Release 配置下的 **16 项 XCTest 全部通过，0 失败**。
- 最终原生 Release 构建成功。
- 覆盖 CPU 差值、空闲/满负载、UInt32 溢出、无增量、内存估算边界、GPU 不可用、选择与颜色恢复、全部 16 种指标选择的两行布局，以及原型偏好迁移。
- 磁盘格式测试覆盖一位小数、单字母单位、跨单位舍入和不可用值。
- 临时 UserDefaults suite 保证单元测试不覆盖真实偏好。

## 本机界面验收

使用 macOS 原生辅助功能操作和真实截图验证最终 Release，未使用替代界面或重绘截图。

- 无主窗口、无 Dock 图标，只有一个状态栏项。
- 四项以两行彩色「图标 + 数值」显示；截图见 `assets/statusbar.png`。
- 浮层直接提供四个复选框及六种颜色，无嵌套菜单；截图见 `assets/popover.png`。
- 浮层关闭时连续约 7 秒采样，CPU 读数发生变化，状态栏持续刷新。
- 浮层持续打开约 7 秒，状态栏及浮层 CPU、内存、GPU 读数均发生变化。
- 四项逐一取消及恢复，状态栏立即增减相应指标，浮层保持打开。
- CPU 改红色、GPU 改紫色后，通过真实「退出 StatPeek」按钮退出并重新启动；选择及颜色保持。
- 磁盘/CPU 的混合选择、四项全取消均经过退出重启验证。
- 全取消时状态栏保留可点击图标，浮层可恢复显示项。
- 测试结束恢复全选及默认蓝/橙/紫/绿配色。
- 状态栏与浮层均显示一位小数和单字母磁盘单位，例如 `312.6G`。

完整机器可读记录见 [gui-acceptance.json](gui-acceptance.json)。

## 安装核验

- 安装位置：`/Applications/StatPeek.app`。
- 安装副本与最终界面验收过的原生 Release 可执行文件 SHA-256 一致：`b55f7224caf7d06727294f3b9eb5742e229cd13f1494a9c5418691ccaff08370`。
- `codesign --verify --deep --strict` 通过，当前为本机 ad hoc 签名。
- 有效 Info.plist：`com.zyapps.StatPeek`、版本 0.1.0 / Build 1、Utilities 分类、StatPeek 显示名、版权信息及 AppIcon 均存在。
- `LSUIElement=true` 与 `ITSAppUsesNonExemptEncryption=false` 均为布尔类型。
- 已确认运行进程来自安装路径，只有一个实例，启动后无主窗口。
- 安装后重新打开浮层，四项勾选及默认颜色恢复，浮层可打开/关闭。
- 测试和构建目录内重复的可运行 `.app` 已移除，只保留固定名安装副本。
- 构建保持 Xcode 配置的 Derived Data，迁移工程后已重新解析并保存匹配的本机 MCP profile；本机配置不提交公开仓库。

## 适用范围

当前证据确认上述功能在本机工作。内存为注明的估算口径；GPU 依赖驱动字段，缺失时显示不可用。macOS 13 和 Intel 实机尚未单独验收。

未完成 Developer ID 签名、公证或 App Store 发布。GitHub 公开的是源码项目。
