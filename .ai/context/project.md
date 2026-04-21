# GameMaker 项目上下文

## 项目目标

GameMaker 是一个 AI Native 游戏创作平台。用户通过自然语言描述游戏需求，系统完成需求理解、规格生成、工具调用、资源生成、验证修复和多平台导出。

核心流程：

`用户描述 -> AI 理解需求 -> 生成游戏规格 -> 调用工具构建场景/脚本 -> AI 生成资源 -> 验证修复 -> 多平台导出`

## 领域划分与知识隔离

本仓库包含三个**知识隔离**的领域，工作在一个领域时不需要加载另一个领域的上下文：

| 领域 | 目录 | 简述 |
|------|------|------|
| **创作平台** | Frontend/ Backend/ MCP/ Engine/ Tools/ Editor/ | AI 驱动的游戏创作全链路 |
| **容器游戏制作** | Engine/ + Backend 容器管理 | Godot 容器内的游戏构建与导出 |
| **游戏服务器** | GameServer/ | 独立部署的实时游戏服务器框架（多进程、TCP/KCP、Protobuf） |

**隔离原则：**
- 创作平台与游戏服务器之间**没有运行时调用关系**，代码完全独立
- GameServer 有独立的 go.mod、独立的技术栈和架构模式，不共享 Backend 的 model/repository/service
- 在 GameServer 工作时，不需要加载 Backend 宪法、生命周期文档、MCP/Engine 规则
- 在创作平台工作时，不需要加载 GameServer 的 Actor/FSM/Protobuf 文档

## 技术栈

### 创作平台
- Frontend: Next.js 14 + React 18 + Tailwind CSS
- Backend: Go + Gin + Zap
- MCP: TypeScript + Express + Zod + Winston
- Engine: Godot 4.x + GDScript
- Tools: Python
- Infra: MongoDB, Redis Streams, Docker, Milvus

### 游戏服务器（GameServer/）
- 语言: Go
- 架构: 微服务（Account/Gate/Lobby/Match/Room/Team/DB Server）
- 并发模型: Actor 模式
- 通信: Protobuf + TCP
- 游戏运行时: Entity-Component + Player FSM
- 开发规范: `GameServer/CLAUDE.md`（通用入口）

## 关键目录

### 创作平台
- `Backend/`: Go 后端服务（Gin + REST API）
- `Frontend/`: Web 前端（Next.js）
- `MCP/`: MCP Server 与 Godot 桥接（TypeScript）
- `Engine/`: 引擎相关代码与容器编排（Godot 4）
- `Tools/`: Python 工具服务和素材处理管线
- `Editor/`: Tauri 桌面客户端

### 游戏服务器
- `GameServer/`: 独立部署，含 account/gate/lobby/match/room/team/db 多个子服务

### 共享
- `Docs/`: 架构、版本、研发过程文档
- `Scripts/`: 环境启动、部署、验证脚本
- `.claude/`: Claude Code 的 commands、skills、plans、scripts、logs
- `.ai/`: Claude 与 Codex 共享上下文

## Claude 目录的语义

`.claude/` 不是项目事实源，而是 Claude Code 的运行时扩展层。里面沉淀了三类高价值资产：

- commands: 工作流定义，例如 `manual-work`、`auto-work`、`feature plan`、`research`
- skills: Claude skill 说明与参考资料
- scripts/plans/logs: 自动化执行脚本、计划模板、运行日志

Codex 需要理解这些内容，但不必把它们视为自己的原生命令系统。对 Codex 来说，它们是可复用的工作流文档和经验资产。

> **Backend 详细约束**（Session 生命周期、Shutdown、容器清理、路由注入等）→ `.ai/context/backend-lifecycle.md`
> **CLI 调用 Trace**（auto-work JSONL trace 落盘、stage 标注、trace_view 用法）→ `.claude/guides/cli-trace.md`

## 项目事实锚点（宪法引用）

以下小节被 `.ai/constitution/*.md` 显式引用，修改或删除前须同步更新引用方。

### 认证与授权模型现状（无 RBAC）

当前 Backend 的认证仅包含 JWT 令牌校验，`Claims` 结构体只有 `UserID` + `Email`（`Backend/internal/router/middleware.go`）。**不存在** `Role` 字段、`RequireAdmin` 中间件、admin 路由组或任何 RBAC 基础设施。`User` 模型（`Backend/internal/model/user.go`）同样无 `role` 字段。Plan 若需要 admin-only 端点，必须先作为前置任务补齐 RBAC 三件套，或改用 owner-only 受保护端点设计。

### Game 领域模型边界（权威 REST 模型 vs 内部业务模块）

仓库中存在两套 `Game` 实现：
- **权威 REST 链路**：`internal/model.Game` + `internal/repository.GameRepository` — 对外 REST `/api/v1/games/*` 的唯一数据源。Handler 读取的字段必须位于此模型。
- **内部业务模块**：`internal/game.Game` + `game.GameRepository` — 仅供 session 内部业务和 ExportHandler 使用，不对外暴露。

Plan 涉及 `Game` 字段新增、索引变更、repo 扩展时，必须显式声明落点且只指向一套。跨两套模型的设计视为 Critical。

### 容器平台导出能力边界

Linux Godot 容器仅支持 Android / HTML5 / 资源导入与验证。完整 iOS 导出必须走 macOS + Xcode 流水线，不得在 Linux 容器方案里承诺 iOS 可导出。缺 macOS runner 时明确标记为"未验收"，而非"通过"。

## 共享协作原则

- 项目事实、架构认知、工程约束统一放在 `.ai/`
- Claude 专用命令和 skill 保留在 `.claude/`
- 如果要新增一个同时影响多个 agent 的规则，优先写入 `.ai/`
- 如果只影响 Claude 的运行方式，再写入 `.claude/`
