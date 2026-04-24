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

### Headless Godot / ThinClient WS 端口合同（权威来源）

<!-- Context Repair: v0.0.4 thin-client CR-3 — fallback_ws_host 错误写成 18081；Backend sync_ws_url 字段缺失，跨模块合同断裂 -->

Headless Godot 容器与 ThinClient 之间通过 WebSocket 通信，端口与字段定义为整个链路的共享事实：

- **WebSocket 端口**：容器内固定为 `9001`；`18081` 是 Backend REST 端口，**不是** WS 端口，不可混用
- **Backend 下发字段**：`POST /api/v1/sessions` 响应体路径 `data.session.sync_ws_url`，格式 `ws://<host>:9001`；Backend Session 模型必须含该字段，缺失即为合同断裂
- **ThinClient fallback 配置**：`fallback_ws_host = "ws://localhost:9001"`，不得配置为 18081 或其他端口
- **Smoke 断言 JSONPath**：`sessions.hurl` 必须包含 `jsonpath "$.data.session.sync_ws_url" != ""`

Plan 涉及 ThinClient ↔ Backend ↔ Headless Godot WS 链路时，必须三端同步此合同：Backend session 模型含 `sync_ws_url` 字段、**`SessionScene.gd` 的 `init_session()` 从会话响应读取 `sync_ws_url` 并同时调用 `SyncManager.connect_ws()` 与 `SSEManager.connect_sse()`**、smoke 明确断言 JSONPath。任意一端缺失视为 **Critical**。

**SyncManager 公开 WS API 命名已固化**：`connect_ws(url)` / `disconnect_ws()` 是唯一权威接口名，不得在任何 task 文件、plan 或 GDScript 代码中单方面改名。改名须先同步本节与 `engine.md` 双连接义务节，否则视为合同回归（Critical，标注 `[CONTRACT_OVERRIDE]`）。

**SyncManager 重连公开合同已固化**（REQ-013 范围）：以下接口名属于跨模块公开合同，与连接/断开 API 同等级别：失败信号 `connection_failed`、重连计数访问器 `get_reconnect_attempts()`、最大重连次数字段 `max_reconnect_attempts`。task 文件不得单方面改名；改名须同步本节、`engine.md` 重连合同节、`plan.md`、`acceptance-report.md` 及所有消费者；违反 → Critical（`[CONTRACT_OVERRIDE]`），无豁免。

> 实现编排规则（双连接义务、退出清理、重连命名约束）详见 `.ai/constitution/engine.md`「ThinClient SessionScene 双连接编排义务」。

### TP-UGC-3D 模板 `GameConfig` 单例访问契约（task-32 M1）

`Template/TP-UGC-3D/content/config/game_config.gd` 通过 `project.godot` `[autoload]` 段以 `GameConfig` 名注册为全局单例。由于 Godot 4 禁止 autoload 名与 `class_name` 同名，该脚本**有意不声明** `class_name GameConfig`；autoload 注册名本身就是全局句柄。

**唯一合规访问路径**：`GameConfig.<field>` 直接字段读写（例：`GameConfig.network_enabled`、`GameConfig.server_host`、`GameConfig.server_port`）。

**禁止的访问路径**：
- `GameConfig.get_instance().<field>` — `get_instance()` 是历史遗留的静态回退助手，**不是**业务代码的契约入口；保留仅为兼容，不得在新脚本 / 测试中使用；
- `get_node_or_null("/root/GameConfig").<field>` — 运行时节点路径查找仅允许用于**确实需要判空**的场景（例：autoload 启动前 / 模板剥离后的兜底），且必须就地 `push_error` 或短路返回，不作为字段访问的默认语法。

**混用代价**：三种访问路径并存时，`_instance` 未 set、autoload 重命名、或静态助手被删除等任一变化都会让部分调用方静默失败。task-32 Round 8 M1 已把"`mode_select.gd` 用 `get_instance()` + `level_script.gd` 用 `/root/GameConfig` + `game_config.gd` 头注释声明直接字段访问"列为 Medium 违契约。

**新脚本 / 测试 / plan / review 的硬规则**：
- 所有 TP-UGC-3D 模板下的新 GDScript 必须使用 `GameConfig.<field>`；
- plan / task 中若出现 `GameConfig.get_instance()` / `/root/GameConfig` 的字段访问，plan review 须直接标记为违反模板契约；
- develop review 遇到同一模板内三种访问路径并存即判 `TEMPLATE_SINGLETON_ACCESS_DIVERGENCE` Medium+。

**任务生成侧强制规则（game-net acceptance CR-2）**：
- 凡新增或修改 TP-UGC-3D 模板 GDScript 并访问 GameConfig 的任务，task 的 `verify_commands` 必须包含反扫描步骤（失败即阻断）：
  `grep -rn "GameConfig\.get_instance()\|get_node_or_null.*GameConfig" Template/TP-UGC-3D/`
  命中任何结果 → 视为合规违规，task 不得标记完成，须将违规访问改为 `GameConfig.<field>` 直接访问后再复查。
- auto-work 生成侧：develop 阶段写盘前对 `Template/TP-UGC-3D/` 下所有本轮新增 / 修改的 `.gd` 文件执行上述扫描；命中即阻断进入 reviewer 阶段，提示开发者修复违规访问路径。
- **触发条件**：`mode_select.gd` 与多个 task 验证标准继续使用 `GameConfig.get_instance()`，是规则未进入任务模板的系统性缺口（game-net acceptance CR-2）。

### 调研信息质量基线（research methodology）

任何在 `Docs/Research/*/` 下生产的调研报告、review 报告、克隆 / 竞品估算，都必须遵守 `.ai/constitution/research.md` 的硬规则。核心锚点：

- **teaser 定性须硬证据**：不得仅凭 `WebFetch` / 静态抓取失败或首页简陋，就把调研对象定性为「teaser」「未形成真正产品」。必须先拿到「真实浏览器 + Network 面板 + 可生成样例 + 商店元数据 + 社交渠道近 90 天活跃」中至少两项硬证据；否则结论须标注「未验证 / 待实测」并按六级状态分级（未验证 / 可访问 / 可生成 / 可分享 / 可编辑 / 可导出）。
- **第三方聚合页只能作线索**：Aibase / Creati / AITECHFY / Powerusers / OpenTools / Similarweb / ProductHunt / Toolify / FutureTools 等聚合目录页仅计为 `source_type=third_party`，不得单独支撑融资、估值、MAU / DAU、下载量、定价、技术栈结论。关键结论必须有官方 / 商店 / 可信媒体 / APK 反编译等一手来源，否则必须在正文改为「待验证假设」或标 `confidence=low`。
- **规模数字必须带时点与来源类型**：MAU / DAU / 月访问 / 下载量 / 注册用户 / 估值 / 融资额 / 员工数 / 付费率 / 订阅价等数量级字段，必须同时附 `as_of` / `source_type` / `source_url` / `verified_at`，并严格区分 `traffic` / `installs` / `MAU` / `registered_users` 四种口径，禁止混用。竞品对比表必须含「当前状态」列以反映近 12 个月的收购、停服、转型、融资枯竭、监管事件。
- **同赛道公司数据禁止互套**（kubee-research 2026-04-22 review I2）：`source_url` 必须实际讲述该条目的主体公司；遇到 Synthesia / HeyGen、Character.AI / Replika、Zepeto / Ready Player Me / Genies、Rosebud / Kubee 等同赛道公司数据易混场景，`verified_at` 栏须附注「被引 URL 主体公司名」。发现 URL 实际主体与引用公司不一致（例如把 Synthesia `$4B` 误归 HeyGen）即视为误引 / 幻觉引用，必须撤回并在 `evidence-log.md` 留「误引修正」行。
- **附录义务**：同时涉及上述三类要求的调研（竞品研究、市场调研、克隆估算），主报告须附 `evidence-log.md` 或 `sources.md`（按 `source_type` 分组，逐条带 `verified_at` + `confidence`）。

`research:review` 维度 3（信息质量）与维度 4（对比分析）须对以上五条逐项核查，命中即判 Critical / Important。详细规则与分级阈值见 `.ai/constitution/research.md`。

## 共享协作原则

- 项目事实、架构认知、工程约束统一放在 `.ai/`
- Claude 专用命令和 skill 保留在 `.claude/`
- 如果要新增一个同时影响多个 agent 的规则，优先写入 `.ai/`
- 如果只影响 Claude 的运行方式，再写入 `.claude/`
