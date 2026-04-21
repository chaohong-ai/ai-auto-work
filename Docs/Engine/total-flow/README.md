# total-flow: 端到端游戏创建-打包流程闭环

> v0.0.3 功能模块文档 | 最后更新: 2026-03-25

## 架构总览

total-flow 打通 **Client -> Server -> MCP -> Godot** 的完整创建-对话-构建-导出-运行闭环，聚焦 Android APK 导出验证。

| 模块 | 职责 | 技术栈 |
|------|------|--------|
| **Client** | 前端 Session 生命周期管理、对话 UI、构建状态轮询、导出 UI | Next.js 14 / React 18 / TypeScript |
| **Server** | Session CRUD、异步 Build 编排、Game 记录管理、Export 调度、容器生命周期 | Go / Gin / MongoDB |
| **MCP** | 语义化工具注册与执行、Godot RPC 通信代理 | TypeScript / Express |
| **Engine (Godot)** | Headless RPC Server，接受 JSON-RPC 命令操作场景树 | GDScript / Godot 4.3 |
| **Engine (Docker)** | 容器创建/销毁、volume mount、端口映射、健康检查 | Go Docker SDK (Engine层) / Docker CLI (Server层) |

## 核心流程

```
用户                Client              Server                MCP               Godot Container
 │                   │                   │                    │                    │
 │──创建会话────────>│                   │                    │                    │
 │                   │──POST /sessions──>│                    │                    │
 │                   │                   │──Create Container──────────────────────>│ (idle模式)
 │                   │                   │──CreateMCPSession─>│──TCP Connect──────>│ :6005
 │                   │                   │<──session_id───────│                    │
 │                   │<──session─────────│                    │                    │
 │                   │                   │                    │                    │
 │──发送消息────────>│                   │                    │                    │
 │                   │──POST /chat──────>│                    │                    │
 │                   │                   │──Claude(无工具)───>│                    │
 │                   │<──AI reply────────│                    │                    │
 │                   │                   │                    │                    │
 │──开始构建────────>│                   │                    │                    │
 │                   │──POST /build─────>│ (返回202+build_id) │                    │
 │                   │                   │                    │                    │
 │                   │                   │==后台goroutine=====│                    │
 │                   │                   │  AgenticLoop       │                    │
 │                   │                   │──ExecuteRound─────>│──create_node──────>│
 │                   │                   │                    │──set_property─────>│
 │                   │                   │                    │──attach_script────>│
 │                   │                   │                    │──save_scene───────>│
 │                   │                   │<──round_result─────│                    │
 │                   │                   │──CreateGame(MongoDB)                    │
 │                   │                   │──Stop Container────────────────────────>│ (清理)
 │                   │                   │                    │                    │
 │                   │──GET /build-status (2s轮询)            │                    │
 │                   │<──{completed, game_id}                  │                    │
 │                   │                   │                    │                    │
 │──导出APK────────>│                   │                    │                    │
 │                   │──POST /games/:id/export──>│            │                    │
 │                   │                   │──docker run --rm (独立导出容器)          │
 │                   │──GET /exports/:id (2s轮询)             │                    │
 │                   │<──{completed, download_url}             │                    │
 │                   │                   │                    │                    │
 │──下载APK────────>│                   │                    │                    │
 │                   │──GET /exports/:id/download              │                    │
 │                   │<──APK file (>1MB)──│                    │                    │
```

### 阶段说明

1. **Brainstorming** -- 用户与 AI 自由对话，讨论游戏想法。Chat 接口调用 Claude 时不携带工具，纯文本对话。
2. **Building** -- `POST /build` 触发异步构建，后台 goroutine 运行 Agentic Loop（10分钟超时）。Loop 通过 MCP 工具操作 Godot 容器内的场景树。构建完成后自动创建 Game 记录并回写 `game_id` 到 Session。
3. **Export** -- 构建完成后，用户可请求导出。Export 使用独立的 `docker run --rm` 容器，挂载宿主机 ProjectDir，执行 Godot headless 导出命令。Android 导出使用 debug keystore，APK 需通过 >1MB 大小校验。
4. **Download** -- 前端轮询导出状态，完成后通过 download 端点获取 APK 文件。

### 关键设计决策

- **异步 Build**: Build API 立即返回 `build_id`（HTTP 202），前端通过 `build-status` 端点 2s 轮询，避免长连接超时问题。
- **ProjectDir 复用**: `{workDir}/sessions/{sessionID}/project/` 通过 volume mount 同时供 idle 容器和导出容器使用，无需文件拷贝。
- **容器即时清理**: Build 完成后立即停止 idle 容器。导出使用独立容器，不依赖 idle 容器。
- **双层 Docker 管理**: Engine 层使用 Docker SDK（全功能），Server 层使用 Docker CLI（轻量）。

## 关键文件索引

### Server

| 文件 | 说明 |
|------|------|
| `Backend/internal/session/manager.go` | Session 生命周期管理：Create/Resume/Suspend/Close + 异步 Build 编排 |
| `Backend/internal/session/model.go` | Session/Message/CheckItem 数据模型，Phase 和 Status 枚举 |
| `Backend/internal/handler/session_handler.go` | Session REST API handlers（Create/Chat/Build/BuildStatus/Resume/Delete） |
| `Backend/internal/game/model.go` | Game 数据模型（MongoDB `games` collection） |
| `Backend/internal/game/service.go` | Game CRUD + ProjectDir 校验（必须包含 project.godot） |
| `Backend/internal/game/repository.go` | Game MongoDB repository |
| `Backend/internal/export/service.go` | Export 编排：Docker 导出、APK 校验、export-meta.json 写入 |
| `Backend/internal/handler/export_handler.go` | Export REST API handlers（Create/Get/Download/Play/Static） |
| `Backend/internal/container/docker.go` | Server 层 Docker CLI 管理器（Create/Stop/Cleanup） |

### Engine

| 文件 | 说明 |
|------|------|
| `Engine/container/docker.go` | Engine 层 Docker SDK 管理器（Create/Stop/Exec/CopyTo/CopyFrom/Status/List/Cleanup） |
| `Engine/godot/project/autoload/rpc_server.gd` | Godot RPC Server -- JSON-RPC 2.0 over TCP:6005，8个方法 |

### MCP

| 文件 | 说明 |
|------|------|
| `MCP/src/tools/tool-registry.ts` | 工具注册表：自动扫描 level2/level3 目录，Zod 校验，重试，afterExecute hooks |

### Client

| 文件 | 说明 |
|------|------|
| `Frontend/src/hooks/useSession.ts` | Session 全生命周期 hook：create/chat/build(轮询)/resume/load/end |

### Scripts

| 文件 | 说明 |
|------|------|
| `Scripts/e2e-test.sh` | 端到端集成测试：bash+curl 自动化全流程（12步） |

### Docs

| 文件 | 说明 |
|------|------|
| `Docs/Version/v0.0.3/total-flow/plan.json` | 功能规格 + 关键决策 + 文件清单 |

## API 端点一览

### Session

| 方法 | 端点 | 说明 | 响应码 |
|------|------|------|--------|
| POST | `/api/v1/sessions` | 创建 Session（启动容器+MCP会话） | 201 |
| GET | `/api/v1/sessions/:id` | 获取 Session 状态 | 200 |
| POST | `/api/v1/sessions/:id/chat` | 发送聊天消息（brainstorming 阶段） | 200 |
| GET | `/api/v1/sessions/:id/history` | 获取对话历史（分页） | 200 |
| POST | `/api/v1/sessions/:id/build` | 启动异步构建 | 202 |
| GET | `/api/v1/sessions/:id/build-status` | 查询构建状态 | 200 |
| POST | `/api/v1/sessions/:id/resume` | 恢复挂起的 Session | 200 |
| DELETE | `/api/v1/sessions/:id` | 结束 Session | 204 |

### Export

| 方法 | 端点 | 说明 | 响应码 |
|------|------|------|--------|
| POST | `/api/v1/games/:id/export` | 创建导出任务 | 202 |
| GET | `/api/v1/exports/:id` | 查询导出状态 | 200 |
| GET | `/api/v1/exports/:id/download` | 下载导出产物 | 200 |
| GET | `/api/v1/exports/:id/play` | 在线游玩 HTML5 导出 | 302 |
| GET | `/api/v1/exports/:id/static/:filename` | HTML5 静态资源 | 200 |

### Godot RPC (JSON-RPC 2.0 over TCP:6005)

| 方法 | 说明 |
|------|------|
| `ping` | 健康检查，返回引擎版本 |
| `get_scene_tree` | 获取完整场景树 |
| `create_node` | 创建节点（parent_path, node_type, node_name, properties） |
| `set_property` | 设置节点属性（支持 Vector2/Vector3/Color/Rect2 类型转换） |
| `attach_script` | 编写并附加 GDScript 到节点 |
| `save_scene` | 保存当前场景为 .tscn 文件 |
| `validate_scene` | 校验场景完整性（节点类型、脚本引用） |
| `remove_node` | 删除节点（禁止删除场景根） |

## 配置项说明

### Server (config.yaml / 环境变量)

| 配置项 | 环境变量 | 默认值 | 说明 |
|--------|----------|--------|------|
| `session.idle_timeout` | -- | -- | Session 空闲超时，超时后自动挂起 |
| `session.max_per_user` | -- | -- | 每用户最大活跃 Session 数 |
| `session.godot_host` | -- | `localhost` | MCP 连接 Godot 容器的主机地址 |
| `session.project_base_dir` | `GAMEMAKER_WORK_DIR` | `./data/projects` | ProjectDir 基础路径 |
| `export.output_dir` | -- | -- | 导出产物输出目录 |
| `export.docker_image` | -- | -- | Godot 导出用 Docker 镜像 |
| `export.container_timeout` | -- | -- | 导出容器超时（秒）。Android 固定 300s |
| `docker.image` | -- | `gamemaker/godot-headless:4.3` | idle 容器 Docker 镜像 |
| `docker.network` | -- | -- | Docker 网络名称 |

### 容器资源限制

| 容器类型 | CPU | 内存 | 说明 |
|----------|-----|------|------|
| idle (Engine 层) | 1 CPU | 1 GB | MCP + Godot Headless 运行时 |
| idle (Server 层) | 2 CPU | 2 GB | Docker CLI 管理器默认值 |
| export (Android) | 4 CPU | 4 GB | Godot 导出需要较多资源 |
| export (其他平台) | 2 CPU | 2 GB | 默认导出资源限制 |

### E2E 测试脚本 (Scripts/e2e-test.sh)

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `BASE_URL` | `http://localhost:18081` | Server 地址 |
| `CLIENT_URL` | `http://localhost:3000` | Client 地址 |
| `MCP_URL` | `http://localhost:3100` | MCP 地址 |
| `BUILD_TIMEOUT` | `300` (5min) | 构建超时（秒） |
| `EXPORT_TIMEOUT` | `600` (10min) | 导出超时（秒） |
| `POLL_INTERVAL` | `5` | 轮询间隔（秒） |
| `TEST_USER_ID` | `e2e-test-user-{timestamp}` | 测试用户 ID |
| `CHAT_MESSAGE` | `做一个方块躲避障碍物的小游戏` | 测试聊天消息 |
