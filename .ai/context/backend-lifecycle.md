# Backend 生命周期约束

> **作用域：仅 `Backend/` 目录。** 本文件从 `.ai/context/project.md` 拆出，仅在涉及 Backend Session / Container / Shutdown 代码时按需加载。不适用于 `GameServer/`。

## cover-snapshot 持久化生命周期约束（不可协商）

凡依赖 live MCP session 或 container 的持久化路径（如截图、导出、资源写入），必须在释放 `MCPSessionID` / `ContainerID` **之前**完成：

- **禁止"先 close/stop，再异步补 capture"**：session close 或容器 stop 之后，MCP session 和容器内的所有运行态资源（截图、临时文件、内存状态）均不可再访问，任何依赖它们的持久化操作将必然失败。
- **硬约束**：`build_complete` / `session close` / `container stop` 触发的后处理（snapshot 生成、cover 上传等）必须在同一生命周期内完成，或在关闭前明确调度到独立的持久化路径（如 Redis Stream 回填），不得假设关闭后资源仍存活。
- **回填路径例外**：若已有 `Game.ProjectDir` 持久化到 MongoDB，可在 session/container 生命周期外通过 DockerCapturer 新开临时容器执行回填；但此路径必须有独立于原 session 的完整输入（`ProjectDir`），不得依赖已关闭 session 的任何内存字段。

## Session 生命周期约束（不可协商）

### Session 关闭资源释放清单

Session 关闭（`Close()` / `Suspend()`）时必须按序释放以下全部资源，缺少任一步骤均判未完成：

```
1. snapshot save
2. DB status = closed
3. revoke capability token
4. close MCP session
5. stop container
6. release concurrency gate（SREM）
7. release game lock
8. SSE broadcast closed
```

反复出现 `Close()` / `Suspend()` 只处理 MCP + container 而遗漏 lock / gate / capability 的模式是系统性缺陷。Code review 和 plan review 必须逐条核对此清单，禁止以"主路径完成"代替完整清单验收。

> **容器清理约束（不可协商）：** step 5（stop container）必须包含 `containerMgr.Stop()` **紧跟** `containerMgr.Remove()` 两步操作，缺少 Remove 步骤判违宪。推荐封装为 `stopAndRemove` helper 统一调用，确保以下所有出口均通过同一入口清理容器：(1) `Close()` 正常关闭路径；(2) `Suspend()` 容器释放段；(3) `Resume()` MCP 失败 / snapshot 失败 / repo.Update 失败三处回滚；(4) `executeBuild()` 构建完成后容器释放；(5) `Create()` MCP 失败 / repo.Create 失败内联回滚（推荐改为调用 `rollbackResources`，与 `CreateWithOptions` 语义对齐）。仅调用 Stop 而不调用 Remove 会导致容器残留，影响下次同 ID 容器创建。
>
> **`rollbackResources` 复用约束（不可协商）：** `CreateWithOptions()` 的 `rollbackResources` 已实现完整 5 步反向回滚（Stop -> Remove -> revoke capability token -> release lock -> release gate）。`Create()` 的两处内联回滚只做了 Stop（无 Remove、无 gate/lock/capability 释放），行为与 `CreateWithOptions` 不一致，判违宪。必须改为调用 `rollbackResources` 或提取等价 helper，禁止以内联 Stop 代替完整回滚。

> **`Suspend()` 与 `Close()` 的差异（step 3）：** `Suspend()` 同样必须执行 step 6（concurrencyGate.Release）和 step 7（lockRepo.Release），但 step 3（revoke capability token）在 suspend 时**不执行**，保留 token 以供 Resume 使用；step 1（snapshot save）和 step 2（DB status）在 `Suspend()` 中写入 `suspended` 而非 `closed`。

### 服务器级 Shutdown 调用链完整性（不可协商）

`main.go` / 服务入口的 graceful shutdown 路径必须显式调用以下全部步骤，缺少任一步骤均判未完成：

```
1. cancel(serverCtx)                   — 触发所有依赖根 ctx 的组件退出
2. sessionMgr.Shutdown(shutdownCtx)    — 关闭所有活跃 session（含 Close() 完整清单）
3. 等待后台 goroutine 退出信号         — 如 <-done channel 或 WaitGroup.Wait()
4. 其他独立 worker/consumer 关闭       — coverConsumer.Stop() 等
```

- `sessionMgr.Shutdown()` 遗漏是高频缺陷：若 main.go 只 `cancel()` 根 ctx 而不调用 `Shutdown()`，所有活跃 session 的 Close() 完整清单（快照 / DB 状态 / capability revoke / container remove / gate / lock / SSE broadcast）均不执行，导致资源泄漏。
- **`srv.Shutdown()` 报错禁止 Fatalf（不可协商）：** HTTP drain 阶段（`srv.Shutdown()`）失败时禁止以 `log.Fatalf` 退出进程；必须记录错误后继续执行 `sessionMgr.Shutdown()` 和 `wg.Wait()`，否则所有活跃 session 的清单均被跳过。正确模式：`log.Printf(...)` + 继续 `onShutdown(shutdownCtx)`。
- **Shutdown 分阶段独立 ctx（不可协商，task-09 RECURRING 升级）：** `Manager.Shutdown()` 内部的各串行阶段（等待 build goroutine 退出 / ListIdleActiveSessions + Close 逐个 session）禁止复用同一个会被前序步骤耗尽的 timeout budget。正确模式：build-wait 阶段使用调用方传入的 `ctx`；session 枚举 + 关闭阶段必须用 `context.WithTimeout(context.Background(), 30s)` 派生独立 `closeCtx`，即使 build-wait 超时，session 清理也必须继续执行。Plan Review 和 develop-review 必须核对 Shutdown 各阶段 ctx 来源，发现复用同一 `shutdownCtx` 即判 High。
- **WaitGroup / done 信号覆盖范围必须包含组件内部自重启 goroutine（不可协商，task-13/09 RECURRING 升级）：** `main.go` 对 `HealthWatcher.Run()` / `Reconciler.Run()` 等组件仅 `wg.Add(1)` 一次，但这些组件内部若以 `go w.Run(ctx)` 形式自重启，新 goroutine 脱离 WaitGroup 管理，导致 `wg.Wait()` 提前归零（假阳性停机信号）。**强制约束：禁止 Watcher / Manager 内部裸起 `go w.Run(ctx)` 类型的长生命周期自重启 goroutine**；重连 / 重订阅 / channel 关闭后的重试必须在**原 goroutine 的 `for-select` 循环内**通过 break + restart-subscribe 实现，不得 spawn 新 goroutine 接管。develop-log 自检必须逐组件列出内部自启动 goroutine 状态（PASS/FAIL/NA），develop-review 同样须独立核查，不得以"main.go 层面 WaitGroup 已完整"替代此项检查。
- 等待退出信号不可省略：shutdown 返回后，依赖 `shutdownCtx` 的 goroutine 可能仍在执行持久化写入；若进程立即退出会截断写入。必须 block 直至退出信号或超时。
- Plan Review、Code Review **以及 develop-log 每轮自检**必须核对 `main.go` shutdown 路径是否包含上述四步，缺失任一步即判 Critical。凡本轮涉及 Manager / Session / Worker 生命周期组件，develop-log 自检必须显式验证：(1) `Manager.Shutdown()` 实现是否迭代 `Close()` 所有活跃 session（仅调用内部 `shutdownCancel()` 不足）；(2) `main.go` 是否向 `Shutdown()` 传入独立 `shutdownCtx`（或带超时的独立 context），而非仅 `cancel()` 后直接退出。
- **修复"已取消 ctx"时必须全链路扫描（develop-log 自检强制项）：** 凡修复"调用链 ctx 已取消后的持久化写入需改用独立 ctx"问题，禁止只修最明显的单个调用点。必须在 develop-log 自检段落中**逐一列出**同一错误路径上所有 durable write / cleanup 调用点（例：`MarkCoverPending` -> `repo.Update` -> `PersistCover` -> `CloseSession` -> `Stop/Remove`），并确认每个调用点均已切换为独立 ctx；漏修任一前置写入视为修复不完整，判 High。
- **cleanup 路径变更后的 HTTP 状态码回归核查（develop-log 自检强制项）：** 凡本轮修改 session close / build cancel / cleanup 路径中的 Go 代码，develop-log 自检必须额外核对"本轮所触及的每个 HTTP 接口其实际返回状态码是否仍与 plan/api.md 合同一致"——典型回归：`DELETE /sessions/{id}` 在重构 close 路径过程中从 204 无意间改回 200。

### CreateSession initWorkspace 调用时机

`CreateSession`（含 `CreateWithOptions`）的 workspace 初始化（`initWorkspace`）必须在 **session DB persist 和 capability token 颁发之后**调用，严格顺序如下：

```
lock -> container -> MCP session -> DB persist -> capability token issue -> initWorkspace
```

- `initWorkspace` 失败时必须触发完整回滚，且回滚顺序有强制要求：**先**执行 `repo.UpdateStatus(ctx, sessionID, SessionError)`（防止 DB 遗留 `status=active` 的幽灵 session），**再**依次 stop container -> release lock -> release gate。四步缺一均判回滚不完整；仅完成后三步而跳过 DB 状态写入，与 Close/Capability 回滚模式不一致，判违宪。
- 禁止在 DB persist 或 token 颁发之前调用 `initWorkspace`，以防资源泄漏（容器启动但 session 从未入库）。
- plan 和 code review 必须验证 step 6（`initWorkspace`）在流程图中的位置，缺失即判未完成。

### Capability Token 写回一致性约束（不可协商，task-11 C1/H3 RECURRING 升级）

凡任何操作**改变** capability token 的值（`capabilityRepo.Issue`、`capabilityRepo.Refresh`），必须在同一请求内将新 token 通过**字段级原子更新**写回 `Session.EventsCapabilityToken`；**禁止**使用 `repo.Update(ctx, sess)` 全量 `ReplaceOne` 回写整个 session 文档。

**强制要求：**

- `Issue` 成功后：必须调用专用字段级更新方法（如 `UpdateEventsToken`）并附带状态谓词（当前状态须在允许集合内），仅更新 `events_capability_token` / `updated_at`；**禁止** `sess.EventsCapabilityToken = newToken` 后调用 `repo.Update(ctx, sess)` 全量写回——并发 `Close()` / `MarkError()` 已将 session 置为终态时，全量覆写会将旧快照的 `active` 状态整包写回，产生幽灵 session（C1 根因）
- `Refresh` 成功后：`capabilityRepo.Refresh(...)` 返回新 token 后，同样必须使用字段级原子更新写回 session 文档；**禁止**全量 `ReplaceOne`；仅调用 `capabilityRepo.Refresh` 不满足此要求
- `Rehydrate` 路径中若有 token 补发：同上，必须使用字段级原子更新，禁止 `ReplaceOne` 全量覆写
- `Revoke`（session close step 3）：已通过 8 步清单约束，此处不额外要求

**根因（RECURRING，三轮同类缺口）：**

`ErrAlreadyExists` 幂等路径从 `existing.EventsCapabilityToken` 读取 session 快照字段，而非从 `capabilityRepo` 实时查询。若 token 操作后未同步 session 文档，幂等重试将持续返回已吊销 token，导致客户端在恢复路径上必然 401：
- H2（task-11 上轮）：`CreateWithOptions()` 中 `Issue()` 成功后未将 token 持久化回 session 文档
- H3（task-11 本轮，RECURRING）：`RefreshEventsToken` 中 `capabilityRepo.Refresh()` 后未同步 `Session.EventsCapabilityToken`
- C1（task-11 最终报告）：`CreateWithOptions()` 用 `repo.Update()` 全量 `ReplaceOne` 回写 token，并发 `Close()`/`MarkError()` 写入的终态被旧快照覆盖，session 被复活

**Review 检查要点（develop-review 及 plan review 均适用）：**

- 对每个调用 `capabilityRepo.Issue(...)` 或 `capabilityRepo.Refresh(...)` 的函数，确认其后使用**字段级更新**（专用 `UpdateEventsToken` / `UpdateCapabilityToken` 方法，或带状态谓词 filter 的 `$set` 操作），而**非** `repo.Update(ctx, sess)` 全量写回
- 使用 `repo.Update(ctx, sess)` 全量写回 token 变更，判 **High**；若在 create 路径存在并发终态覆写风险，升级 **Critical**（C1 模式）
- 仅更新 capability 仓库而未更新 session 文档，判 **High**；同类问题跨轮 RECURRING 后升级为 **Critical**

### RefreshEventsToken 状态门禁与原子更新约束（不可协商，task-11 C1/C2/H4 RECURRING）

`POST /sessions/:id/events/token/refresh` 具有双层强制约束，违反任一均判 Critical：

**1. 状态门禁（handler 层 + 持久化层双重校验，禁止 TOCTOU 前置读取）**

- 仅允许非终态 session（`active` / `suspended` 等允许态）执行 refresh
- 对 `closed` / `completed` / `error` 等终态必须返回 `409 Conflict`
- 禁止只做 owner 校验而跳过状态校验；handler 层和 repo 层均须独立检查状态
- **TOCTOU 禁止（不可协商）：** 上述状态门禁**不得**仅依赖"先 `Get(id)` 读取 session 状态，再调用 `capabilityRepo.Refresh()` / `UpdateEventsToken()`"的前置读取模式——`Close()` 发生在 `Get()` 之后、写入之前时，前置快照将被绕过，终态 session 仍可获得新 token。`UpdateEventsToken` 和 `capabilityRepo.Refresh()` 的 DB 操作必须**内嵌状态谓词**（如 MongoDB `$set` filter 中携带 `status: {$in: ["active", "suspended"]}`），使 DB 层写入在并发 `Close()` 时原子 miss；CAS miss（0 matched / modified documents）时必须撤销刚签发的新 token 并返回 `409 Conflict`，不得依赖前置快照结论降级处理。
- 理由：`Close()` 按生命周期约定已撤销 token；对终态 session 重签发新 token 会破坏"close 后 token 失效"的安全语义

**2. 原子字段级更新（禁止 Get + ReplaceOne 全量覆写）**

- 回写新 token 必须使用带状态谓词的字段级原子更新：仅更新 `events_capability_token` / `updated_at`，并要求当前状态仍允许 refresh
- 禁止"先 `Get(sessionID)` 取出整个 session，修改字段后 `ReplaceOne` 全量写回"模式
- 理由（C2 根因）：若 refresh 与 `Close()` / rehydrate / 其他 session 更新并发，全量 `ReplaceOne` 会把旧快照的 `status`、`container_id`、`mcp_session_id` 等关键字段整包写回，直接把已关闭 session 复活为 active，产生幽灵指针，违反生命周期 step 3 持久化边界
- 写回失败必须向客户端返回错误，禁止降级为"仅日志 + 返回 200"

**Review 检查要点（develop-review 及 plan review 均适用）：**

| 检查项 | 严重级 |
|--------|--------|
| `RefreshEventsToken` handler / manager 未在 owner 校验之外额外校验 `sess.Status` | High |
| 终态 session 可成功 refresh（无 409 拦截） | Critical |
| 仅在 handler 层通过 `Get()` 做单次前置状态检查，`UpdateEventsToken` / `capabilityRepo.Refresh()` DB 操作不内嵌状态谓词（TOCTOU 窗口可绕过） | Critical |
| 使用 `Get + ReplaceOne` 全量覆写 session 文档 | Critical |
| refresh 回写失败时返回 200 而非错误 | High（跨轮 RECURRING 后升级 Critical）|
| 测试矩阵未覆盖终态拒绝（缺少 `closed`/`completed`/`error` session 的 409 smoke 用例） | High |

> 关联规则：`### Capability Token 写回一致性约束`——token 变更后必须写回 session 文档；本节在其基础上额外要求状态门禁和原子更新模式，两节需同时满足。

## 路由依赖注入完整性约束（不可协商）

`Backend/cmd/api/main.go` 维护两套路由组装路径：`startMockMode`（进程内 fake 依赖）与 `startRealMode`（真实外部服务）。两者均通过 `router.Setup(router.Dependencies{...})` 组装，`Dependencies` 结构体定义在 `Backend/internal/router/router.go`。

**硬约束：**

- 每次向 `Dependencies` 新增字段（handler / repo / config），必须同时在 `startMockMode` 和 `startRealMode` 中注入；任意一处遗漏即判 Critical。
- `startMockMode` 中可选字段（如 `AssetSearch`）可置 `nil`，但**必须在 `Dependencies` 字段注释中显式标注**"mock 模式为 nil（可选）"；没有注释说明的字段默认视为双模式必填。
- Plan / feature 中声明"新建 XxxHandler"时，testing.md 必须有一条覆盖 mock 模式的 smoke 用例，验证该路由在 mock 模式下可达。
- Develop-review 必须对比 `Dependencies` 结构体字段列表 vs `startMockMode` 赋值列表，两者须对齐；遗漏的非 nil 字段即判 Critical。

**触发背景（RECURRING）：** task-12 develop-review M1 指出 `CoverRegenerateHandler` 在 mock 模式遗漏，属于反复出现的同类缺口（`startMockMode` 与 `startRealMode` 之间无编译期强制约束，纯靠人工记忆同步）。
