# 开发日志：v0.1.0-mvp 全模块骨架

## 2026-03-11 - 全部 8 个模块骨架搭建

### 概述
一次性搭建了 v0.1.0-mvp 全部 8 个功能模块的完整骨架框架，包含目录结构、接口定义、入口文件、数据模型和 stub 实现。共创建 **185 个文件**，覆盖 6 种技术栈。

### 新增文件统计

| 模块 | 文件数 | 技术栈 |
|------|--------|--------|
| Engine/ (01-godot-headless + 04-templates) | 33 | Docker, Bash, GDScript, Go |
| MCP/ (02-mcp-server + 03-semantic-tools) | 50 | TypeScript |
| Backend/ (05-asset + 06-verify + 07-backend) | 48 | Go |
| Frontend/ (08-frontend) | 33 | React, Next.js, TypeScript |
| Tools/ (asset-pipeline + clip-service) | 13 | Python |
| Docs/Engine/ (框架文档) | 8 | Markdown |
| **合计** | **185** | |

### 各模块详情

#### 01-Godot Headless (Engine/docker, godot, container)
- Dockerfile + entrypoint.sh + healthcheck.sh
- project.godot + screenshot.gd + health_check.gd
- build/run/test shell scripts
- Go container Manager 接口 + Docker SDK 实现骨架

#### 02-MCP Server (MCP/)
- Express HTTP 服务 + 路由 (sessions, tools, resources, snapshots)
- Session 管理 (创建/超时清理)
- Godot TCP 连接 + JSON-RPC 协议
- Tool Registry + Resource Provider

#### 03-语义工具层 (MCP/src/tools/level2/)
- 28 个 Level 2 工具骨架 (scene 10 + rules 8 + assets 5 + verify 5)
- 3 个 Level 3 模板工具 (apply/configure/get_template_info)
- shared: script-templates.ts, validation.ts, negative-rules.json (20 条)

#### 04-游戏模板 (Engine/godot/templates/platformer/)
- config.json + config.schema.json 完整定义
- 12 个 GDScript 文件 (game_manager, player, enemy_base/walking/flying, collectible, platform_moving/breakable, camera_follow, ui_manager 等)
- _shared/ 模板间共享资源

#### 05-素材库 (Backend/internal/asset, milvus + Tools/)
- Go: Asset 数据模型, Repository, SearchService, CLIPClient, COSStorage
- Milvus Client + Collection 定义 (768d CLIP ViT-L/14)
- Python: 9 个批量处理脚本 + asset_manifest.csv
- CLIP 服务: FastAPI + open_clip

#### 06-验证闭环 (Backend/internal/verify, snapshot, generation)
- 4 层验证: StaticChecker, RunChecker, ScreenshotChecker, LogicChecker
- Pipeline 编排器
- Snapshot Manager (Save/Restore/RestoreLatestVerified)
- Generation Orchestrator (Plan->Build->Verify->Heal->Deliver)

#### 07-Go 后端 API (Backend/)
- Gin 路由 + CORS 中间件
- Handler: game CRUD + generate + SSE + asset search
- Model: Game, Task, User
- Service: GameService, GenerateService, AssetService
- Repository: GameRepo, TaskRepo (MongoDB)
- Queue: Redis Stream Producer + Consumer + TaskWorker
- AI: ClaudeClient (Tool Use), System Prompt v1
- SSE: Broadcaster (Subscribe/Publish)
- MCP: HTTP Client
- Pkg: mongodb, redis, cos client

#### 08-前端界面 (Frontend/)
- Next.js 14 App Router: 5 个页面 (home, create, games, game detail)
- 16 个 React 组件 (ChatInterface, MessageBubble, PromptInput, GenerationProgress, GameCard, GameGrid, GamePlayer 等)
- 3 个 Hooks (useSSE, useGameGeneration, useGames)
- API Client + TypeScript types
- Tailwind CSS 配置

### 关键决策
- 骨架阶段所有实现都标记为 TODO，保持接口完整但不含实际业务逻辑
- Go 模块的 go.mod 已定义依赖但未运行 go mod tidy（需在填充阶段执行）
- 前端使用 Next.js 14 App Router (而非 Pages Router)

### 工程文档
8 个模块的框架文档已持久化到 Docs/Engine/{module}/framework.md

### 待办事项
- [x] 各模块填充实际实现代码
- [ ] Backend/ 运行 `go mod tidy` 下载依赖
- [ ] MCP/ 运行 `npm install` 安装依赖
- [ ] Frontend/ 运行 `npm install` 安装依赖
- [ ] Docker 镜像构建测试
- [ ] 端到端集成测试

---

## 2026-03-11 - 全模块 TODO 实现填充

### 概述
将骨架阶段遗留的所有 TODO stub 填充为实际实现代码。共处理 ~96 个 TODO 项。

### 修改文件

#### Engine (1 文件)
- `Engine/container/docker.go` — 完整实现 Docker SDK 7 个方法：Create (含 waitForReady)、Exec (StdCopy)、CopyTo/CopyFrom (tar 归档)、Stop、Status、List (标签过滤)

#### MCP Server (35+ 文件)
- `src/godot/godot-connection.ts` — 实现 sendRPC：JSON-RPC over TCP，newline-delimited，pendingRequests Map，timeout
- `src/session/session.ts` — 实现 saveSnapshot/restoreSnapshot：通过 RPC 获取/写回项目文件
- `src/resources/resource-provider.ts` — 实现 5 个资源处理器：project/structure, scene/tree, scene/preview, game/log, game/errors
- `src/tools/level2/shared/script-templates.ts` — 实现 3 个 GDScript 生成器：walking enemy, flying enemy, collectible
- `src/tools/level2/scene/*.ts` — 实现 10 个场景工具：add-player, add-enemy, add-platform, add-collectible, add-obstacle, add-npc, add-ui-element, add-camera, add-background, add-trigger-zone
- `src/tools/level2/rules/*.ts` — 实现 8 个规则工具：set-win-condition, set-lose-condition, set-player-controls, set-physics, set-spawn-point, add-level-transition, set-difficulty, set-game-loop
- `src/tools/level2/assets/*.ts` — 实现 5 个素材工具：search-asset, apply-asset, generate-asset, set-bgm, add-sfx
- `src/tools/level2/verify/*.ts` — 实现 5 个验证工具：get-screenshot, validate-scene, run-game-test, save-snapshot, rollback-snapshot
- `src/tools/level3/*.ts` — 实现 3 个模板工具：apply-template (含 deepMerge)、configure-template (含 schema 校验)、get-template-info (含完整模板注册表)

#### Server (12 文件)
- `internal/ai/claude_client.go` — 完整实现 Claude Messages API 调用：Plan/Heal，HTTP 请求构造，tool_use content block 解析
- `internal/handler/game.go` — 完整实现 9 个 handler：Create (含入队)、List (分页+搜索)、Get、Delete、Generate、GenerateStatus、GenerateStream (SSE)、Export、ExportDownload
- `internal/handler/asset.go` — 完整实现 Search 和 Get
- `internal/service/game.go` — 注入 GameRepo+TaskRepo+Producer，实现 Create 全流程
- `internal/service/generate.go` — 注入依赖，实现 StartGeneration 和 GetTaskStatus
- `internal/service/asset.go` — 代理 SearchService
- `internal/queue/consumer.go` — 完整实现任务消费：session 创建 → orchestrator 调用 → 状态更新 → SSE 广播 → 错误处理
- `internal/generation/orchestrator.go` — 完整实现 5 阶段生成管线：Plan → Build (含周期性验证) → Verify (4 层) → Heal (最多 2 次) → Deliver
- `internal/config/config.go` — 修正 MCPConfig、QueueConfig 字段匹配
- `internal/router/router.go` — 重构为依赖注入模式 (Dependencies struct)
- `internal/repository/game_repo.go` — 新增 ListPaginated (分页+搜索)
- `cmd/api/main.go` — 完整 DI 接线：所有 repo/service/handler/worker 初始化

#### 已确认无需修改（实现已完整）
- `internal/verify/static_check.go` — MCP 调用 + 文件检查 + 错误解析
- `internal/verify/run_check.go` — 游戏运行 + 错误日志收集
- `internal/verify/screenshot_check.go` — 截图 + 空白检测
- `internal/verify/logic_check.go` — 输入模拟 + 条件检查
- `internal/snapshot/manager.go` — Save/Restore/RestoreLatestVerified
- `internal/snapshot/storage.go` — 本地存储 (COS 集成待后续)
- `internal/milvus/client.go` — ANN 搜索 + 插入
- `internal/milvus/collection.go` — Schema + HNSW 索引
- `internal/asset/search.go` — 双轨融合检索
- `internal/asset/embedding.go` — CLIP HTTP 客户端
- `internal/asset/cos_storage.go` — COS SDK 上传/下载
- `internal/mcp/client.go` — MCP HTTP 客户端
- `internal/sse/broadcaster.go` — Channel SSE 广播

### 关键决策
- Router 从直接依赖 Config/MongoDB/Redis 改为 Dependencies struct 依赖注入
- MCPConfig 从 BaseURL+Duration 改为 Host+Port+Timeout(int) 以配合 main.go 接线
- QueueConfig 字段重命名以匹配实际使用（GroupName, WorkerCount）
- snapshot storage 的 COS 集成保留 TODO（需要实际 COS 凭证配置）

### 剩余 TODO
- Server: 3 个 (snapshot COS 上传/下载，需要实际 SDK 配置)
- Tools/: Python 脚本实现中 (后台进行)

### 待办事项
- [ ] Backend/ 运行 `go mod tidy` 下载依赖
- [ ] Engine/ 运行 `go mod tidy` 下载依赖
- [ ] MCP/ 运行 `npm install` 安装依赖
- [ ] Frontend/ 运行 `npm install` 安装依赖
- [ ] Docker 镜像构建测试
- [ ] 端到端集成测试
