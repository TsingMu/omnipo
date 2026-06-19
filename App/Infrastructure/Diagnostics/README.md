# Diagnostics Infrastructure

Phase 0 不实现系统监控、采样或诊断。本目录预留给 System Monitor change 的性能指标采集实现。

**约束**:任何诊断实现必须满足:
- 默认完全本地,不上传任何指标
- 高频采样必须支持取消、节流和生命周期停止
- 不得记录可能与隐私关联的内容(如具体进程的窗口标题、URL)
