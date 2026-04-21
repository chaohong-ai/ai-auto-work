# GameMaker 共享开发宪法（核心原则）

Version: 1.4
Scope: Claude Code / Codex / 其他在本仓库工作的 AI agent

本文件是项目级最高规则。任何 agent 的本地偏好、命令系统或自动化流程，都不得违反这里的约束。

> **领域隔离声明：** 本仓库包含三个知识隔离的领域：
> 1. **创作平台**（Frontend/ Backend/ MCP/ Engine/ Tools/ Editor/）— AI 驱动的游戏创作链路
> 2. **容器游戏制作**（Engine/ + Backend 容器管理）— Godot 容器内的游戏构建
> 3. **游戏服务器**（GameServer/）— 独立部署的实时游戏服务器框架（多进程、TCP/KCP、Protobuf）
>
> 本宪法第 1-4、8-11 节为通用规则，适用于所有领域。**第 5-7 节仅适用于创作平台领域**，GameServer 有自己的架构模式（Actor + FSM + Protobuf），不受这些节约束。
> GameServer 的开发规范见 `GameServer/CLAUDE.md`（通用入口），各子服务有独立的 `servers/<name>/CLAUDE.md`。

> **模块详细规则按需加载（不默认装载）：**
> - Backend 并发 / 生命周期 → `.ai/constitution/backend.md` + `.ai/context/backend-lifecycle.md`
> - 测试验收 / Plan Review 硬检查 → `.ai/constitution/testing-review.md`
> - 跨模块通信 → `.ai/constitution/cross-module.md`
> - Engine 多平台兼容 → `.ai/constitution/engine.md`

## 1. 简单优先

- 只实现需求明确要求的内容，不做预支设计。
- 先用现有依赖和标准库解决问题，再考虑新增依赖。
- 简单函数和清晰数据结构优先于过早抽象。
- **实现功能时优先复用项目现有技术栈的语言**（创作平台：Go / TypeScript / Python / GDScript；GameServer：Go / Protobuf）。**不得为单点需求引入新语言**——新语言会带来构建链、依赖管理、CI、部署、人力维护等全链路成本。确需引入时，必须在 plan / 设计文档中说明理由（现有语言无法胜任、生态显著优势、已评估替代方案）并取得确认后才能落地。

## 2. 明确性与可观测性

- 错误必须显式处理，禁止静默吞错。
- 记录错误时必须带上下文日志。
- 注释解释"为什么"，不要重复代码表面含义。

## 3. 低耦合高内聚

- 一个模块只负责一类职责。
- 依赖方向保持单向，禁止循环依赖。
- 业务层依赖接口，不直接依赖基础设施实现。
- 入口层负责组装依赖，业务代码不自行拼装基础设施。

## 4. 测试先行

- 新功能和缺陷修复优先从失败测试开始。
- Go 使用 `testing`，TypeScript 使用 Jest，Python 使用 pytest。
- 新增 HTTP 端点时，必须同时补上路由注册测试和 smoke 测试。
- 详细的验收硬检查、Plan Review 检查项、产物核验规则 → `.ai/constitution/testing-review.md`

## 5. 并发与任务安全（创作平台专属）

> **作用域：** Backend/ MCP/ Engine/ 创作平台链路。不适用于 GameServer/（GameServer 使用 Actor 模型处理并发，见其自有文档）。

- Redis Streams 任务消费必须幂等，成功后 ACK，失败要记录并重试或进入死信处理。
- Go 的阻塞操作必须传播 `context.Context`。
- 容器必须有资源限制、生命周期追踪和健康检查。
- 详细的锁、连接、ctx 取消、goroutine 信号化规则 → `.ai/constitution/backend.md`

## 6. 多平台兼容（创作平台专属）

> **作用域：** Engine/ 及创作平台导出链路。不适用于 GameServer/。

- Engine 层决策必须优先保证 iOS / Android 可导出。
- 禁止引入仅支持单一移动平台或仅适合桌面端的引擎依赖。
- 性能基线以移动端设备为准，而不是桌面端。
- 详细的平台导出规则 → `.ai/constitution/engine.md`

## 7. 跨模块通信（创作平台专属）

> **作用域：** Frontend ↔ Backend ↔ MCP ↔ Godot 创作平台链路。不适用于 GameServer/（GameServer 使用 Protobuf + TCP 的服务间通信模型）。

- Client <-> Server 用 REST / SSE；Server <-> MCP 用 HTTP；MCP <-> Godot 用 TCP / WebSocket。
- 所有外部输入必须经过 schema 或 binding 校验。
- MCP 工具应保持语义化，不直接暴露底层 Godot API 细节。
- 详细的鉴权、契约、幂等规则 → `.ai/constitution/cross-module.md`

## 8. Review 闭环

- Review 发现的 CRITICAL / HIGH 问题必须在下一轮迭代开始前处置。
- 每轮迭代记录必须包含"上轮 Review 问题处置表"。
- **门禁**：计入门禁的 HIGH+ 问题累积 ≥ 2 条时，禁止进入下一轮迭代。
- 状态定义（FIXED / SPLIT / ACCEPTED_RISK / POSTPONED / OPEN）及出池条件详见 `.ai/context/reviewer-brief.md`。

## 9. 错误分层与日志分级

- **错误变量分层**：sentinel error 必须定义在它所属的语义层（repository 层 vs service 层）。
- **日志级别**：Error/Fatal 仅用于非预期系统故障；业务正常路径（如 404）记为 Error 视为违宪。
- **错误日志上下文**：每条错误必须包含操作名、实体 ID、失败原因。

## 10. 共享上下文治理

- `.ai/` 是跨 agent 的共享事实源。
- `.claude/` 是 Claude 专用运行时层，不单独定义项目事实。
- 更新项目级规则时，先改 `.ai/`，再同步必要的 agent 专用文件。

## 11. 冲突解决

优先级如下：

1. 宪法核心原则（本文件）及模块详细规则（`.ai/constitution/*.md`）
2. 共享项目文档，例如 `.ai/context/project.md` 与 `Docs/Architecture/`
3. agent 专用运行时文件，例如 `.claude/commands/*`、`.claude/skills/*`
