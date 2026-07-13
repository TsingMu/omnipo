# disk-analysis Delta Specification

## ADDED Requirements

### Requirement: 持久化扫描授权失效时必须提供恢复状态

Disk Analysis MUST 区分用户从未授权扫描目录和已保存授权无法恢复。可刷新 stale bookmark 时必须安全刷新；无法解析或无法启动 security scope 时必须显示需要重新授权，而不是将结果报告为空目录、0 B 或首次未授权。

#### Scenario: stale bookmark 可以刷新

- **当** 已保存的大文件扫描目录 bookmark 已 stale
- **并且** 系统仍允许解析并访问该目录
- **那么** 应用刷新 bookmark 并继续只读元数据扫描
- **并且** 不要求用户重复选择目录

#### Scenario: 已保存授权无法恢复

- **当** 已保存 bookmark 损坏、目录移动或 security scope 无法启动
- **那么** 磁盘分析页显示需要重新授权
- **并且** 提供重新选择目录的操作
- **并且** 不把失败状态展示为 0 B、无大文件或从未授权
- **并且** 日志不包含 bookmark 数据或原始路径
