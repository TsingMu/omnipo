# clipboard Delta Specification

## ADDED Requirements

### Requirement: 剪贴板存储不可用时必须安全降级

Clipboard MUST 在其 Application Support 目录、SQLite 数据库、schema 或 payload 存储无法初始化时进入明确的不可用状态。该状态不得启动剪贴板监控，不得被展示为空历史，也不得阻止 Omnipo 其他 capability 启动。

#### Scenario: 启动时数据库无法打开

- **当** Clipboard 数据库在应用启动时无法打开或初始化
- **那么** Omnipo 主窗口和非 Clipboard 功能仍然可用
- **并且** Clipboard 页面显示本地存储不可用
- **并且** Clipboard 不开始读取或持久化新的剪贴板内容

#### Scenario: 在不可用状态执行剪贴板操作

- **当** 用户在 Clipboard 存储不可用时尝试读取、收藏、删除、复制或粘贴历史项目
- **那么** 操作返回稳定的 capability 不可用错误
- **并且** 应用不崩溃
- **并且** 应用不自动删除、覆盖或重建现有数据库

#### Scenario: 记录剪贴板初始化失败

- **当** Clipboard 初始化失败并写入本地日志
- **那么** 日志只包含稳定事件名、错误代码和脱敏上下文
- **并且** 不包含数据库路径、SQLite 原始消息、剪贴板内容或 payload 文件名
