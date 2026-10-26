<p align="center"><img src="docs/assets/app-icon.png" width="112" alt="StatPeek app icon"></p>

# StatPeek · 状态一瞥

A compact macOS menu bar monitor. Selected metrics appear in two rows of colored D/C/M/G labels and live values. Click for a vertically scrolling dashboard with metric cards, progress, native color picking and disk history. No main window or Dock icon.

一个无主窗口的 macOS 状态栏小工具。选中的设备信息直接以两行系统等宽字体的「D/C/M/G 字母 + 数值」展示，点击打开可上下滚动的仪表盘，上方设置、下方磁盘历史，左下角固定显示版本。

![真实状态栏截图](docs/assets/statusbar.png)

## 功能

- 磁盘剩余空间、系统 CPU 使用率、内存使用率估算、GPU 使用率。
- 状态栏持续每 2 秒刷新；浮层打开时预览四项，关闭后只采样选中项。勾选仅决定状态栏显示。
- 四项全选时，上行为磁盘和 CPU，下行为内存和 GPU；紧凑留白和列间隔减少菜单栏占用，刷新时保持宽度稳定。
- 四项各有原生 NSBox 紧凑配色卡片，百分比只在进度条右侧显示；磁盘显示总容量、已用、剩余，进度代表已用比例。采样中或不可用不画虚假的零进度。
- 标题旁显示真实 App 图标；浮层宽 288 点、理想高度 766 点，高度自适应内容，仅屏幕可用高度不足时纵向滚动；勾选框在每项最前；未勾选降低强调程度，仍预览实时读数。页脚左侧版本与右侧开机启动、退出保持水平对齐。
- 装饰图标使用彩色填充 SF Symbol，不加背景，与标题居中对齐、间隔 4 点；GPU 使用 cube.fill 表达 3D 图形渲染。macOS 14+ 出现时播放一次原生 Bounce，读数刷新不重播；macOS 13 静态，未选中、隐藏或减少动态效果时停止。状态栏仍使用 D/C/M/G 字母。
- 主浮层采用无箭头的一体玻璃面板，状态栏按下立即切换，再按立即关闭；点击其他应用、切走应用或 Escape 可关闭，颜色选择器保留主面板。macOS 26+ 使用系统液态玻璃；颜色入口使用小尺寸原生颜色井，不添加自建按钮背景，退出按钮使用系统 glass 样式，历史范围使用系统自动外观的原生分段控件，旧系统使用原生磨砂材质。退出为 24 点高、红色纯文字；开机启动为无背景勾选项。
- 行尾小尺寸原生颜色井默认打开 macOS 原生颜色 Popover，主浮层保持显示，配色即时更新；系统“更多颜色”入口仍可用。关闭主浮层会同步结束颜色 Popover，重开后可继续选色；读数刷新不覆盖正在编辑的颜色；任意 RGB 配色重启后恢复，单项修改不影响其他项。
- 固定页脚右侧的「开机自动启动」使用 macOS 原生登录启动项；勾选后在当前用户登录时启动，取消即注销。默认关闭，需要系统批准或设置失败时明确提示。
- 磁盘保留一位小数，单位使用单字母，例如 `320.8G`。
- 后台每 5 分钟记录一次磁盘剩余空间，即使取消磁盘显示也继续记录；只保存本机，静默运行。
- 下方「磁盘记录」使用更紧凑的排版，剩余容量以青色突出；查看较上次增加或减少的一位小数 G 数，以及 24 小时、7 天和全部历史曲线；曲线平滑，线条从蓝渐变至紫。记录持续保留，重启沿用历史；休眠或退出期间不伪造采样。
- 全部取消时仍保留一个可点击图标，随时恢复显示项。
- 无第三方运行依赖，无网络请求，无 sudo 或常驻辅助进程。

## 构建与运行

需要 macOS 13+ 和支持 Swift 6 的 Xcode。本次验证环境为 Apple Silicon、Xcode 27.1。

1. 打开 `StatPeek.xcodeproj`。
2. 选择 `StatPeek` Scheme、`My Mac`。
3. 按 Run，在屏幕顶部状态栏查看指标。

项目提供本机 ad hoc 签名设置，便于源码构建。正式分发前应配置自己的签名及公证；公开仓库不等于已完成应用商店发布。

```sh
xcodebuild -project StatPeek.xcodeproj -scheme StatPeek -configuration Release -destination 'platform=macOS' test
xcodebuild -project StatPeek.xcodeproj -scheme StatPeek -configuration Release -destination 'platform=macOS' build
```

构建保持 Xcode 配置的 Derived Data 位置。用 `xcodebuild -showBuildSettings` 查看 `TARGET_BUILD_DIR`，将验证通过的 Release `.app` 安装到个人应用目录 `~/Applications/StatPeek.app`。每次更新均停止旧版、替换该固定副本并后台启动新版，核对唯一运行进程及版本后清理本次旧副本和构建重复 App；用户设置和磁盘历史保留。工程交付约定见 [AGENTS.md](AGENTS.md)。

项目已包含生成后的 Xcode 工程。只有修改 `project.yml` 时才需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```sh
xcodegen generate
```

## 应用信息

| 字段 | 内容 |
| --- | --- |
| Product / Target / Scheme | StatPeek |
| Bundle identifier | com.zyapps.StatPeek |
| Version / Build | 0.3.9 / 27 |
| Category | Utilities |
| Minimum macOS | 13.0 |
| App icon | 10 个标准 macOS AppIcon 资源尺寸 |
| Dock / Main window | 无 |

最初原型的 `local.StatPeek` 偏好会迁移到当前标识；已有新标识下的选择不会被覆盖。

## 指标口径

- **磁盘**：用户主目录所在卷的可用容量，十进制单位；APFS 共享容器可能与其他工具的口径不同。
- **CPU**：Mach 系统 ticks 的两次差值，总体为 0–100%，不是单个进程的百分比。
- **内存**：活跃页 + wired 页 + compressor 页 − purgeable 页，占物理内存的比例；明确标为估算，不声称与活动监视器完全一致。
- **GPU**：驱动提供的 `IOAccelerator / PerformanceStatistics / Device Utilization %`；多 GPU 取可读设备的最高值。字段缺失时浮层显示「不可用」，状态栏显示 `—`。该字段的跨驱动稳定性没有保证。

首次 CPU 采样需要建立基线，短暂显示 `…`。macOS 13 和 Intel 实机尚未单独验收。

规格与验收标准见 [SPEC.md](docs/SPEC.md)，验证记录见 [VALIDATION.md](docs/VALIDATION.md)，图标设计及生成提示见 [icon-design.md](docs/icon-design.md)。

## 不操作桌面输入的布局验证

```sh
python3 scripts/verify-layout.py --output work/verification/layout-new-run
```

脚本沿用 Xcode 配置的构建位置，创建不获取焦点、不接收鼠标事件的独立窗口，以临时偏好和临时数据库检查浅/深色、四档可用高度及顶部/中段/底部，并执行 1,000 次切换：交错 250 次失活、1,000 次重复动作与 1,000 次旧鼠标事件，检查每次切换及关闭后无延迟重开。NSEvent 仅作为进程内数据交给生产处理入口，不投递到系统事件队列；只截取自己的测试窗口，不操作鼠标或键盘。输出目录必须为新目录，截图使用合成数据。见 [状态栏点击验收记录](docs/status-toggle-acceptance.json)；早期结果见 [浮层开关验收记录](docs/presentation-acceptance.json) 和 [独立布局验收记录](docs/independent-layout-acceptance.json)。

颜色选择器的独立生命周期检查：

```sh
python3 scripts/verify-layout.py --color-picker --output work/verification/color-new-run
```

四项各运行选色关闭、取消关闭、重开选色三阶段。打开实际系统 Popover，通过系统颜色模型触发真实颜色回调；最后阶段交错失活再处理关闭动作，并重复派发同一点击，确认不会重开。不向桌面发送输入、不切换前台应用。当前证据见 [状态栏点击验收记录](docs/status-toggle-acceptance.json)，此前记录见 [颜色浮层验收记录](docs/color-lifecycle-acceptance.json)。

原生状态栏按钮的独立窗口回归：

```sh
python3 scripts/verify-layout.py --status-gesture --output work/verification/status-gesture-new-run
```

在自己的非激活测试窗口中驱动真正的 NSStatusBarButton 类，检查 500 次手势、每次只有一个动作、失活交错不闪回，以及动作没有当前事件或转发另一事件时的关闭意图。释放事件只进入本测试进程自己的队列，不进入系统输入队列；这不等同于物理点击用户桌面的状态栏。最新对比及验证边界见 [纯色点与关闭修复](docs/evidence/status-dot-20261026/comparison.html)。

分层 Esc 与外部关闭检查：

```sh
python3 scripts/verify-layout.py --layered-dismissal --output work/verification/escape-new-run
```

对四项分别验证主面板取消命令、颜色子窗口的 Esc 处理入口，以及外部点击处理入口：第一次 Esc 只收回颜色选择器，第二次关闭主浮层；外部关闭一次收回两层。12 个流程保存 20 个截图状态，并验证重开、保存与不抢焦点。测试直接调用生产处理入口，不发送物理键盘或桌面鼠标事件，见 [分层关闭验收记录](docs/layered-dismissal-acceptance.json)。
