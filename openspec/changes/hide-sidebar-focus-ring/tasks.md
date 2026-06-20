# Tasks：隐藏侧栏外层焦点描边

## 1. OpenSpec

- [x] 1.1 编写 proposal、design、tasks 和 main-dashboard 增量规范。

## 2. 实现

- [x] 2.1 隐藏侧栏滚动容器的系统焦点效果，同时保留可聚焦与方向键导航。

## 3. 验证

- [x] 3.1 验证侧栏焦点描边消失且键盘选择仍可用。验收证据：真实应用截图确认侧栏外围蓝色焦点框已消失；`focusable()`、`onMoveCommand` 和侧栏导航边界测试保持不变。
- [x] 3.2 执行完整构建与测试并记录验收证据。验收证据：Xcode Debug 全量测试结果为 `TEST SUCCEEDED`，项目脚本构建并启动真实应用成功。
