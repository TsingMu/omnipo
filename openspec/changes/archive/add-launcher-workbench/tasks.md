# Tasks：add-launcher-workbench

## 1. OpenSpec 文档

- [x] 1.1 编写 `proposal.md`，明确主窗口快速启动页升级为正式 Launcher 工作台。
- [x] 1.2 编写 `design.md`，定义共享内容组件、状态复用与执行边界。
- [x] 1.3 编写 `tasks.md`，拆分文档、实现、测试和验收任务。
- [x] 1.4 编写 `specs/launcher/spec.md` 增量规范，定义主窗口 Launcher 工作台要求。

## 2. 共享 Launcher 内容视图

- [x] 2.1 将现有 Launcher 面板内容改造成可复用的共享工作台视图。
- [x] 2.2 区分浮动面板样式与主窗口内嵌样式，避免主窗口被固定尺寸锁死。
- [x] 2.3 保持搜索框、结果列表、部分失败和瞬态错误提示行为一致。

## 3. 主窗口快速启动页

- [x] 3.1 将 `LauncherView` 从占位页改为正式工作台页面。
- [x] 3.2 页面首次出现时展示空查询默认命令，不再显示 Phase 0 占位说明。
- [x] 3.3 页面提供轻量说明与打开浮动面板入口，但主内容以内嵌工作台为主。

## 4. 结果执行与交互

- [x] 4.1 复用现有 `LauncherResultExecutor` 执行主窗口页中的结果。
- [x] 4.2 主窗口页执行成功后不关闭页面，失败时仍通过安全错误提示反馈。
- [x] 4.3 保持快捷入口与搜索结果执行不触发额外扫描、删除或高权限行为。

## 5. 测试

- [x] 5.1 为 Launcher 工作台展示模型或状态补充单元测试。
- [x] 5.2 运行 `xcodebuild -project Omnipo.xcodeproj -scheme Omnipo -configuration Debug -derivedDataPath /tmp/omnipo-launcher-workbench -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`。

## 6. 人工验收

- [x] 6.1 打开“快速启动”页并确认不再显示 Phase 0 占位文案。
- [x] 6.2 确认空查询下可见六个功能命令。
- [x] 6.3 确认查询应用、文件与命令均可返回结果。
- [x] 6.4 确认点击或回车执行结果行为正确，且无额外权限弹窗。
