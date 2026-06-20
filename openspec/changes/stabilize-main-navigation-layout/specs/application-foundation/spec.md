# application-foundation 增量规范

## MODIFIED Requirements

### Requirement：应用必须提供稳定的原生 macOS 主窗口

系统必须以 SwiftUI Scene 和 `NavigationSplitView` 管理可调整尺寸的主窗口。窗口必须依据当前实际内容布局建立标题栏安全边界；导航选择变化不得改变无关区域的空间位置，也不得在启动阶段执行敏感业务操作。

#### Scenario：切换主窗口目的地

- **当** 用户通过侧栏、Launcher 命令或恢复状态切换目的地
- **那么** 主窗口保留相同的侧栏与详情内容原点
- **并且** 选择变化不会造成导航整体跳动或详情顶部裁切
- **并且** 不触发其他功能的后台任务
