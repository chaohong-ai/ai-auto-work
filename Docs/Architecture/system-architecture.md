# GameMaker 系统架构文档

> AI Native 游戏创作平台 - 用户通过自然语言对话创建可运行的移动端游戏
>
> Version: 1.0 | Date: 2026-03-27

---

## 1. 系统总览

GameMaker 是一个 AI 驱动的游戏创作平台。用户在浏览器中通过自然语言描述游戏想法，系统借助 Claude AI + MCP 工具链 + Godot 4 引擎，自动完成游戏的设计、开发、构建和多平台导出。

### 1.1 整体架构图

```
                                                    ┌─────────────┐
                                                    │  文件存储     │
                                                    │ (COS/Local)  │
                                                    └──────▲───────┘
                                                           │
┌────────┐    ┌───────────┐    ┌──────────┐    ┌──────────┴──┐    ┌──────────────┐
│  浏览器  │───▶│ FrontEnd  │───▶│ Gateway  │───▶│  BackEnd x N │───▶│   K8S 集群    │
│ (用户)  │    │ Next.js   │    │ (Nginx/  │    │  (Go+Gin)   │    │ Godot容器池   │
└────────┘    │ :3000     │    │  RPC)    │    │  :18081     │    │ MCP+Engine   │
              └───────────┘    └──────────┘    └──────┬──────┘    └──────────────┘
                                                      │
                                                ┌─────▼─────┐
                                                │    DB      │
                                                │ MongoDB    │
                                                │ Redis      │
                                                │ Milvus     │
                                                └────────────┘
```

### 1.2 核心设计理念

| 原则 | 说明 |
|------|------|
| **AI Native** | AI 不是辅助工具，而是核心创作引擎。用户描述意图，AI 自动编排游戏逻辑 |
| **会话驱动** | 每个游戏创建过程是一个有状态的 Session，包含 brainstorming 和 building 两个阶段 |
| **容器隔离** | 每个 Session 独占一个 Godot Docker 容器，通过 K8S 调度，资源隔离 |
| **多平台导出** | 以移动端为性能基线，支持 HTML5/Android/iOS/Windows/Linux 导出 |

---

## 2. 服务架构

### 2.1 服务清单

| 服务 | 技术栈 | 端口 | 职责 |
|------|--------|------|------|
| **Client (FrontEnd)** | Next.js 14 + React 18 + Tailwind CSS | 3000 | 用户交互界面，游戏创建/管理/预览 |
| **Gateway** | Nginx / RPC Proxy | - | 前端访问后端的代理层，负载均衡 |
| **Backend (Server)** | Go + Gin + Zap | 18081 | 核心业务逻辑：用户、游戏、会话、任务队列 |
| **MCP Server** | TypeScript + Express | 3100 | Godot 引擎桥接层，语义化工具执行 |
| **Godot Engine** | Godot 4.3 Headless + GDLuau | 6007 (TCP) | 游戏运行时，场景编辑，导出构建 |
| **CLIP Service** | Python + FastAPI + OpenCLIP | 8100 | 图片语义嵌入，素材搜索 |
| **GameServer** | Go | 22333 | 排行榜/社区服务 |
| **MongoDB** | MongoDB 7.0 | 27017 | 持久化存储（游戏、会话、任务、素材元数据） |
| **Redis** | Redis 7 | 6379 | 任务队列（Redis Streams）、缓存、会话状态 |
| **Milvus** | Milvus + etcd + MinIO | 19530 | 向量数据库，CLIP 嵌入检索 |
| **文件存储** | 腾讯云 COS / 本地文件系统 | - | 游戏项目文件、AI 会话中间产物、导出产物 |

### 2.2 服务部署模式

```
生产环境:
  FrontEnd ──── Nginx(Gateway) ──── BackEnd x N (水平扩展)
                                         │
                                    K8S 集群
                                    ├── Godot Pod (按需创建，KEDA 自动扩缩)
                                    ├── MCP Pod
                                    └── CLIP Pod

开发环境 (docker-compose):
  FrontEnd(:3000) → BackEnd(:18081) → MCP(:3100) → Godot(:6007)
  MongoDB(:27017) + Redis(:6379) + Milvus(:19530)

测试环境 (mock mode):
  BackEnd (内存仓库，无需外部服务)
```

---

## 3. 数据流与通信

### 3.1 通信协议

```
浏览器 ──HTTP/SSE──▶ FrontEnd ──HTTP/RPC──▶ Gateway ──HTTP──▶ BackEnd
                                                                │
                                                          HTTP ─┤── MongoDB (driver)
                                                                ├── Redis (driver)
                                                                ├── Milvus (gRPC)
                                                          HTTP ─┤── MCP Server
                                                                │      │
                                                                │   TCP/JSON-RPC
                                                                │      │
                                                                │      ▼
                                                                │   Godot Engine
                                                                │
                                                          SSE ──┤──▶ 浏览器 (实时事件推送)
```

**关键约束（宪法第七条）：** 数据只能沿 `Client → Server → MCP → Godot` 方向流动。反向通信通过 SSE（Server→Client）或回调机制。Client 不能直连 MCP 或 Godot。

### 3.2 核心业务流 - 游戏创建

```
┌─────────┐   POST /games    ┌──────────┐   Redis Stream   ┌──────────┐
│  Client  │ ───────────────▶ │  Server   │ ───────────────▶ │  Worker  │
└─────────┘                   └──────────┘                   └────┬─────┘
     ▲                              │                              │
     │ SSE events                   │ 写入 MongoDB                  │
     │ (status/step/screenshot)     │ (Game: draft→queued)          │
     │                              ▼                              │
     │                        ┌──────────┐                         │
     └────────────────────────│Broadcaster│◀────────────────────────┘
                              └──────────┘         │
                                                   ▼
                                            ┌─────────────┐
                                            │ Orchestrator │
                                            │  (AI Loop)   │
                                            └──────┬──────┘
                                                   │ HTTP
                                                   ▼
                                            ┌─────────────┐    TCP/JSON-RPC    ┌────────┐
                                            │ MCP Server  │ ─────────────────▶ │ Godot  │
                                            │  (工具执行)   │                    │ Engine │
                                            └─────────────┘                    └────────┘
```

**流程步骤：**

1. **创建游戏** — Client 发送 POST `/api/v1/games`（prompt + template）
2. **入队** — Server 创建 Game（draft）和 Task（queued），推入 Redis Stream
3. **消费** — Worker 从 Redis Stream 取出任务，调用 Orchestrator
4. **AI 生成循环** — Orchestrator 驱动 Claude AI 进行迭代开发：
   - AI 分析需求 → 调用 MCP 工具 → 执行 Godot 操作 → 验证结果
   - 每 3 步进行一次验证（verify），最多 2 次自愈（heal）
5. **实时推送** — 每个步骤通过 SSE Broadcaster 推送到 Client
6. **完成** — Game 状态更新为 ready，快照保存到文件存储

### 3.3 核心业务流 - 会话式开发（Workspace 模式）

```
Client                    Server                    MCP                     Godot
  │                         │                        │                        │
  │ POST /sessions          │                        │                        │
  │────────────────────────▶│ 创建 Docker 容器         │                        │
  │                         │───────────────────────▶│ 建立 TCP 连接            │
  │                         │                        │───────────────────────▶│
  │                         │◀───────────────────────│ session_id             │
  │◀────────────────────────│ session ready           │                        │
  │                         │                        │                        │
  │ POST /sessions/:id/chat │                        │                        │
  │────────────────────────▶│ Agentic Loop            │                        │
  │                         │ (Claude AI turn)        │                        │
  │                         │──── tool_call ─────────▶│──── JSON-RPC ────────▶│
  │                         │◀─── tool_result ────────│◀─── result ───────────│
  │                         │ (迭代多轮)               │                        │
  │◀──── SSE events ────────│                        │                        │
  │                         │                        │                        │
  │ POST /sessions/:id/build│                        │                        │
  │────────────────────────▶│ Build Phase             │                        │
  │◀──── SSE (progress) ────│ ─── export ───────────▶│──── build ────────────▶│
  │                         │                        │                        │
```

**Session 两阶段模型：**

| 阶段 | 说明 | AI 行为 |
|------|------|---------|
| **Brainstorming** | 需求讨论，方案共创 | 自然语言对话，生成 GameSpec/GamePlan |
| **Building** | 代码实现，场景构建 | 调用 MCP 工具操作 Godot 项目 |

### 3.4 SSE 事件契约（容器创建阶段）

容器创建链路通过 `GET /api/v1/sessions/:id/events` SSE 流实时推送阶段事件。客户端通过 `?token=<events_capability_token>` 查询参数进行鉴权（capability token 在创建 Session 时随 201 响应一并返回）。

#### 容器创建阶段事件顺序

| 事件类型 | 触发时机 | 数据字段 |
|----------|----------|----------|
| `container.starting` | 发起 Docker 容器创建前（intent） | `{"session_id": "..."}` |
| `container.started` | Docker 容器创建成功，容器 ID 可用 | `{"container_id": "..."}` |
| `container.ready` | MCP Session 建立、Session 持久化、Capability Token 签发完成 | `{"session_id": "..."}` |
| `workspace.initialized` | `init-workspace` MCP 工具调用成功（项目目录已初始化） | `{"session_id": "..."}` |
| `knowledge.seeded` | `seed-knowledge` MCP 工具调用成功（模板与知识库已注入） | `{"session_id": "..."}` |

#### 其他关键 SSE 事件

| 事件类型 | 场景 | 说明 |
|----------|------|------|
| `closed` | Session 被关闭 | `{"session_id": "...", "reason": "user"}` |
| `phase` | Phase 状态变更（brainstorming / building / completed） | `{"phase": "..."}` |
| `build_error` | 异步构建失败 | `{"error": "..."}` |
| `build_cancelled` | 构建被取消 | `{"session_id": "..."}` |
| `workspace:build_complete` | Workspace 模式构建完成 | `{"game_id": "..."}` |
| `cover:ready` | 游戏封面截图已生成并上传 | `{"url": "..."}` |
| `cover:failed` | 封面截图生成失败 | `{"error": "..."}` |

#### Capability Token 语义

- `events_capability_token` 随 `POST /api/v1/sessions` 的 201 响应返回，TTL 由 `session.capability_ttl` 配置（默认 1h）
- 缺少 token 或 token 无效/已过期 → `401 MISSING_CAPABILITY / INVALID_CAPABILITY / EXPIRED_CAPABILITY`
- Token 绑定 Session ID；使用其他 Session 的 Token 访问 → `403 CAPABILITY_SESSION_MISMATCH`
- Token 刷新：`POST /api/v1/sessions/:id/events/token/refresh`（JWT 保护），返回新 `events_capability_token`

### 3.5 导出流程

```
Client ──▶ Server ──▶ 创建 Export Container (Godot CI)
                           │
                           ├── 加载项目文件
                           ├── 执行 Godot 导出命令
                           ├── 产出: APK / HTML5 / IPA
                           │
                           ▼
                      文件存储 (COS/Local)
                           │
                           ▼
                     Client 下载/预览
```

**支持平台：** HTML5, Windows, Linux, Android, iOS

---

## 4. 各模块详细设计

每个模块有独立的架构文档，包含选型理由、竞品对比、架构设计、关键决策等。

| 模块 | 技术栈 | 端口 | 详细文档 |
|------|--------|------|----------|
| **Backend** | Go + Gin + Zap | 18081 | [modules/backend.md](modules/backend.md) |
| **Engine** | Godot 4.3 Headless + GDScript | 6007 | [modules/engine.md](modules/engine.md) |
| **MCP Server** | TypeScript + Express + Zod | 3100 | [modules/mcp-server.md](modules/mcp-server.md) |
| **Client** | Next.js 14 + React 18 + Tailwind | 3000 | [modules/client.md](modules/client.md) |
| **Tools** | Python + FastAPI + OpenCLIP | 8100 | [modules/tools.md](modules/tools.md) |
| **GameServer** | Go | 22333 | [modules/gameserver.md](modules/gameserver.md) |
| **数据层** | MongoDB + Redis + Milvus + COS | - | [modules/data-layer.md](modules/data-layer.md) |
| **外部平台** | Claude API + SD/DALL·E/Suno/ElevenLabs | - | [modules/external-platforms.md](modules/external-platforms.md) |

---

## 5. 数据架构

### 5.1 核心数据模型

```
Game {
  id, user_id, prompt, title, description,
  template, status (draft→queued→generating→ready→failed),
  task_id, session_id, screenshots[], timestamps
}

Session {
  id, user_id, game_id, container_id, mcp_session_id,
  phase (brainstorming | building),
  status (active | suspended | completed),
  rounds[], history[]
}

Task {
  id, game_id, status, prompt, template,
  current_phase, steps[], heal_attempts, error
}
```

> 存储选型详情见 [modules/data-layer.md](modules/data-layer.md)

### 5.2 文件存储结构

```
文件存储/
├── users/{user_id}/
│   └── games/{game_id}/
│       ├── project/             # Godot 项目文件
│       ├── snapshots/           # 会话快照
│       ├── exports/             # 导出产物
│       └── assets/              # 游戏素材
└── sessions/{session_id}/
    ├── workspace/               # 工作区文件
    └── history/                 # AI 对话历史
```

---

## 6. 任务队列与并发

### 6.1 Redis Streams 任务队列

```
Producer (API Handler)                Consumer (Queue Worker)
       │                                      │
       │  XADD generation_tasks               │  XREADGROUP workers
       │──────────────────────▶  Redis  ◀──────│
       │                       Stream          │
       │                                       │  处理成功 → XACK
       │                                       │  处理失败 → 重试/死信队列
```

**关键保证：**
- 生产者与消费者完全解耦
- 消费者幂等处理（同一消息重复消费无副作用）
- 成功必 ACK，失败必记录日志

### 6.2 AI 生成循环（Agentic Loop）

```
           ┌─────────────────────────────┐
           │     Agentic Loop            │
           │                             │
           │  ┌──────┐   tool_call  ┌────┴────┐
  prompt──▶│  │Claude│ ──────────▶ │MCP Tools│
           │  │  AI  │ ◀────────── │         │
           │  └──┬───┘  tool_result└─────────┘
           │     │                             │
           │     │ 每3步 verify                │
           │     ▼                             │
           │  ┌──────────┐                     │
           │  │Verifier  │ ──失败──▶ heal (≤2次)│
           │  └──────────┘                     │
           │     │ 通过                         │
           │     ▼                             │
           │   完成 / 下一步                    │
           └─────────────────────────────┘

配置:
  max_tool_calls: 50
  verify_interval: 3
  max_heal_attempts: 2
  loop_mode: agentic | hybrid | batch
```

---

## 7. 部署架构

### 7.1 生产环境（目标）

```
                    ┌─────────────────────────────────────────────┐
                    │              K8S 集群                        │
                    │                                             │
  浏览器 ──▶ CDN ──▶│  Nginx Ingress (Gateway)                    │
                    │       │                                     │
                    │       ├──▶ FrontEnd Pod (Next.js)           │
                    │       │                                     │
                    │       └──▶ BackEnd Pod x N (Go, 水平扩展)    │
                    │               │                             │
                    │               ├──▶ Godot Pod (按需, KEDA)   │
                    │               ├──▶ MCP Pod                  │
                    │               └──▶ CLIP Pod                 │
                    │                                             │
                    │  ┌──────────┐ ┌───────┐ ┌────────┐         │
                    │  │ MongoDB  │ │ Redis │ │ Milvus │         │
                    │  └──────────┘ └───────┘ └────────┘         │
                    └─────────────────────────────────────────────┘
                                                    │
                                              腾讯云 COS
                                             (文件存储)
```

- **BackEnd 水平扩展：** 无状态设计，通过 Gateway 负载均衡
- **Godot 容器按需调度：** 用户创建 Session 时启动，空闲 30 分钟回收
- **KEDA 自动扩缩：** 基于 Redis Stream pending 消息数动态调整 Worker 数量

### 7.2 开发环境

```bash
# 启动全栈开发环境
Scripts/docker-compose.dev.yml   # MongoDB + Redis + Godot
Server (:18081)                  # go run
MCP (:3100)                      # npm run dev
Client (:3000)                   # npm run dev
```

### 7.3 测试环境

```bash
# Mock 模式（无需任何外部服务）
env: mock → 内存仓库 + Mock AI + Mock MCP + Mock Container

# Test 模式（需要 MongoDB + Redis）
docker-compose.test.yml → MongoDB + Redis (tmpfs)
```

---

## 8. 安全与可靠性

### 8.1 容器安全

- 每个 Godot 容器设置 CPU/内存上限
- 容器间网络隔离（Docker bridge network）
- 生产环境计划使用 gVisor 增强沙箱

### 8.2 数据校验

| 层级 | 校验方式 |
|------|----------|
| Client → Server | Gin binding 校验 |
| Server → MCP | Zod schema 校验 |
| MCP → Godot | JSON-RPC 协议约束 |
| Tools API | Pydantic/FastAPI 校验 |

### 8.3 错误处理

- 所有错误显式处理，配合结构化日志（Zap/Winston）
- SSE 错误事件实时通知客户端
- 任务失败进入重试或死信队列

### 8.4 会话管理

- 每用户最多 1 个活跃 Session
- 空闲 30 分钟自动回收容器
- 快照机制支持 Session 恢复

---

## 9. 技术栈汇总

| 分层 | 技术 | 版本 |
|------|------|------|
| **前端** | Next.js + React + Tailwind CSS | 14 / 18 |
| **网关** | Nginx (RPC Proxy) | - |
| **后端** | Go + Gin + Zap | 1.21+ |
| **MCP** | TypeScript + Express + Zod + Winston | Node 18+ |
| **引擎** | Godot 4.3 Headless + GDScript/Luau | 4.3-stable |
| **AI** | Claude Sonnet (Tool Use) | claude-sonnet-4-6 |
| **数据库** | MongoDB | 7.0 |
| **缓存/队列** | Redis (Streams) | 7.x |
| **向量库** | Milvus + etcd + MinIO | - |
| **文件存储** | 腾讯云 COS | - |
| **素材服务** | Python + FastAPI + OpenCLIP | 768d |
| **容器编排** | Docker + K8S + KEDA | - |
| **CI/CD** | GitHub Actions | - |

---

## 10. 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 引擎 | Godot 4.3 Headless | 开源、轻量、支持 Headless 模式，适合容器化 |
| MCP 工具层级 | 语义化 Level 2/3 (~30 工具) | AI 理解成本低，一个工具 = 一个编辑意图 |
| 容器隔离 | Docker per Session | 用户间完全隔离，资源可控 |
| 任务队列 | Redis Streams | 轻量、可靠，支持消费组和 ACK |
| AI 模式 | CLI + API 双模式 | CLI 适合开发调试，API 适合生产 |
| 向量搜索 | Milvus + CLIP | 语义素材搜索，非关键词匹配 |
| 文件存储 | COS（生产）/ Local（开发） | 统一接口，开发零依赖 |
| 自动扩缩 | KEDA | 基于队列深度动态调度 Godot 容器 |
