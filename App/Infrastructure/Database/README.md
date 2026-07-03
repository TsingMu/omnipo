# Database Infrastructure

Phase 0 不引入任何数据库实现。本目录预留给后续 change(如 Clipboard、WeChat Storage、Operation Log 持久化)的本地存储实现。

**约束**:任何引入的数据库必须满足:
- 完全本地存储,不上传任何数据
- 默认不得记录剪切板原文、用户文件名、聊天数据或隐私内容
- Clipboard 能力的数据层可在用户确认后本地保存剪切板原文;日志、调试输出、统计事件和其他能力仍不得记录剪切板原文
- 在 change 的 `design.md` 中说明选型与降级策略
