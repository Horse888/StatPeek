# 仪表盘细节调整 · 2026-10-26

## 范围与依据

用户提供 0.3.9 (14) 仪表盘截图并调用 make-interfaces-feel-better。已检查同一生产控制器的独立原生窗口：彩色卡片描边、进度条双重轮廓偏重；磁盘卡片进度与说明间距不均；历史卡片的内容缩进与指标卡片不一致，底部说明仅 9 点。

保留 288 点宽、单层玻璃面板、原生玻璃控件、语义颜色、全部文案、模块顺序、固定页脚及现有行为。仅调整表面、间距和文字，不新增动效、依赖或数据操作。

## 实施与验收

1. 卡片使用更淡的色底及中性细描边；进度条减轻轮廓，保留极端自选颜色的可辨性与无效值语义。
2. 收紧磁盘卡片空隙，统一历史内边距；历史主数值适度突出，底部文字提高到 10 点并容纳换行。
3. 沿用独立非激活窗口采集前后浅深色、四档高度与滚动位置；检查全部文字尺寸、历史范围、取消选择、不可用和空态、颜色 Popover 生命周期。仅调用进程内控件方法，不发送桌面输入。
4. 实际 App build 前分配递增编号；Release 测试通过后按项目 AGENTS 替换个人 Applications，验证身份、签名、哈希、唯一进程及数据保留，清理本次重复副本并提交推送。

参考：[Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Apple Typography](https://developer.apple.com/design/human-interface-guidelines/typography)。原生窗口使用合成数据，安装与真实数据保留另行记录。
