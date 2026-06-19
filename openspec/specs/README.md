# 当前规范目录

此目录保存已经实现并验收的能力规范。

## 已实现能力

- [`application-foundation`](application-foundation/spec.md) — 应用入口、桌面导航、依赖装配、Settings/Logging 横切服务与统一模型(AppError、TaskProgress、OperationLog)。Phase 0 完成于 2026-06-19。

## 计划中能力

后续 Launcher、Clipboard、Dashboard、Disk Cleaner、App Uninstaller、Permission Audit、WeChat Manager 和 System Monitor 都遵循相同流程:

1. 在 `openspec/changes/<change-id>/` 下完成 `proposal.md`、`design.md`、`tasks.md` 和 `specs/<capability>/spec.md`。
2. 按 `tasks.md` 顺序实施,每完成一项把 `[ ]` 改为 `[x]`,并保持工程可编译。
3. 验收后把增量规范合并到本目录,并将 change 目录归档到 `openspec/changes/archive/`。

涉及删除、隐私权限、微信数据或 TCC 数据库的 change,设计文档必须单列风险、系统限制与降级策略。
