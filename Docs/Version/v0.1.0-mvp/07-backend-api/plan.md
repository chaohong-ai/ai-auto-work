# 07-Go 后端 API 技术规格

## 1. 概述

Go + Gin 后端服务，作为平台的 API 层，负责：接收前端请求、管理 AI 生成任务队列、编排容器和 MCP 调用、管理游戏和素材数据、提供 SSE 流式进度推送。

**范围**：
- Gin HTTP 路由与中间件
- AI 生成任务队列（Redis Stream）
- Claude API 集成（Tool Use 模式）
- 游戏 CRUD API
- SSE 流式进度推送
- MongoDB / Redis / COS / Milvus 客户端初始化

**不做**：
- 用户认证（Phase 0 跳过，Phase 1 添加）
- 支付系统（Phase 2）
- Kubernetes 部署（Phase 1）

## 2. 文件清单

```
Backend/
├── cmd/
│   └── api/
│       └── main.go                # 入口
├── configs/
│   ├── config.yaml                # 主配置
│   └── config.example.yaml
├── internal/
│   ├── config/
│   │   └── config.go              # 配置加载
│   ├── router/
│   │   ├── router.go              # 路由注册
│   │   └── middleware.go          # 中间件（CORS/日志/Recovery）
│   ├── handler/
│   │   ├── game.go                # 游戏 CRUD
│   │   ├── generate.go            # AI 生成相关
│   │   ├── asset.go               # 素材检索
│   │   └── health.go              # 健康检查
│   ├── service/
│   │   ├── game.go                # 游戏业务逻辑
│   │   ├── generate.go            # 生成任务编排
│   │   └── asset.go               # 素材服务
│   ├── model/
│   │   ├── game.go                # 游戏数据模型
│   │   ├── task.go                # 生成任务模型
│   │   └── user.go                # 用户模型（Phase 0 简化）
│   ├── repository/
│   │   ├── game_repo.go           # 游戏 MongoDB CRUD
│   │   └── task_repo.go           # 任务 MongoDB CRUD
│   ├── queue/
│   │   ├── producer.go            # Redis Stream 生产者
│   │   ├── consumer.go            # Redis Stream 消费者
│   │   └── task_worker.go         # 任务处理 Worker
│   ├── ai/
│   │   ├── claude_client.go       # Claude API 客户端
│   │   ├── tool_use.go            # Tool Use 消息构建
│   │   └── prompt.go              # System Prompt 管理
│   ├── sse/
│   │   └── broadcaster.go         # SSE 事件广播
│   ├── asset/                     # (见 05-asset-library)
│   ├── verify/                    # (见 06-verify-loop)
│   ├── generation/                # (见 06-verify-loop)
│   ├── container/                 # (见 01-godot-headless)
│   └── mcp/
│       └── client.go              # MCP Server HTTP 客户端
├── pkg/
│   ├── mongodb/
│   │   └── client.go              # MongoDB 连接
│   ├── redis/
│   │   └── client.go              # Redis 连接
│   └── cos/
│       └── client.go              # COS 客户端
├── go.mod
└── go.sum
```

## 3. 配置

```yaml
# Backend/configs/config.yaml

server:
  port: 8080
  mode: debug  # debug / release

mongodb:
  uri: "mongodb://localhost:27017"
  database: "gamemaker"

redis:
  addr: "localhost:6379"
  password: ""
  db: 0

cos:
  region: "ap-guangzhou"
  bucket: "gamemaker-assets"
  secret_id: "${COS_SECRET_ID}"
  secret_key: "${COS_SECRET_KEY}"
  cdn_url: "https://assets.gamemaker.example.com"

milvus:
  addr: "localhost:19530"
  collection: "asset_embeddings"

mcp:
  base_url: "http://localhost:3100"
  timeout: 30s

claude:
  api_key: "${CLAUDE_API_KEY}"
  model: "claude-sonnet-4-6-20250514"
  max_tokens: 4096

docker:
  image: "gamemaker/godot-headless:4.3"
  network: "gamemaker-net"
  max_containers: 10

queue:
  stream_name: "generation_tasks"
  consumer_group: "workers"
  max_concurrent: 5
```

## 4. API 路由

### 4.1 路由表

```
# 健康检查
GET    /api/health

# 游戏 CRUD
POST   /api/games                    # 创建游戏（触发 AI 生成）
GET    /api/games                    # 列出游戏
GET    /api/games/:id                # 获取游戏详情
DELETE /api/games/:id                # 删除游戏

# AI 生成
POST   /api/games/:id/generate       # 触发生成/重新生成
GET    /api/games/:id/generate/status # 查询生成状态
GET    /api/games/:id/generate/stream # SSE 流式进度

# 素材
GET    /api/assets/search             # 素材搜索
GET    /api/assets/:id                # 素材详情

# 导出
POST   /api/games/:id/export          # 导出 H5
GET    /api/games/:id/export/download  # 下载导出包
```

### 4.2 关键接口定义

#### POST /api/games — 创建游戏

```json
// Request
{
  "prompt": "做一个简单的平台跳跃游戏，有3个关卡，角色是一只小猫",
  "template": "platformer"  // 可选，不指定则由 AI 选择
}

// Response 201
{
  "id": "game_abc123",
  "status": "queued",
  "prompt": "...",
  "created_at": "2026-03-11T10:00:00Z",
  "task_id": "task_xyz789"
}
```

#### GET /api/games/:id/generate/stream — SSE 流式进度

```
event: status
data: {"phase": "plan", "message": "分析需求中..."}

event: step
data: {"step": 1, "tool": "apply_template", "status": "executing"}

event: step
data: {"step": 1, "tool": "apply_template", "status": "done", "message": "模板已应用"}

event: step
data: {"step": 2, "tool": "configure_template", "status": "executing"}

event: verify
data: {"layer": "static", "passed": true}

event: verify
data: {"layer": "run", "passed": true}

event: screenshot
data: {"base64": "iVBORw0KGgo..."}

event: heal
data: {"attempt": 1, "error": "CollisionShape missing", "status": "fixing"}

event: complete
data: {"status": "success", "game_url": "https://...", "screenshot": "..."}
```

#### GET /api/assets/search — 素材搜索

```json
// Request Query
// ?query=wooden+crate&type=3d_model&style=cartoon_lowpoly&limit=5

// Response
{
  "assets": [
    {
      "id": "asset_001",
      "name": "Wooden Crate",
      "type": "3d_model",
      "thumbnail_url": "https://assets.../thumb.png",
      "file_url": "https://assets.../crate.glb",
      "score": 0.87,
      "tags": ["wooden", "crate", "container"]
    }
  ],
  "has_match": true,
  "total": 3
}
```

## 5. 数据模型

### 5.1 Game

```go
// Backend/internal/model/game.go

type Game struct {
    ID          primitive.ObjectID `bson:"_id,omitempty" json:"id"`
    Prompt      string             `bson:"prompt" json:"prompt"`
    Title       string             `bson:"title" json:"title"`
    Description string             `bson:"description" json:"description"`
    Template    string             `bson:"template" json:"template"`
    Status      GameStatus         `bson:"status" json:"status"`

    // 生成信息
    TaskID       string `bson:"task_id" json:"task_id"`
    ScreenshotURL string `bson:"screenshot_url" json:"screenshot_url"`
    GameURL       string `bson:"game_url" json:"game_url"`   // H5 CDN URL

    // 快照
    LatestSnapshotID string `bson:"latest_snapshot_id" json:"latest_snapshot_id"`

    // 统计
    PlayCount    int       `bson:"play_count" json:"play_count"`
    LikeCount    int       `bson:"like_count" json:"like_count"`

    CreatedAt    time.Time `bson:"created_at" json:"created_at"`
    UpdatedAt    time.Time `bson:"updated_at" json:"updated_at"`
}

type GameStatus string
const (
    GameStatusDraft      GameStatus = "draft"
    GameStatusQueued     GameStatus = "queued"
    GameStatusGenerating GameStatus = "generating"
    GameStatusReady      GameStatus = "ready"
    GameStatusFailed     GameStatus = "failed"
)
```

### 5.2 Task (生成任务)

```go
// Backend/internal/model/task.go

type Task struct {
    ID          string     `bson:"_id" json:"id"`
    GameID      string     `bson:"game_id" json:"game_id"`
    Status      TaskStatus `bson:"status" json:"status"`
    Prompt      string     `bson:"prompt" json:"prompt"`
    Template    string     `bson:"template" json:"template"`

    // 容器信息
    ContainerID string `bson:"container_id" json:"container_id"`
    SessionID   string `bson:"session_id" json:"session_id"`

    // 进度
    CurrentPhase string        `bson:"current_phase" json:"current_phase"` // plan/build/verify/heal/deliver
    Steps        []StepRecord  `bson:"steps" json:"steps"`
    HealAttempts int           `bson:"heal_attempts" json:"heal_attempts"`

    // 结果
    Result      *GenerationResult `bson:"result,omitempty" json:"result,omitempty"`
    Error       string            `bson:"error,omitempty" json:"error,omitempty"`

    CreatedAt   time.Time `bson:"created_at" json:"created_at"`
    StartedAt   time.Time `bson:"started_at,omitempty" json:"started_at,omitempty"`
    FinishedAt  time.Time `bson:"finished_at,omitempty" json:"finished_at,omitempty"`
}

type TaskStatus string
const (
    TaskStatusQueued     TaskStatus = "queued"
    TaskStatusRunning    TaskStatus = "running"
    TaskStatusSucceeded  TaskStatus = "succeeded"
    TaskStatusFailed     TaskStatus = "failed"
)
```

## 6. 任务队列 (Redis Stream)

### 6.1 生产者

```go
// Backend/internal/queue/producer.go

func (p *Producer) EnqueueTask(ctx context.Context, task *model.Task) error {
    // XADD generation_tasks * task_id xxx game_id yyy prompt zzz
    return p.rdb.XAdd(ctx, &redis.XAddArgs{
        Stream: p.streamName,
        Values: map[string]any{
            "task_id":  task.ID,
            "game_id":  task.GameID,
            "prompt":   task.Prompt,
            "template": task.Template,
        },
    }).Err()
}
```

### 6.2 消费者

```go
// Backend/internal/queue/consumer.go

func (c *Consumer) Start(ctx context.Context) {
    // XREADGROUP GROUP workers consumer_1 COUNT 1 BLOCK 5000 STREAMS generation_tasks >
    for {
        streams, err := c.rdb.XReadGroup(ctx, &redis.XReadGroupArgs{
            Group:    c.groupName,
            Consumer: c.consumerID,
            Streams:  []string{c.streamName, ">"},
            Count:    1,
            Block:    5 * time.Second,
        }).Result()

        if err != nil { continue }

        for _, msg := range streams[0].Messages {
            c.processTask(ctx, msg)
            c.rdb.XAck(ctx, c.streamName, c.groupName, msg.ID)
        }
    }
}

func (c *Consumer) processTask(ctx context.Context, msg redis.XMessage) {
    taskID := msg.Values["task_id"].(string)

    // 1. 分配容器
    container, _ := c.containerMgr.Create(ctx, ContainerConfig{Mode: "idle"})

    // 2. 创建 MCP Session
    session, _ := c.mcpClient.CreateSession(ctx, container.ID)

    // 3. 调用编排器
    result, _ := c.orchestrator.Generate(ctx, GenerationRequest{
        UserPrompt:  msg.Values["prompt"].(string),
        SessionID:   session.ID,
        ContainerID: container.ID,
    })

    // 4. 更新任务状态
    // 5. 导出 H5 并上传 COS
    // 6. 回收容器
    c.containerMgr.Stop(ctx, container.ID)
}
```

## 7. Claude API 集成

```go
// Backend/internal/ai/claude_client.go

type ClaudeClient struct {
    apiKey    string
    model     string
    maxTokens int
}

type ToolCall struct {
    Name string         `json:"name"`
    Args map[string]any `json:"input"`
}

// Plan: 让 AI 分析需求并输出工具调用计划
func (c *ClaudeClient) Plan(ctx context.Context, prompt string, tools []ToolDef) ([]ToolCall, error) {
    // Claude Messages API with Tool Use
    // System Prompt + 用户 Prompt + 可用工具列表
    // 返回 tool_use content blocks
}

// Heal: 让 AI 分析验证错误并输出修复工具调用
func (c *ClaudeClient) Heal(ctx context.Context, verifyResult *VerifyResult) ([]ToolCall, error) {
    // 将验证错误结构化为 user message
    // AI 返回修复工具调用
}

// 将 MCP 工具定义转为 Claude Tool Use 格式
func mcpToolToClaudeTool(mcp ToolDefinition) ToolDef {
    return ToolDef{
        Name:        mcp.Name,
        Description: mcp.Description,
        InputSchema: mcp.Parameters,
    }
}
```

## 8. SSE 广播

```go
// Backend/internal/sse/broadcaster.go

type Broadcaster struct {
    channels map[string][]chan Event  // taskID → []subscriber
    mu       sync.RWMutex
}

type Event struct {
    Type string `json:"type"` // "status", "step", "verify", "screenshot", "heal", "complete", "error"
    Data any    `json:"data"`
}

func (b *Broadcaster) Subscribe(taskID string) <-chan Event
func (b *Broadcaster) Unsubscribe(taskID string, ch <-chan Event)
func (b *Broadcaster) Publish(taskID string, event Event)
```

## 9. Go 依赖

```
github.com/gin-gonic/gin           # HTTP 框架
github.com/redis/go-redis/v9       # Redis 客户端
go.mongodb.org/mongo-driver        # MongoDB 驱动
github.com/docker/docker           # Docker SDK
github.com/milvus-io/milvus-sdk-go # Milvus SDK
github.com/tencentyun/cos-go-sdk-v5 # 腾讯云 COS SDK
github.com/google/uuid              # UUID
github.com/spf13/viper              # 配置管理
go.uber.org/zap                     # 日志
```

## 10. 验收标准

1. **服务启动**：`go run cmd/api/main.go` 在 8080 端口正常启动
2. **创建游戏**：POST /api/games 返回 game_id 和 task_id，任务入队 Redis
3. **任务消费**：Worker 从 Redis Stream 消费任务，分配容器，调用编排器
4. **SSE 推送**：前端 EventSource 连接后收到 status/step/verify/complete 事件
5. **游戏列表**：GET /api/games 返回所有游戏，含状态和截图
6. **素材搜索**：GET /api/assets/search?query=xxx 返回相关素材
7. **H5 导出**：生成完成后导出 H5 zip，上传 COS，返回 CDN URL
8. **并发控制**：同时 5 个任务运行，第 6 个排队等待
9. **错误处理**：容器超时/MCP 断连/AI 调用失败时返回明确错误，不阻塞队列
10. **端到端**：POST 创建游戏 → SSE 跟踪进度 → 完成后 GET 获取 game_url → 浏览器打开可玩
