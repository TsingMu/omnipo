# Omnipo

Omnipo 是一款本地优先、透明可控、安全保守的原生 macOS 管家应用。它将快捷启动、剪贴板管理、磁盘分析、应用卸载、隐私权限审计、微信空间分析和系统监控集中在一个 SwiftUI 桌面应用中。

> 当前项目主要面向单台 Mac 本地使用。稳定能力以最新 Git tag 和 `openspec/specs/` 为准；`main` 可能包含仍在验收中的 OpenSpec change。

## 功能概览

| 模块 | 当前能力 | 安全边界 |
| --- | --- | --- |
| 总览 | 汇总系统状态和常用功能入口 | 不因页面导航自动启动高成本扫描 |
| 聚焦搜索 | 全局快捷键、应用与文件搜索、内置命令 | 不监听全部键盘输入，不记录查询或文件路径 |
| 剪贴板 | 本地历史、搜索、类型筛选、收藏、删除、复制与浮动面板 | 首次确认后才记录；无辅助功能权限时自动粘贴降级为仅复制 |
| 磁盘分析 | 卷容量概览、授权目录大文件扫描、筛选排序、会话内候选复核、Finder 定位 | 只读取文件系统元数据，不读取内容，不执行通用清理 |
| 应用卸载 | 应用发现、关联文件分析、风险分级、确认后移入废纸篓 | 不永久删除；归属不明确或高风险文件默认不选中 |
| 权限审计 | 本机应用隐私授权状态的只读查看与筛选 | 不修改 TCC；无法读取时明确降级 |
| 微信管理 | 本地微信空间分类、大文件和匿名会话占用分析 | 不读取聊天内容，不删除、移动或修改微信数据 |
| 系统监控 | CPU、内存、磁盘、网络、电池和应用资源用量 | 使用公开系统 API，不为监控申请额外隐私权限 |

## 设计原则

- **本地优先**：当前基线不包含云同步、远程服务、自动更新或遥测。
- **最小权限**：只在具体功能需要时请求目录、辅助功能、完全磁盘访问或 Finder 自动化权限。
- **保守降级**：权限不足、授权失效或数据不可读时显示真实原因，不伪装成空数据。
- **删除可恢复**：应用卸载优先移动到系统废纸篓，不提供应用内部永久删除。
- **隐私日志**：不记录剪贴板内容、用户路径、文件名、微信数据或 bookmark 数据。

## 系统要求

- macOS 14 或更高版本
- 支持 Swift 6 的 Xcode
- 当前工程为单一 macOS App Target，无第三方运行时依赖

## 快速开始

克隆项目并进入目录：

```bash
git clone https://github.com/TsingMu/omnipo.git
cd omnipo
```

使用项目统一脚本构建并启动 Debug 版本：

```bash
./script/build_and_run.sh run
```

常用命令：

| 命令 | 用途 |
| --- | --- |
| `./script/build_and_run.sh build` | 仅构建 Debug 应用 |
| `./script/build_and_run.sh run` | 停止旧进程、构建并启动 |
| `./script/build_and_run.sh debug` | 构建后以前台调试方式启动 |
| `./script/build_and_run.sh test` | 运行全量 XCTest |
| `./script/build_and_run.sh verify` | 执行 Debug 构建和全量 XCTest |
| `./script/build_and_run.sh logs` | 实时查看 Omnipo 日志 |
| `./script/build_and_run.sh telemetry` | 查看最近的本地诊断日志 |
| `./script/build_and_run.sh stop` | 停止正在运行的 Omnipo |

也可以直接在 Xcode 中打开 `Omnipo.xcodeproj`，选择 `Omnipo` scheme 和 `My Mac` 运行。

## 构建 Release 版本

```bash
xcodebuild \
  -project Omnipo.xcodeproj \
  -scheme Omnipo \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  build
```

构建产物位于：

```text
build/DerivedData/Build/Products/Release/Omnipo.app
```

仅在本机使用时，可以在 Finder 中将该应用复制到 `/Applications`。当前项目未配置 Developer ID 发布签名、公证、安装包或自动更新流程。

## 权限说明

| 权限或授权 | 使用场景 | 未授权时的行为 |
| --- | --- | --- |
| 用户选择的目录 | 文件搜索、磁盘分析、微信空间分析 | 仅跳过未授权范围并提示选择或重新授权 |
| 辅助功能 | 剪贴板自动粘贴 | 内容仍会复制到剪贴板，但不会发送模拟粘贴事件 |
| 完全磁盘访问 | 权限审计读取 TCC 状态；部分卸载关联文件分析 | 显示不可读取或结果受限，不绕过系统权限 |
| Finder 自动化 | 将 `/Applications` 中的应用等项目移入废纸篓 | 逐项报告权限不足，不自动永久删除 |

目录授权使用 macOS security-scoped bookmark 保存。目录被移动、权限被撤销或 bookmark 失效后，需要用户重新选择目录。

项目曾使用 `com.omnipo.app` 开发标识，现已改为 `com.qing.omnipo`。macOS 会将新标识视为另一个应用；旧标识下的系统授权、`UserDefaults` 和剪贴板存储不会自动迁移，需要重新配置或授权。

## 已知限制

- 不提供通用磁盘删除或自动清理。
- 应用卸载尚无拖拽导入入口。
- 大文件工作台只覆盖当前授权目录中数量受限的结果；选择和忽略状态只保留在当前会话。
- 微信空间管理保持只读，不删除或修改微信数据。
- 用户启动的有限扫描不保证在应用退出后继续运行。
- 当前不包含 Developer ID 签名、公证、安装包、云端 CI、崩溃上报或遥测。

## 项目结构

```text
App/
├── Application/       # 应用入口、依赖装配、导航和应用级状态
├── UI/                # 各功能 SwiftUI/AppKit 界面
├── Services/          # 业务能力协议
├── Models/            # 跨层值模型、错误和结果类型
├── Infrastructure/    # 文件系统、数据库、权限和系统 API 实现
├── Shared/            # 跨功能轻量组件与工具
└── Resources/         # Assets 与 entitlements

Tests/OmnipoTests/     # XCTest 测试
openspec/specs/        # 已验收的主规格
openspec/changes/      # 活动 change 与历史归档
script/                # 构建、测试和运行入口
```

应用以服务协议隔离 UI 与系统实现，使用 Swift Concurrency、Actor 和可取消任务管理扫描、监控及其他异步工作。

## OpenSpec 开发流程

项目一次只推进一个 change：

1. 在 `openspec/changes/<change-name>/` 创建 `proposal.md`、`design.md`、`tasks.md` 和 delta spec。
2. 先审阅需求、非目标、风险和降级策略，再开始实现。
3. 按任务顺序开发，并执行与风险相称的测试。
4. 运行严格校验：

   ```bash
   openspec validate --all --strict
   ```

5. 人工验收通过后，将 delta spec 合并到 `openspec/specs/` 并归档 change。

更完整的工程约定见 [`openspec/project.md`](openspec/project.md)，已验收能力索引见 [`openspec/specs/README.md`](openspec/specs/README.md)。

## 当前发布状态

- 已验收稳定基线：`v0.2.0`
- 最低部署目标：macOS 14
- Bundle ID：`com.qing.omnipo`
- 发布方式：本机 Release 构建和本地安装

仓库当前未提供 `LICENSE` 文件，因此不要默认其代码已按某种开源许可证授权。
