# Claude Code 专属代码级规则与示例

> **定位：** 本文件是 `.ai/constitution.md` 的 Claude 专属补充，仅提供代码级示例和 Claude 特有约束。
> **原则不在此重复** — 核心原则见 `.ai/constitution.md`，本文件仅在命中具体编码场景时按需加载。

---

## 1. Go 错误处理示例（补充 §2 明确性、§9 错误分层）

```go
// ✅ 正确：捕获时记录日志 + 包装上下文
func (s *Service) CreateGame(ctx context.Context, req *CreateReq) error {
    game, err := s.repo.Create(ctx, req)
    if err != nil {
        s.logger.Error("create game failed", zap.Error(err), zap.String("userID", req.UserID))
        return fmt.Errorf("create game: %w", err)
    }
    return nil
}

// ❌ 错误：只返回 error，没有日志
func (s *Service) CreateGame(ctx context.Context, req *CreateReq) error {
    game, err := s.repo.Create(ctx, req)
    if err != nil {
        return fmt.Errorf("create game: %w", err)  // 缺少日志！
    }
    return nil
}
```

```typescript
// ✅ TypeScript：捕获时记录日志
try {
  await toolExecutor.execute(tool, params);
} catch (error) {
  logger.error('Tool execution failed', { tool: tool.name, error });
  throw new ToolExecutionError(tool.name, error);
}
```

## 2. 依赖反转示例（补充 §3 低耦合、§4 单一职责）

```go
// ✅ 正确：Service 依赖自己定义的接口
type GameRepository interface {
    Create(ctx context.Context, game *Game) error
    FindByID(ctx context.Context, id string) (*Game, error)
}

type Service struct {
    repo   GameRepository  // 接口，不是 *mongo.Collection
    logger *zap.Logger
}

// ❌ 错误：Service 直接依赖 mongo
import "go.mongodb.org/mongo-driver/mongo"

type Service struct {
    col *mongo.Collection  // 直接依赖基础设施
}
```

**接口归属消费方**：接口定义在使用它的包中（如 `game.GameRepository`），由 `repository/mongo` 包实现。组装只在 `cmd/api/main.go` 完成。

## 3. 并发安全示例（补充 §5 并发与任务安全）

```go
// ✅ 正确：defer 释放锁
func (m *Manager) Get(id string) *Item {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return m.items[id]
}
```

- 所有可能阻塞的操作必须接受 `context.Context`
- 启动的 goroutine 必须有退出机制（context cancellation 或 done channel）
- TypeScript 异步操作使用 async/await，Express 路由必须有 try/catch 或统一错误中间件

## 4. 控制块拆分（补充 §3 低耦合）

当 `if` 或 `for` 语句块内的代码超过 10 行时，封装成独立函数：

```go
// ✅ 正确：复杂逻辑封装
func (h *Handler) Process(items []Item) {
    for _, item := range items {
        if item.NeedsProcessing() {
            h.processItem(item)
        }
    }
}
```

## 5. Claude 专属约束

- **依赖清单**（引入新依赖前检查此列表）：
  - Go Backend: Gin, Zap, mongo-driver, go-redis, milvus-sdk-go
  - Go Engine: Docker SDK, OpenTelemetry
  - TypeScript MCP: Express, Zod, Winston
  - TypeScript Frontend: Next.js 14, React 18, Tailwind CSS
  - Python Tools: FastAPI, open-clip-torch, pymongo, pymilvus
- **数据流向**：`Client → Server → MCP → Godot`，反向通过 SSE / WebSocket，Client 不得直连 MCP 或 Godot
- **GoDoc / JSDoc**：所有导出的类型和函数必须有文档注释
- **无全局可变状态**：依赖通过参数 / 结构体成员 / 构造函数注入（例外：只读配置、Logger）
