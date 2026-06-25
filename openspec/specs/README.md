# 当前规范目录

此目录保存已经实现并验收的能力规范。

## 已实现能力

- [`application-foundation`](application-foundation/spec.md) — 应用入口、桌面导航、依赖装配、Settings/Logging 横切服务与统一模型(AppError、TaskProgress、OperationLog)。Phase 0 完成于 2026-06-19。
- [`launcher`](launcher/spec.md) — 全局快捷键、独立浮动搜索面板、主窗口内嵌工作台、应用/Spotlight 文件/六命令搜索、查询代次与取消、隐私边界。完成于 2026-06-21(核心)+ 2026-06-24(主窗口工作台)。
- [`main-dashboard`](main-dashboard/spec.md) — 分组侧栏导航、启动磁盘状态卡(真实容量摘要)、快捷入口纯导航、外观适配、侧栏焦点反馈。完成于 2026-06-20(重设计)+ 2026-06-24(容量摘要升级)。
- [`disk-analysis`](disk-analysis/spec.md) — 启动卷只读容量概览、显式刷新、大文件列表(NSOpenPanel 授权 + security-scoped bookmark)、保守扫描边界(跳过 Library/Caches/node_modules 等)、未实现能力标注。完成于 2026-06-24。

## 计划中能力

后续 Clipboard、App Uninstaller、Permission Audit、WeChat Manager、System Monitor 与清理执行等仍遵循相同流程:

1. 在 `openspec/changes/<change-id>/` 下完成 `proposal.md`、`design.md`、`tasks.md` 和 `specs/<capability>/spec.md`。
2. 按 `tasks.md` 顺序实施,每完成一项把 `[ ]` 改为 `[x]`,并保持工程可编译。
3. 验收后把增量规范合并到本目录,并将 change 目录归档到 `openspec/changes/archive/`。

涉及删除、隐私权限、微信数据或 TCC 数据库的 change,设计文档必须单列风险、系统限制与降级策略。
