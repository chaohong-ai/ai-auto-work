# Backend — Go 后端服务

> 端口：18081 | 目录：`Backend/` | 语言：Go

---

## 1. 选型理由

| 维度 | 选择 | 理由 | 不选 |
|------|------|------|------|
| 语言 | **Go 1.21+** | 强类型、编译快、goroutine 原生并发，适合高并发 API + 任务队列消费 | Java（重）、Node（弱类型） |
| Web 框架 | **Gin** | 性能稳定、中间件生态丰富、团队熟悉 | Fiber（生态偏小）、Echo（社区活跃度不如 Gin） |
| 日志 | **Zap** | 结构化日志、零分配、JSON 输出，便于 ELK/Loki 采集 | logrus（性能不如 Zap） |
| 数据库驱动 | **mongo-driver** (官方) | 官方维护，稳定性有保障 | |
| Redis 客户端 | **go-redis** v9 | 官方推荐、支持 Streams | |
| 向量库 | **milvus-sdk-go** | Milvus 官方 Go SDK | |

---

## 2. 架构分层

Backend 采用经典三层架构 + 领域模块拆分：

```
Backend/
├── cmd/api/main.go              # 入口：服务初始化、依赖注入
├── internal/
│   ├── router/                  # Gin 路由定义 + 中间件（CORS、Auth、TraceID、Recovery）
│   ├── handler/                 # HTTP Handler 层 — 参数校验、调用 Service、返回响应
│   │   ├── game.go              #   游戏 CRUD、生成触发
│   │   ├── session_handler.go   #   会话生命周期、聊天
│   │   ├── export_handler.go    #   导出管理
│   │   └── auth_handler.go      #   认证
│   ├── service/                 # 业务逻辑层 — 编排多个 Repository/外部调用
│   ├── repository/              # 数据访问层 — MongoDB CRUD，接口抽象（支持 Mock 仓库）
│   ├── model/                   # 数据模型定义（Game, Session, Task, Asset 等）
│   ├── session/                 # 会话管理器 — 容器生命周期、空闲监控、快照恢复
│   ├── generation/              # AI 生成编排 — Orchestrator、Agentic Loop、GameSpec/GamePlan
│   ├── mcp/                     # MCP 客户端 — HTTP 调用 MCP Server 执行工具
│   ├── ai/                      # Claude AI 客户端 — CLI/API 双模式、prompt 构建、响应解析
│   ├── container/               # Docker 容器管理 — 创建/销毁/健康检查/资源限制
│   ├── export/                  # 多平台导出 — 调度 Godot CI 容器执行导出
│   ├── asset/                   # 素材仓库 — CLIP 语义搜索 + MongoDB 标签搜索
│   ├── storage/                 # 对象存储抽象 — Local/COS 双实现，统一接口
│   ├── snapshot/                # 会话快照 — .tscn 文件级快照，支持回滚
│   ├── verify/                  # AI 产出验证 — 静态检查 + 运行检查 + 截图验证
│   ├── queue/                   # Redis Streams 任务队列 — 生产者/消费者/ACK/死信
│   └── sse/                     # SSE 事件广播器 — 实时推送生成进度到 Client
├── pkg/                         # 公共包 (mongodb, redis, trace, errors)
├── configs/config.yaml          # 运行时配置
└── tests/                       # 集成测试 (.go) + 冒烟测试 (.hurl)
```

---

## 3. 关键设计

**无状态设计：** Handler 不持有 Session 状态，Session 信息存储在 Redis + MongoDB，支持 Backend 水平扩展。

**Mock 模式：** 所有外部依赖（MongoDB、Redis、MCP、Container、AI）均有接口抽象，`env=mock` 时自动注入内存实现，单元测试无需任何外部服务。

**AI 双模式：** `ai.Client` 同时支持 CLI（`claude` 二进制，适合开发调试）和 API（HTTP SDK，适合生产计费），通过配置切换。

---

## 4. API 端点

| Method | Path | 说明 |
|--------|------|------|
| GET | `/health` | 健康检查 |
| GET | `/readyz` | 就绪探针 |
| POST | `/api/v1/games` | 创建游戏并入队生成 |
| GET | `/api/v1/games` | 游戏列表（分页） |
| GET | `/api/v1/games/:id` | 游戏详情 |
| DELETE | `/api/v1/games/:id` | 删除游戏 |
| POST | `/api/v1/games/:id/generate` | 触发生成 |
| GET | `/api/v1/games/:id/generate/status` | 轮询生成状态 |
| GET | `/api/v1/games/:id/generate/stream` | SSE 实时事件流 |
| POST | `/api/v1/sessions` | 创建会话 |
| GET | `/api/v1/sessions/:id` | 会话详情 |
| POST | `/api/v1/sessions/:id/chat` | 发送聊天消息 |
| POST | `/api/v1/sessions/:id/build` | 启动构建 |
| GET | `/api/v1/sessions/:id/build-status` | 构建进度 |
| POST | `/api/v1/sessions/:id/build/cancel` | 取消构建 |
| DELETE | `/api/v1/sessions/:id` | 结束会话 |
| GET | `/api/v1/games/:id/export` | 创建导出 |
| GET | `/api/v1/assets/search` | 素材搜索 |

---

## 5. 核心配置

```yaml
server:
  port: 18081
  mode: debug
session:
  idle_timeout: 30m        # 空闲超时自动清理
  max_per_user: 1          # 每用户最多 1 个活跃会话
  loop_mode: "agentic"     # agentic | hybrid | batch
queue:
  stream_name: "generation_tasks"
  worker_count: 2
claude:
  mode: "cli"              # cli | api
  model: "claude-sonnet-4-6-20250514"
```
