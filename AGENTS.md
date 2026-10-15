# StatPeek 本机交付约定

按用户 2026-10-15 的要求，后续本工程每次更新并验证通过后：

1. 使用 Xcode 配置的 Derived Data 构建 Release。
2. 保留用户设置及磁盘历史，停止旧版，替换 `~/Applications/StatPeek.app`，再后台启动新版。用户已授权这套替换和启动流程。
3. 核对版本、签名、构建与安装可执行文件哈希，以及唯一运行进程来自个人 Applications；确认成功后移除本次暂存、旧 App 和构建重复 App。正式保留一个固定名称的安装副本。

`/Applications/StatPeek.app` 是旧安装位置；迁移成功后移除该旧副本，后续使用个人 Applications。自动化验证继续使用独立测试窗口，不操作用户鼠标或键盘。
