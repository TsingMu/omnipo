# FileSystem Infrastructure

Phase 0 不实现任何文件系统访问。本目录预留给 Cleaner、Uninstaller、Disk Usage 等 change 的文件系统实现。

**约束**:任何文件访问必须满足:
- 默认 App Sandbox,需要沙盒外访问时由对应 change 单独评估 entitlement
- 优先使用用户选择、Security-Scoped Bookmark 和公开系统 API
- 删除前必须确认,优先移动到废纸篓
- 高风险、共享容器、归属不明的文件默认不勾选
- "无法读取"不得误报为"未授权"或"无数据"
