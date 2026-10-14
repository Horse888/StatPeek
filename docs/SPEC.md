# StatPeek · 状态一瞥

## 名称与范围

Stat 表示系统状态，Peek 表示点开看一眼。产品、主 Target、共享 Scheme 均使用 StatPeek。
当前任务完成原生 macOS 项目、本机界面验证、应用图标、Xcode 应用信息、Applications 安装，并推送到用户授权的 GitHub 公开仓库；商标核验与 App Store 上架另行处理。

应用信息：StatPeek，Bundle ID `com.zyapps.StatPeek`，版本 0.3.3 / Build 8，Utilities 分类，最低 macOS 13.0。原型 `local.StatPeek` 的选择与配色在新标识首次启动时迁移，已有新偏好不覆盖。

图标：深蓝底板、两排彩色状态指示，见 `icon-design.md`；AppIcon 资源包含 macOS 标准 16–1024 像素尺寸。

## 用户行为

- macOS 13 或更高版本；Swift + AppKit，兼容 Apple Silicon 和 Intel 的源码构建。
- 无主窗口、无 Dock 图标，仅一个菜单栏状态项。
- 已选指标直接显示在状态栏：上下两行，每行最多两项，每项为字母 D/C/M/G + 数值，使用等宽数字。四项顺序为磁盘、CPU、内存、GPU；一项时垂直居中。
- 用户最新要求用 D（磁盘）、C（CPU）、M（内存）、G（GPU）替代状态栏小图标，保留两行紧凑布局。
- 点击状态项打开 380 点宽、620 点高的原生 NSPopover。中央纵向滚动，上方四项设置及启动设置，下方磁盘历史；标题和左下版本/右下退出固定。
- 默认全部选中；勾选保存至本机 UserDefaults，重启恢复。操作即时改变状态栏，浮层保持打开。
- 行尾 14 点淡色小圆点（28 点点击区）打开真实 NSColorPanel；选择任意 sRGB 色值立即应用并按规范化 #RRGGBB 保存。旧六种颜色字符串仍可读取，neutral 保持语义文字色；无效偏好回退本项默认，开关不清除配色。默认磁盘蓝、CPU 橙、内存紫、GPU 绿。
- 全部取消时状态栏保留一个可点击图标，浮层可恢复任意选项。
- 状态栏持续每 2 秒更新，浮层打开或关闭都继续刷新，浮层打开时采样四项用于卡片预览，关闭后仅采样所选指标。CPU 需要两次采样，首次显示「采样中…」，紧凑状态栏显示「…」。
- 不读取失败时伪造零值；采集失败显示「不可用」。
- 浮层提供「退出 StatPeek」，点击外部关闭浮层。选色器作为系统面板独立存在，浮层关闭后仍可为当前目标保存；初始化与切换目标不触发配色写入。

## 0.3.0 可滚动仪表盘

- 统一滚动文档按磁盘/CPU/内存/GPU 卡片、开机自动启动、磁盘记录排列；刷新仅更新既有视图，保持滚动位置。旧页签与六段色条移除。
- 四项各有独立淡色背景、实时读数、进度与说明。CPU、内存、GPU 只有有效 0–100% 才绘制进度；采样中、驱动不可用或无效值显示真实状态，不伪造零进度。
- 磁盘使用用户主目录所在卷的同一容量快照：总量来自 volumeTotalCapacity，剩余来自 volumeAvailableCapacity，已用=总量−剩余；进度为已用/总量。总量≤0、剩余<0或>总量时容量卡片不可用。历史记录独立沿用仅要求有效剩余量/卷标识的原条件，缺少总量不停止真实历史。
- 浮层打开时四项均可预览，勾选仅决定状态栏显示；关闭后只采样选中项。CPU 从停止采样恢复时重建间隔基准。2 秒刷新、独立 5 分钟记录、SQLite 全量数据与真实启动项状态保留。
- 版本从 Bundle 读取并固定在左下角；应用为 0.3.0 (5)。浅/深模式使用系统语义文字与淡色背景。
- 实施和验收计划见 ../design-plans/scrolling-dashboard.md；真实测试与设备证据见 VALIDATION.md。下方 0.1.1/0.2.0 记录历史设计，已由本节的新布局/选色行为替代。

## 0.1.1 紧凑布局与登录启动

- 缩小状态栏左右留白至 2 点、图标和数值间隔至 2 点、列间隔至 3 点；按每列文字宽度排布，不再使用固定 75 点列宽。百分比预留 `100.0%`，磁盘预留各单位的一位小数最大宽度，避免正常刷新时宽度跳动或满负载读数被截断。
- 设置浮层增加「开机自动启动」复选框。使用 macOS 13+ `SMAppService.mainApp`，实际在当前用户登录时启动，不创建额外辅助进程。
- 默认不主动注册。复选框读取系统真实状态；取消则注销。需要用户批准时显示半选及系统设置入口；失败显示原因并重新读取状态，不保存虚假的本地开关。
- 实施顺序：布局与启动项控制器 → 单元测试/Release → 临时副本界面验证 → 固定安装路径上的启动项注册、取消和应用重启验证 → 更新文档、提交并推送 GitHub。
- 验收：四项宽度较当前辅助功能测得的 162 点明显缩小；全部 16 种选择无遗漏、读数不越界；浮层持续刷新、开关不关闭浮层；启动项注册与注销均在应用重启后保持，并恢复测试前的用户设置。
- 不为测试注销当前用户或重启电脑；系统注册和应用重启的证据与实际开机验收分开记录。

## 0.2.0 磁盘历史与界面检查

- 后台每 5 分钟独立采集当前用户目录所在卷的剩余字节数，即使状态栏取消磁盘项也继续记录。首次启动立即建立真实基准。
- 用户已明确：仅记录，打开浮层时查看，不主动弹出提示。浮层增加「设置 / 磁盘记录」页签；记录页显示最近剩余量、相较上次增加或减少的一位小数 G 数及真实历史曲线。
- 全部记录持续保存在本机 Application Support 的 SQLite 数据库，不自动删除，不上传网络；时间、卷标识、原始字节数均保存。重启沿用上次记录与下次到期时间。
- 未运行/休眠期间不伪造记录；重启或唤醒时若已到期，补采一条当下真实值。比较文字使用真实上次记录时间，不声称间隔总是恰好五分钟。
- 换卷或时钟回退时建立新比较基准；读取/写入失败明确提示，保留历史，不将失败保存为零。差值不足可显示精度时提示变化小于 0.1G，不显示虚假的正负 0.0G。
- 曲线提供 24 小时、7 天和全部范围。采用保持单调性的平滑三次插值，线条从蓝经靛蓝渐变至紫；渐变与整个绘图区对齐，真实采样点保留。全量数据保留；绘图可以保留端点及局部极值进行降采样，避免多年数据绘图卡顿。只有一条记录时显示真实单点及等待提示，无虚构趋势。
- 保留现有两行状态栏、配色、勾选和开机启动项。状态栏全部指标采用字母 D/C/M/G，避免小 SF Symbol 难以辨认。
- 颜色选择改为连续长胶囊，均分六种颜色；根据最新要求，选中段中央显示直径 18 点的小圆玻璃标记（macOS 26+ 原生 NSGlassEffectView），圆内附加勾号；保持六段长色条，无大型胶囊选中按钮。较旧系统使用高光兼容样式，保留键盘焦点、颜色名称与选择状态的辅助功能。
- UI 范围：页签与记录页、设置浮层底色的可读性、六段胶囊配色；状态栏维持 107 点目标。先完成持久化和虚拟时钟测试，再构建、实际界面/重启验证，更新 Applications 与现有授权的 GitHub 交付。
- 验收证据分别记录自动五分钟边界测试、SQLite 持久化、真实 UI、安装与远端提交；未实际观察的自然五分钟定时采样不冒称已观察。

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

- [x] 启动后无主窗口与 Dock 图标，菜单栏恰好一个状态项，显示两行字母/数值。
- [x] 单击打开浮层；浮层持续打开 6 秒以上，状态栏及浮层数值仍刷新，关闭浮层后状态栏继续刷新。
- [x] 四个信息项均可直接勾选/取消；状态栏立即体现选择，浮层不关闭。
- [x] 更改颜色立即生效，退出再启动，选择及颜色保持；全取消仍能打开配置并退出。
- [ ] CPU、内存、磁盘与系统数据大致对照，遵循本文口径。
- [x] GPU 支持时显示读数，不支持时有明确提示。
- [x] 单元测试与 Release 构建通过，有效 plist 的 LSUIElement、加密声明为布尔类型。
- [x] Applications 中的最终 Release 启动成功，验证进程路径，移除测试/构建目录中的重复可运行应用。
- [x] 紧凑布局四项实际宽度 107 点，较原 162 点减少约 34%；正常刷新宽度稳定，最坏读数自动检查无越界。
- [x] 0.1.1 开机启动注册/取消均经应用重启验证；本次保留用户后来开启的当前设置。
- [x] 正式五分钟周期连续写入真实记录，记录页显示差值及曲线；重启保存且未提前重复采样。
- [x] 0.2.0 历史六段长胶囊及中央小圆玻璃曾检查实际界面；0.3.0 已替换为系统颜色面板入口。

自动测试、编译不等于菜单交互及读数的人工验收；在 VALIDATION.md 分开记录。

## 参考

- [Apple NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [Apple RunLoop.Mode.common](https://developer.apple.com/documentation/foundation/runloop/mode/common)
- [Apple LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [Apple NSPopover](https://developer.apple.com/documentation/appkit/nspopover)

- [Apple SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)

- [Apple 平滑单调插值](https://developer.apple.com/documentation/charts/interpolationmethod/monotone)
- [Apple 图表渐变对齐](https://developer.apple.com/documentation/charts/chartcontent/alignsmarkstyleswithplotarea%28_%3A%29)

## 0.3.1 紧凑卡片

- CPU/内存/GPU 百分比仅在进度条右侧显示，磁盘标题行保留剩余容量；不可用/采样中状态仍在读数位置明确显示。
- 磁盘卡片从 126 点缩为 108 点，其他指标从 92 点缩为 80 点，间隔从 10 点缩为 6 点。
- 开机自动启动卡片移到磁盘历史下方、滚动内容最末，固定版本与退出页脚保留。
- 浮层磁盘/CPU/内存/GPU 使用 internaldrive/cpu/memorychip/cpu.fill，磁盘记录使用 chart.xyaxis.line，启动设置使用 power。指标符号跟随用户配色，启动图标已启用时呈绿色；符号不增加重复辅助功能信息，也不截获点击。
- 可见模块使用轻微呼吸动画：macOS 14+ 原生 PulseSymbolEffect，macOS 13 透明度动画。关闭浮层、滚出可见区域或系统开启减少动态效果时停止。状态栏保留 D/C/M/G。
- 用既有仪表盘/历史测试与真实上下滚动验证，安装并同步 GitHub。

动画 API：[Apple PulseSymbolEffect](https://developer.apple.com/documentation/symbols/pulsesymboleffect)。

## 0.3.2 原生分层呼吸与 GPU 图标

- 四项继续使用系统 SF Symbol，GPU 改为 square.3.layers.3d，用三层立体图形表达图形渲染；这是产品语义选择，不宣称为 Apple 专用 GPU 符号。Apple 目录未提供名为 gpu 或 graphicscard 的符号。
- macOS 15+ 可见图标使用 BreatheSymbolEffect.plain.byLayer，按系统原生运动图层平滑缩放，速度 0.65；不额外叠加透明度、弹跳或旋转。GPU 符号具有三组原生运动图层，其余三项具有一组。
- macOS 13/14 保持静态；移除 Core Animation 兼容动画。系统开启减少动态效果、关闭浮层或滚出可见区域时停止；指标自选配色、紧凑卡片和状态栏字母保留。
- 验收原生动画实际帧变化、四项图标清晰度、滚动/关闭/重新打开、勾选和重启保存；保留原偏好与真实历史，再安装和推送。
- 系统颜色面板打开或切换目标时，设置浮层保持显示，数值和配色实时刷新；关闭颜色面板仍可继续操作设置。浮层使用 semi-transient，切到其他应用时主动关闭；状态栏再次点击与 Escape 仍可关闭。

依据：[Apple BreatheSymbolEffect](https://developer.apple.com/documentation/symbols/breathesymboleffect)、[Apple SF Symbols 动画](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)。系统版本门槛以本机 SDK 的 macOS 15.0 声明为准，图层依据 Apple SF Symbols 导出模板核验。

## 0.3.3 窄高玻璃浮层与就地选色

- 浮层宽 288 点，比 380 点减少 24.2%；高度按实际内容自适应（当前内容约 870 点）。以状态栏所在屏幕的可用高度减去 32 点作为上限，仅放不下时启用纵向滚动；卡片宽 260 点，固定标题和页脚始终可见。
- 勾选框位于最前，后接无背景的彩色装饰图标、名称和圆形玻璃选色入口。未勾选时图标/读数/进度/卡片呈灰色，保存的颜色不变，预览仍更新。
- 四项使用填充版 internaldrive.fill/cpu.fill/memorychip.fill/cube.fill。GPU 的立方体表达 3D 图形渲染，是应用语义选择，不宣称为 Apple 专用 GPU 图标。
- 可见时只播放一次原生 Bounce.byLayer（macOS 14+），不在每次读数刷新时重播；未选中/隐藏/减少动态效果立即停止。macOS 13 静态，无自制替代动画。
- 颜色入口为 minimal NSColorWell，点击默认打开系统颜色 Popover；每个控件按自己的指标保存 RGB，开启连续更新，普通读数刷新不覆盖正在编辑的颜色。保留系统主动“更多颜色”入口。
- 主浮层、圆形颜色入口、历史范围胶囊和退出胶囊使用 macOS 26+ 原生 NSGlassEffectView；较旧系统使用原生磨砂材质。各玻璃视图保留滚动裁切层级，不跨滚动边界合并提升；无自制模糊/玻璃动画。
- 页脚左侧版本、右侧裸开机启动勾选项与 24 点高的退出胶囊中心对齐；开机启动没有背景，退出仅为警告红色“退出”文字，无图标。状态/错误用 tooltip/辅助功能帮助，等待批准或失败显示橙色，右键保留系统登录项入口。
- 历史内容从 420 点缩至 304 点：剩余容量为 20 点青色，变化文案 11 点，时间 10 点；绘图区宽 228 点，时间、计划和说明允许换行。24 小时/7 天/全部使用三个独立胶囊玻璃按钮，平滑渐变线与真实历史保持。
- 验收原生 Popover 和主浮层共存、颜色目标隔离、灰色静态与颜色恢复、范围按钮和重启保存，保留原数据后安装、推送。用户要求不控制鼠标/键盘后，后续只进行隔离自动测试、源码及安装检查；最终无背景图标版本不操作桌面输入，出现动画及最终视觉待用户自然使用确认。

依据：[Apple NSColorWell.Style.minimal](https://developer.apple.com/documentation/appkit/nscolorwell/style/minimal)、[Apple BounceSymbolEffect](https://developer.apple.com/documentation/symbols/bouncesymboleffect)、[Apple NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)。

## 0.3.4 独立窗口排版验证

- 指标图标与标题共用中心线，间隔 4 点；指标符号字号 14，历史标题间距也为 4 点。保留无背景装饰图标及可点击控件玻璃外观。
- 显式设置滚动区高度，仅宽度自动调整；避免玻璃内容层在窗口挂载后再调整尺寸时，滚动区重复应用高度变化。标题和页脚仍固定。
- 使用独立测试窗口检查浅/深色、1378/736/568/448 点可用高度与短屏顶部/中段/底部；窗口不成为 key/main，测试进程不替代用户前台应用，不发送鼠标或键盘事件。
- 自动检查文字容纳尺寸、同层标签不重叠、刷新不改变滚动位置、最大滚动能抵达末尾；既有采样、偏好、记录与登录项逻辑保持。测试截图明确为合成数据。

## 0.3.5 稳定开关与无箭头浮层

- 用户允许统一背景无法稳定衔接时去掉箭头。本次使用无箭头 borderless NSPanel，保留单层原生玻璃、原布局和自适应高度。试验过 NSPopover.hasFullSizeContent；它会改变内容安全区域，采用用户允许的无箭头方案避免引入布局偏移。
- 状态栏只在 leftMouseDown 派发动作，由同一个展示控制器同步切换可见性；关闭使用 orderOut，window animationBehavior 为 none，无退出淡出。
- 状态栏区域的鼠标按下和相关失活事件不先行当作外部关闭；普通外部点击和应用失活关闭，Escape 经 responder cancelOperation 关闭。应用内颜色窗口的点击保持父面板。
- 面板位置跟随实际状态栏锚点，约束在当前屏幕可用区域；取消选择 CPU 时关闭后恢复采样基准。显隐过程中不更改指标选择、配色、登录项或磁盘记录。关闭时停掉图标动画并收回颜色窗口；监听器不重复累积。
- 独立窗口按生产展示路径运行，关闭桌面输入监听和激活，直接调用自己的事件路由；验证 200 次开关、20 个浅深/高度/滚动状态，并检查偶数次点击后保持关闭。保留事件回放与物理桌面事件的证据边界。

参考：[Apple NSPopover 行为](https://developer.apple.com/documentation/appkit/nspopover)、[hasFullSizeContent 与安全区域](https://developer.apple.com/documentation/appkit/nspopover/hasfullsizecontent)、[NSWindow.animationBehavior](https://developer.apple.com/documentation/appkit/nswindow/animationbehavior-swift.property)。

## 0.3.6 颜色 Popover 联动生命周期

- 打开系统颜色 Popover 时主浮层保持可见；从状态栏关闭主浮层时，子 Popover 的显示状态与窗口都必须同步结束；重开后同一颜色控件可再次选色。
- 通过子窗口内容的公开 nextResponder 链找到 NSPopover，先关闭其动画并调用 close，待 isShown=false 后恢复原动画设置；随后取消颜色井激活并隐藏父面板。避免只隐藏窗口或在关闭动画结束前隐藏父面板导致内部状态残留。
- 四个指标分别验证选色、取消、重开选色三阶段，颜色变化必须经 AppKit 的真实颜色面板→激活颜色井通路进入现有保存回调；其他指标不变，重建选择对象仍读到保存值。
- 独立工具使用隔离偏好和合成读数，不发送桌面输入、不激活应用；采用公开控件方法和系统颜色模型，截图只包含自己的窗口。

## 0.3.7 分层 Escape 与外部关闭

- 颜色 Popover 显示时，Escape 的 cancelOperation 先收回颜色选择器并取消颜色井激活，主浮层和其监听器继续保留；再次 Escape 才关闭主浮层。没有颜色选择器时，一次 Escape 关闭主浮层。
- 颜色子窗口的原生取消命令在独立回放中可能只隐藏 NSWindow，保留 Popover.isShown 与激活颜色井。通过本应用的 local keyDown monitor，在系统解释 Escape 前将属于主浮层/子窗口/高级颜色面板的命令交给同一取消路由；其他窗口保持自身处理。主浮层关闭时移除该监听器。
- 外部点击、状态栏切换关闭及应用失活仍一次收回主浮层与颜色选择器。关闭不撤销已连续保存的颜色，不产生额外颜色修改；重新打开仍可选色并持久化。
- 先用真实原生颜色控件添加失败回归，再修复取消路由；独立窗口逐项覆盖两次 Escape、外部关闭、重开选色及延迟状态检查。测试直接调用 responder 命令与事件处理入口，不发送键盘/鼠标事件、不激活应用、不使用正式偏好和磁盘库。
