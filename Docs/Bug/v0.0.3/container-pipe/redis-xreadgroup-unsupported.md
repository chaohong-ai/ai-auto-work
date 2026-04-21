# Bug 分析：Redis 3.x 不支持 XREADGROUP 导致队列消费失败

## Bug 描述

```
ERROR    queue/consumer.go:102    Failed to read from stream    {"stream": "generation_tasks",
"consumer_id": "worker_0", "error": "ERR unknown command 'xreadgroup'"}
```

Consumer 启动后，`XReadGroup` 调用持续返回 `ERR unknown command 'xreadgroup'`，所有任务队列消费完全瘫痪。游戏生成流程无法执行。

## 代码定位

- **涉及文件**: `Backend/internal/queue/consumer.go:91-108`
- **当前行为**: `c.rdb.XReadGroup(...)` 每次调用均返回 `ERR unknown command 'xreadgroup'` 错误。错误被 logger.Error 记录后 `continue`，进入无限重试循环，永远无法消费任何消息。同时 `XGroupCreateMkStream` (line 66) 也必然失败（该命令同样需要 Redis 5.0+），但仅被记录为 Warn 并继续执行。
- **预期行为**: `XReadGroup` 从 Redis Stream 中消费消息并分发给 `processTask` 处理。
- **影响范围**:
  - `Backend/internal/queue/consumer.go` — 消费者完全不可用
  - `Backend/internal/queue/producer.go` — `XAdd` 同样会失败（Redis Streams 命令）
  - 整个游戏生成流程 (POST /api/v1/games → 入队 → 消费 → 生成) 完全瘫痪

## 根本原因

**本机安装的 Redis 版本为 3.0.504**（Windows 古早移植版），而 Redis Streams（包括 XADD、XREADGROUP、XACK 等命令）是 **Redis 5.0**（2018年发布）引入的全新数据结构。Redis 3.x 完全不认识这些命令。

架构文档 (`Docs/Architecture/system-architecture.md:60,401`) 明确要求 **Redis 7.x**，但开发环境实际运行的是 Redis 3.0.504，版本差距跨越 4 个大版本。

## 全链路断点分析

### idea → feature: PASS

feature.json 未涉及 Redis 版本要求（container-pipe 功能关注的是 Docker/TCP 链路，不涉及 Redis 队列），但 queue 模块的 Redis Streams 使用在 v0.1.0-mvp 阶段已存在。

### feature → plan: PASS

container-pipe 的 plan 正确聚焦于 Docker 容器管理和 TCP 连接，Redis 队列不在其 scope 内。plan.json `server_design.queue_consumers` 为空数组，说明此功能不新增队列消费者。

### plan → tasks: PASS

8 个 task 均不涉及 Redis Streams 修改。

### tasks → 代码: N/A（非 container-pipe 产出的代码）

Bug 出现在 `queue/consumer.go`，该文件在 v0.1.0-mvp 阶段已编写，container-pipe 未修改。

### Preflight 检查: MISS

`Backend/internal/config/preflight.go:60-69` 的 `CheckRedis` 仅执行 `PING` 命令验证连通性，**不检查 Redis 版本**。Redis 3.0 完美支持 PING，因此 preflight 通过，但 Streams 命令完全不可用。

> 原文: `if err := rdb.Ping(pingCtx).Err(); err != nil { ... }`

### env-check (v0.0.3): MISS

v0.0.3/env-check 功能聚焦于 MCP/Backend 服务启动和日志创建，未涉及 Redis 版本校验。

### Review 检出: MISS

所有 container-pipe review 报告（task-01 到 task-06）均不涉及 Redis 队列模块。原始 queue 模块的 review（v0.1.0-mvp 阶段）假设了 Redis 5.0+ 环境，未验证实际部署版本。

## 归因结论

**主要原因：环境前提遗漏** — 代码正确假设了 Redis 5.0+ 环境（架构文档明确要求 Redis 7.x），但开发环境实际安装了 Redis 3.0.504。Preflight 检查只验证 Redis 可达性，未验证版本兼容性。

**根因链：**

1. 架构文档要求 Redis 7.x，queue 模块代码基于此正确使用 Redis Streams API
2. 开发环境安装了 Windows 版 Redis 3.0.504（Microsoft 维护的古早移植版，2016年已停更）
3. Preflight `CheckRedis` 仅 PING 不校验版本，启动时未告警
4. 服务成功启动 → Consumer 调用 XREADGROUP → Redis 3.x 返回 "unknown command" → 消费循环空转

**非 container-pipe 产出的 bug**：此 bug 的根源是基础设施版本不匹配，与 container-pipe 功能开发无关。container-pipe 的所有 task 均未触及 Redis 队列模块。

## 修复方案

### 代码修复

**方案 A（推荐）：升级 Redis**

将本机 Redis 升级到 7.x：
- Windows 推荐使用 [Memurai](https://www.memurai.com/) 或通过 WSL2 安装 Redis 7
- 或使用 Docker 运行: `docker run -d --name redis -p 6379:6379 redis:7-alpine`

**方案 B：Preflight 增加 Redis 版本校验**

在 `Backend/internal/config/preflight.go` 的 `CheckRedis` 中增加版本检查：

```go
// 在 PING 成功后检查版本
info, err := rdb.Info(pingCtx, "server").Result()
// 解析 redis_version 字段，检查 major >= 5
// 如果版本 < 5.0，返回 error: "Redis %s detected, minimum 5.0 required for Streams"
```

### 工作流优化建议

1. **Preflight 增加版本校验（防御性）**：即使升级了 Redis，也应在 Preflight 中校验版本 >= 5.0，防止未来环境回退或部署到低版本环境。加入 `result.Failed` 使服务拒绝启动。

2. **Consumer 增加启动自检**：在 `Consumer.Start()` 中，`XGroupCreateMkStream` 失败时应区分 "group already exists"（正常）和 "unknown command"（致命），后者应终止 Consumer 而非无限重试。

3. **开发环境基线文档**：在项目根目录或 `Docs/` 中维护一份开发环境依赖版本清单（Redis >= 7, MongoDB >= 6, Docker >= 24, Go >= 1.22, Node >= 20），CI 和本地 Preflight 共同校验。
