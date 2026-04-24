# 宪法详细规则：Backend（Go 并发与生命周期）

> **作用域：仅 `Backend/` 目录。** 本文件是 `.ai/constitution.md` §5「并发与任务安全」的详细展开，仅在涉及 Backend Go 代码时按需加载。
> **不适用于 `GameServer/`**——GameServer 使用 Actor 并发模型，有独立的架构规范（见 `GameServer/CLAUDE.md`）。

## 长生命周期独占锁（不可协商）

session / game / build / reservation 等业务允许持续活跃超过任意固定 TTL 的独占锁，禁止仅凭"锁创建时间 + 固定 TTL"判定可抢占。必须二选一：(a) 可续期锁，续期信号绑定确定的持久化活动点（成功的工具调用、轮次提交、显式 heartbeat 写入）；或 (b) 抢占前额外校验原持有者已进入终态（`closed` / `error` / `suspended` / `cleanup_failed`）或 `idle_since` 超阈值。详见 `.ai/context/backend-lifecycle.md`"独占锁设计硬约束"。

## 长生命周期外部连接（不可协商）

被多个请求复用、跨 request 存活的外部连接（SSH、远程 Docker、长连接 gRPC、持久化 DB 连接池之外的单条长连接、MCP 侧连接等），不得只在启动时 `Dial` 一次就永久缓存。必须同时满足：(a) 启用协议级 keepalive / ping（SSH `keepalive@openssh.com`、gRPC `keepalive.ClientParameters`、TCP `KeepAlive`）；(b) 在使用点检测"连接已死"类错误（EOF / `wsarecv` / `wsasend` / `connection reset` / `broken pipe` / `use of closed network connection`）并按需重拨一次重试；(c) 鉴权 / 握手失败（`handshake failed`、401、bad credentials）**禁止**走自动重连，必须直接冒泡，以免掩盖凭据问题并触发 fail2ban / 账号锁定；(d) 重连入口用互斥锁串行化，避免"连接风暴"。任何"启动时 Dial 一次、永不重连"的长连接方案判违宪。

## 已取消 ctx 路径的持久化写入须使用独立 context（不可协商）

任何在"调用链 ctx 已 `Canceled` / `DeadlineExceeded`"时仍需完成的持久化写入，**必须**使用 `context.WithTimeout(context.Background(), 合理超时)` 重新派生独立 context，而非透传已取消的 ctx。透传已取消 ctx 会使 Redis / Mongo / Docker API 调用立即失败，fallback 保证形同虚设。**适用场景包括但不限于**：(a) graceful shutdown hook 内的状态回写；(b) session 关闭回调、build cancel fallback enqueue；(c) **HTTP handler 内分配了外部资源（容器 / MCP session / DB 锁）的 defer / rollback 闭包**——HTTP client 断连或请求超时会取消 request ctx，所有透传该 ctx 的清理调用将立即失败，导致容器 / 锁等资源泄漏，必须在 defer/rollback 内创建新的独立 context 执行清理。

## 服务初始化顺序约束（shutdownCtx 注入，不可协商）

凡需将服务器根 ctx 作为 `shutdownCtx` 注入到服务组件（如 `coversnapshot.Service`、`coverConsumer` 等）时，**根 ctx 的声明与 `cancel` 注册必须早于所有依赖该 ctx 的组件构造**。禁止以 `context.Background()` 充当 `shutdownCtx` 传入，因为 `context.Background()` 永不取消，会导致"用户主动取消"判断逻辑（`isUserInitiatedCancel()`）对任何 ctx 取消均误判为用户行为，掩盖真实 fallback 路径。典型正确顺序：

```go
// 正确：先声明 shutdownCtx，再构造依赖它的组件
ctx, cancel := context.WithCancel(context.Background())
defer cancel()
// ...
coverSvc := coversnapshot.NewService(..., ctx, ...) // 传入服务器根 ctx 作为 shutdownCtx

// 错误：组件构造早于 ctx 声明，只能传 context.Background()
coverSvc := coversnapshot.NewService(..., context.Background(), ...) // shutdownCtx 永不取消
// ...
ctx, cancel := context.WithCancel(context.Background())
```

**Plan Review 必须核对**：凡 plan 引入 `shutdownCtx` / `serverCtx` 参数的服务构造，必须验证 `ctx` 声明顺序早于所有注入点；若组件构造顺序导致无法注入根 ctx，必须重排构造顺序或改为 `SetShutdownCtx(ctx)` 后置注入，不得以 `context.Background()` 占位。

## 子 goroutine 退出信号化（不可协商）

具有"持有资源"语义的子 goroutine（lease heartbeat、keepalive 探针等）提前退出时，必须通过 closed channel 或 atomic flag 通知调用方；调用方在进入关键操作（网络 IO、DB 写入）前必须 select 该信号。禁止依赖 `defer + hbCancel` 的隐式关闭作为"通知"机制，因为 defer 方向是父->子，不是子->父。典型模式：在 goroutine 函数头部 `defer close(hbDone)`，调用方在写入前做 `select { case <-m.hbDone: return ErrLeaseExpired; default: }`。最小参照实现：
```go
// goroutine 内部（heartbeat / keepalive 等）
func (c *Consumer) runHeartbeat(ctx context.Context) {
    defer close(c.hbDone) // 退出时关闭，通知调用方
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done():
            return
        case <-ticker.C:
            if err := c.renewLease(ctx); err != nil {
                return // 续期失败：退出，调用方通过 hbDone 感知
            }
        }
    }
}

// 调用方（进入写入前先 select）
func (c *Consumer) processItem(ctx context.Context, item Item) error {
    select {
    case <-c.hbDone:
        return ErrLeaseExpired // 租约已失效，拒绝写入
    default:
    }
    return c.repo.Save(ctx, item) // heartbeat 仍活着，可安全写入
}
```

## 生命周期 Cleanup 回退禁令（不可协商）

凡 shutdown / rollback / cleanup 修复与迭代，**禁止**将已建立的完整清理模式回退为简化写法。正确模式为：独立 `context.WithTimeout(context.Background(), ...)` + `Stop()` 后紧跟 `Remove()` + `WaitGroup / done channel` 等待后台 goroutine 退出；简化写法（直接透传调用方 ctx + 只 Stop 不 Remove + 不等待 goroutine 退出）判违宪。**适用场景包括但不限于** `Create()` / `Resume()` / `Close()` / `Suspend()` / `executeBuild()` 等所有生命周期方法的异常分支与回滚路径。Code review 发现 rollback/cleanup 路径由完整模式退化为简化写法，直接判 Critical，不降级处理。

---

> 以下规则从 v0.0.3 多轮 develop-review 反复出现的系统性问题中提取。

## Sentinel Error 比较必须使用 errors.Is()（不可协商）

禁止使用 `==` 比较 sentinel error。必须使用 `errors.Is(err, ErrSomething)`，包括测试代码。原因：一旦 error 被 `fmt.Errorf("%w", ...)` 包装，`==` 比较静默失败，导致错误分支走 fallback 路径而无任何告警。典型正确模式：

```go
// ✅ 正确
if errors.Is(err, repository.ErrUserNotFound) {
    return nil, ErrInvalidCredentials
}

// ❌ 违宪
if err == repository.ErrUserNotFound {
    return nil, ErrInvalidCredentials
}
```

测试中同理，使用 `assert.ErrorIs(t, err, ErrXxx)` 而非 `assert.Equal(t, ErrXxx, err)`。根因：v0.0.3 account Task-04 review 反复标记此问题。

## Error 类型判别与 interface{} 断言必须使用 comma-ok（不可协商）

<!-- Context Repair: v0.0.4 thin-client task-03 H2 — RefreshEventsToken c.Get("user_id").(string) 裸断言 panic；旧规则仅覆盖 err.(CustomType)，未泛化到非 error interface{} -->
禁止对**任何** `interface{}` 值（包括但不限于 `err`、`c.Get(key)`、从 map/slice 取出的值）做裸类型断言——当值为 nil 或非目标类型时会 panic，直接崩溃请求。必须使用以下之一：

1. **errors.As**（仅 error 类型）：`errors.As(err, &target)`
2. **comma-ok 断言**：`v, ok := x.(T); if ok && v != "" { ... }`

**典型违规场景（自动判 High）：**
```go
// ❌ err 裸断言 — panic if not CustomType
customErr := err.(CustomError)

// ❌ c.Get() 裸断言 — panic if user_id 未注入或 JWT 中间件未激活
userID := c.Get("user_id").(string)

// ❌ map value 裸断言
val := someMap["key"].(string)
```

**正确模式：**
```go
// ✅ error 类型：errors.As
var customErr *CustomError
if errors.As(err, &customErr) { ... }

// ✅ c.Get() / map value：comma-ok
uid, ok := c.Get("user_id").(string)
if !ok || uid == "" {
    c.JSON(http.StatusUnauthorized, ...)
    return
}

// ✅ map value：comma-ok
val, ok := someMap["key"].(string)
if !ok { ... }
```

**Ownership check 是最高频触发场景**：handler 中 `c.Get("user_id")` 用于权限校验时，JWT 中间件未激活或 key 不存在均会返回 `(nil, false)`，裸断言必 panic。

根因：v0.0.3 game-server 多次裸断言 panic；v0.0.4 task-03 H2 在 ownership check 路径复现。

## 错误分类先行禁令（不可协商）

<!-- Context Repair: v0.0.4 thin-client task-01 round4 → task-02 → task-03 共 6+ 轮 RECURRING；task-02 CR-2 要求写入但未落地，task-03 升级为 Critical -->
Go handler / service 中，对同一个 `err` 变量，**`logger.Error` 调用必须在所有 `errors.Is` / `errors.As` 语义分类之后**。若某 error 在下方被识别为预期业务条件（`ErrAlreadyExists`、`ErrNotFound`、`ErrUnauthorized` 等），则不得在分类之前调用 `logger.Error`，否则业务正常路径将被记录为系统故障级别日志，违反宪法 §9「业务正常路径记为 Error 视为违宪」。

**禁止模式：**
```go
// ❌ 违宪：logger.Error 先于 errors.Is，幂等正常路径被记为系统故障
if err != nil {
    logger.Error("create session failed", zap.Error(err)) // ← 先于分类
    if errors.Is(err, session.ErrAlreadyExists) {
        return c.JSON(http.StatusOK, gin.H{"idempotent": true})
    }
    return c.JSON(http.StatusInternalServerError, ...)
}
```

**正确模式：**
```go
// ✅ 先分类，再按语义选日志级别
if err != nil {
    if errors.Is(err, session.ErrAlreadyExists) {
        logger.Info("create session: idempotent return", zap.String("user_id", req.UserID))
        return c.JSON(http.StatusOK, gin.H{"idempotent": true})
    }
    logger.Error("create session failed", zap.Error(err)) // 非预期错误才用 Error
    return c.JSON(http.StatusInternalServerError, ...)
}
```

Reviewer 遇到违反此规则时自动升级为 **Critical**，无豁免。

## JSON Tag 完整性（omitempty 规则）

API 响应结构体中，当字段的零值（`""`、`0`、`0001-01-01T00:00:00Z`、`false`）在业务上没有语义含义时，**必须**添加 `omitempty` tag。典型场景：

```go
// ✅ LastLoginAt 未登录时为零值，无语义含义 → omitempty
LastLoginAt time.Time `json:"last_login_at,omitempty" bson:"last_login_at,omitempty"`

// ✅ CreatedAt 始终有值 → 不需要 omitempty
CreatedAt time.Time `json:"created_at" bson:"created_at"`
```

Plan Review 和 Develop Review 必须逐字段检查新增 struct 的 JSON tag 完整性。根因：v0.0.3 account feature 的 `LastLoginAt` 零值问题在 4+ 轮 review 中被反复标记。

## 请求链禁用 context.Background()（不可协商）

Repository / Service / Handler 的请求处理链中，**禁止**使用 `context.Background()`。`context.Background()` 仅允许出现在以下位置：(a) `main()` 启动阶段；(b) 后台 goroutine 入口（消费者、定时任务、心跳）；(c) 已取消 ctx 路径的持久化写入（见上方"已取消 ctx 路径"规则）。在请求链中使用 `context.Background()` 会切断超时传播和取消信号，导致客户端超时后服务端仍在执行，浪费资源。根因：v0.0.3 game-server 多处 repository 层使用 `context.Background()` 导致超时不传播。

## HTTP Server 四超时配置（不可协商）

所有 HTTP server 必须同时配置四个超时参数：`ReadHeaderTimeout`、`ReadTimeout`、`WriteTimeout`、`IdleTimeout`。仅配置 graceful `Shutdown()` **不等于**超时保护。缺失超时会导致 slowloris 攻击和资源耗尽。典型配置：

```go
srv := &http.Server{
    Addr:              ":8080",
    Handler:           router,
    ReadHeaderTimeout: 10 * time.Second,
    ReadTimeout:       30 * time.Second,
    WriteTimeout:      60 * time.Second,
    IdleTimeout:       120 * time.Second,
}
```

接受大文件上传的端点可在具体 handler 中使用 `http.MaxBytesReader()` 另行放宽 ReadTimeout。根因：v0.0.3 game-server 的 HTTP server 只配了 Shutdown 无超时。

## Config.Validate() 必须深度校验（不可协商）

配置的 `Validate()` 方法不得仅检查字段是否为空。必须实际解析和类型转换所有复杂值（`time.ParseDuration`、`strconv.Atoi`、`net.SplitHostPort` 等），将格式错误拦截在启动阶段，不得延迟到运行时才发现。枚举类配置（如 `auth.mode`）必须用 switch 校验所有已知值，未匹配值必须报错，禁止静默 fallback。

```go
// ✅ 正确：启动时就发现 "30min" 不是合法 duration
func (c *Config) Validate() error {
    if _, err := time.ParseDuration(c.JWTExpiry); err != nil {
        return fmt.Errorf("invalid jwt_expiry %q: %w", c.JWTExpiry, err)
    }
    switch c.AuthMode {
    case "jwt", "cli":
        // ok
    default:
        return fmt.Errorf("unknown auth.mode %q, must be 'jwt' or 'cli'", c.AuthMode)
    }
    return nil
}
```

根因：v0.0.3 account Task-01 的 `jwt_expiry` 未在 Validate 中解析，运行时才报格式错误。

## MongoDB 计数更新必须使用原子操作（不可协商）

<!-- Context Repair: aippy-research plan-review C1/H2 反复出现"先查余额/先查记录再更新计数"反模式，属系统性空白 -->
凡 plan 或代码中出现"先 FindOne 查记录 → 再 UpdateOne/Inc 计数"的两步模式，**必须**改为以下之一：

1. **MongoDB 原子 findOneAndUpdate**：使用 `$cond`（存在才更新）或直接 `$inc` + filter 条件，单次操作完成"条件检查 + 计数变更"：
   ```go
   // ✅ Credits 扣除：余额足够才原子扣除
   result := coll.FindOneAndUpdate(ctx,
       bson.M{"_id": userID, "credits": bson.M{"$gte": cost}},
       bson.M{"$inc": bson.M{"credits": -cost}},
   )
   // result.Err() == mongo.ErrNoDocuments → 余额不足

   // ✅ 点赞/收藏：upsert 一步插入 + 外层原子 $inc
   coll.FindOneAndUpdate(ctx,
       bson.M{"userId": uid, "gameId": gid, "action": "like"},
       bson.M{"$setOnInsert": ...},
       options.FindOneAndUpdate().SetUpsert(true),
   )
   ```
2. **显式捕获 duplicate key**：unique 索引冲突（mongo code 11000）必须作为业务正常路径处理（返回"已操作"），不得返回 500。
3. **Service 层分布式锁**：高并发计数场景可用 Redis 分布式锁保护单个 entityId 的并发写入（替代方案，非首选）。

**禁止模式**（判 Critical）：
```go
// ❌ 先查余额再扣除 — 并发下可超额消耗
balance, _ := repo.GetCredits(ctx, userID)
if balance >= cost {
    repo.DeductCredits(ctx, userID, cost) // 两步非原子
}
```

根因：v0.0.3 aippy-research plan-review 中 Credits 扣除（C1）和社交计数（H2）反复出现此反模式；docker-env feature 的 session 计数也有同类遗漏，说明规则未覆盖 MongoDB 层面原子操作要求。

### Plan 阶段计数/聚合字段强制原子声明（计入 Important+）

<!-- Context Repair: aippy-research Round2 H2 → Round3 H-new-2 → Round5 H-R5-2 → Round6 I-R6-2，四次出现同类 [RECURRING]；Round6 将规则范围从"社交计数"扩展至"所有业务聚合统计字段" -->
凡 plan 中出现**任何**计数或聚合统计字段，**对应操作描述必须显式声明 `findOneAndUpdate + $inc`**，禁止仅描述为"计数 +1"或"更新计数"而不指明原子实现方式。

**覆盖范围（不限于此）**：
- 社交互动计数：`likes` / `views` / `comments` / `forks` / `shares` / `remixes`
- 社交关系计数：`followersCount` / `followingCount`（跨文档双向更新须同时声明一致性策略：多文档事务 or 最终一致补偿）
- 业务聚合统计：`ProjectCount` / `CreditsUsed` / 任何以 `Count` / `Total` 结尾的用户/游戏级聚合字段
- Credits 余额变动：必须使用带余额校验的原子 `findOneAndUpdate + $inc`（见上方规则示例）

**跨文档双向计数额外要求**（如 follow 关系同时更新 follower.FollowingCount 和 followee.FollowersCount）：plan 必须二选一声明：
1. MongoDB 多文档事务（`session.WithTransaction`）原子更新双方；
2. 最终一致：保证主方原子更新，副方由后台补偿 goroutine 定期重算；同时在 Plan 验收节追加"并发操作后双方计数与实际记录数一致"断言。

- Plan 遗漏此声明 → plan-review 直接判定 **Important**
- 同一 feature 或跨相邻轮次出现 `[RECURRING]` 标注 → 自动触发 Context Repair，升级为 **Important+**，在下一轮开始前必须将规则落地至 backend.md 并在迭代记录中注明

## Go 模型业务默认值必须在 Repository.Create 显式写入（不可协商）

<!-- Context Repair: aippy-research Round1 H1（BuildStatus）与 Round5 H-R5-1（Level int）相距两个阶段重复同类遗漏 -->
凡 Go 模型字段满足以下任一条件，plan **必须**在对应阶段的数据模型说明中追加"Repository.Create 时显式写入默认值 X"注释，不得依赖 Go 零值或 omitempty 隐式行为：

1. 字段有业务语义默认值且该值**不等于** Go 零值（如 `Level int` 默认 1、`Status string` 默认 `"active"`）；
2. 字段带 `omitempty` tag 但业务上要求新建记录必须含非零初始值。

**违规示例**：
```go
// ❌ omitempty + 业务默认值非零 → 新建用户时 Level 被跳过写入，读取返回 0
Level int `bson:"level,omitempty"`
// 应在 Repository.Create 显式设置: Level: 1
```

**正确模式**：
```go
// Repository.Create
func (r *UserRepository) Create(ctx context.Context, u *model.User) error {
    if u.Level == 0 {
        u.Level = 1 // 显式写入业务默认值，不依赖 omitempty 零值
    }
    _, err := r.coll.InsertOne(ctx, u)
    return err
}
```

plan-review 发现上述注释缺失 → 判定 **Important**。develop-review 发现 Repository.Create 未显式赋值 → 判定 **Important**，不降级。

## 异步队列满载必须传播错误（不可协商）

向 Redis Streams / channel / 内部队列 enqueue 时，如果队列已满或写入失败，**必须**向调用方返回 error，禁止静默 log + 丢弃。调用方有责任决定重试、降级或拒绝请求。静默丢弃导致调用方误判为成功，用户视角"提交成功但无效果"。根因：v0.0.3 game-server 的队列满载路径静默 log 导致任务丢失。
