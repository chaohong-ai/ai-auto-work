# 宪法详细规则：测试验收与 Review 硬检查

> 本文件是 `.ai/constitution.md` §4「测试先行」的详细展开，仅在执行 Plan Review / Develop Review / 任务收尾验收时按需加载。
>
> **作用域分层：** 本文件包含通用规则和创作平台专属规则。各节用标签标注：
> - **[通用]** — 适用于所有领域（创作平台 + GameServer）
> - **[创作平台]** — 仅适用于 Backend/ Frontend/ MCP/ Engine/ Tools/，不适用于 GameServer/
>
> GameServer review 时只需关注 [通用] 标签的规则。

## 测试先行（基础原则）[通用]

- 新功能和缺陷修复优先从失败测试开始。
- Go 使用 `testing`，TypeScript 使用 Jest，Python 使用 pytest。
- 新增 HTTP 端点时，必须同时补上路由注册测试和 smoke 测试。（创作平台 Backend 专指 `Backend/tests/smoke/*.hurl`；GameServer 使用各子服务自有测试）
- feature/plan 中声明"新建"或"create"的测试文件，必须在工作区中真实存在，缺失即视为功能未完成。
- 新增的测试层（如 integration、e2e、smoke）必须接入 CI workflow 并实际执行，未接入 CI 同样视为未完成。

## Plan 阶段 HTTP 端点强制 Checklist（不可协商）[创作平台]

<!-- Context Repair: aippy-research plan-review 发现 15+ 端点均未声明路由测试和冒烟测试，属系统性缺口 -->
Plan Review 阶段：凡 plan 文件中新增任何 HTTP 端点，对应的 Phase 子 plan 必须显式包含以下两条 task，缺失任意一条 **plan-review 判定 Critical**：

1. **路由注册测试 task**：`Backend/internal/router/router_test.go` 覆盖本阶段所有新端点（断言路由已注册、方法匹配、鉴权要求正确）
2. **Smoke 测试 task**：`Backend/tests/smoke/aippy-{phase}.hurl` 覆盖所有新端点 happy-path + 未认证路径

此约束也适用于 develop-review：develop 阶段提交代码若缺少上述两类文件，判 Critical（RECURRING）。

## 验收输入真实性前置校验（不可协商，CANNOT_ACCEPT_SCOPE_MISMATCH）

凡执行 acceptance review，必须在读取 `review-input-acceptance.md` 后、开始逐 REQ 审查前，执行以下前置校验：

1. 运行 `git diff --name-only <base>..HEAD`，获取本次提交实际变更文件列表。
2. 将该列表与 `review-input-acceptance.md` 中声明的 Changed Files / Diff --stat 及 feature/plan 声明的实现路径集合做交叉比对。
3. 若目标 diff 未命中 feature/plan 声明的任何功能代码目录（`Backend/`、`MCP/`、`Frontend/`、`Engine/` 等），则**立即**：
   - 在报告总览区标注 `DIFF STALE` / `CANNOT_ACCEPT_SCOPE_MISMATCH`
   - 将所有 REQ 的"代码实现验证"维度一律标为 FAIL，禁止用工作区历史代码替代本次提交证据
   - 报告整体结论直接判定为 `REMEDIATION_NEEDED`，不得有任何 REQ 为 PASS
4. 此规则优先级高于所有"go test / tsc 编译通过"声明——编译通过只证明代码在工作区存在，不证明本次 diff 交付了这些代码。
5. 同类校验也适用于 develop-review：若 `review-input-*.md` 的 Changed Files 与工作区 `git diff --stat` 严重不符，同样禁止依据 review-input 的 diff 段落判断代码质量或标记任务 done。详见 `.ai/context/reviewer-brief.md` §零条目 4、5。

## 自检 PASS 不得替代文件存在性检查（不可协商）
## 自检 PASS 不得替代文件存在性检查（不可协商）[通用]

宣称任何功能或任务完成前，必须对 plan 中声明 `create` / `new` 的文件在工作区逐一执行存在性验证。自检结论禁止依据 develop-log 自述或"上轮 review 报告确认"，必须依据工作区实物与测试文件。任一核对项缺失即判任务未完成，不得标记 PASS 或打 checkpoint。详见 `.claude/rules/context-repair.md`"产物存在性核对"。

> **创作平台附加**：新增 HTTP 端点必须同时核对 router.go 注册 + router_test.go 断言 + `Backend/tests/smoke/*.hurl` 三件套均存在。

## 回归保护（不可协商）[通用]

新增或修改测试不得通过变更既有业务契约来换取通过。触碰会话模式、状态机语义等核心行为的改动，必须重跑并通过既有回归套件（如 workspace/template 双模式测试）。破坏既有模式的测试视为回归失败，不得合入。

## MCP tool 与 Engine 层跨层契约变更测试强制要求（不可协商，task-15 H1 RECURRING）

凡 MCP tool 的行为依赖 Godot RPC 调用或容器内文件系统状态，变更该 tool 的语义（含参数、返回值 `files[]`、文件路径形式、递归/扁平扫描逻辑、文件增删策略等）时，必须同时满足以下三条，缺一判 High（首次）或 Critical（RECURRING）：

1. **Engine 侧回归测试**：在 `Engine/godot/project/test/` 补对应 GUT 用例，直接调用被修改的 GDScript RPC 方法，断言：
   - 方法已在 RPC 注册表（`_rpc_handlers` 或等价结构）中注册。
   - 嵌套/递归文件操作（如 `seed_knowledge_subset` 的多层目录清理）产生正确的文件系统终态。
   - 对外返回的文件路径为约定形式（如绝对路径 `/project/knowledge/...`），不得只断言相对路径或仅检查列表非空。

2. **MCP 层 mock 契约对齐**：对应的 `.test.ts` mock 断言中的 `files[]` 路径必须与 Engine 侧约定形式一致（如改为绝对路径后，mock 期望也必须更新）；禁止 mock 仍沿用旧形式（相对路径、不同前缀），否则 Jest 通过但 Engine 回归失效属无效验收。

3. **容器级集成测试**：在 `MCP/tests/integration/` 或 plan 声明的对应目录落地真实容器集成测试文件，至少执行一次完整 RPC 调用并断言：最终落地到容器文件系统的文件集合与对外返回的 `files[]` 契约一致。该测试须能在真实 Docker 容器内执行，不得以同进程内存 fake 替代。

**根因（task-15 H1 RECURRING）**：工具层 Jest 仅覆盖 MCP 侧 mock 路径，对 Engine GDScript 执行语义无感知；GUT 用例集声明"覆盖 8 个 RPC 方法"但未显式枚举 `seed_knowledge_subset`，导致该方法的修复点（递归删除、绝对路径返回）无守护，Engine 侧任意回退 Jest 不会报警。

## 验收条件硬断言

当需求文档包含 REQ + 验收条件时，测试必须在测试名或注释中逐条映射验收条件。feature 中声明的 HTTP 状态码（201/202/401/409 等）必须使用精确断言，禁止使用 `HTTP *` 等通配符。JWT 保护的接口在 smoke/E2E 中必须携带 `Authorization` 头。验收条件未被硬断言覆盖的，任务不得标记完成。

## Capability Token 刷新并发与恢复测试强制要求（不可协商，task-11 C1/H1 RECURRING）

凡实现或修改 `RefreshEventsToken` / `UpdateEventsToken` / `capabilityRepo.Refresh()` 相关路径，测试矩阵必须包含以下两条硬性用例，缺一判 High（首次）或 Critical（RECURRING）：

1. **Close 与 Refresh 并发交错（TOCTOU 终态隔离）**：模拟 `Close()` 发生在 refresh 路径的 `Get()` 快照读取之后、`capabilityRepo.Refresh()` / `UpdateEventsToken()` 写入之前（TOCTOU 窗口），断言：终态 session 不得获得新的 capability token；DB 中 session 状态必须仍为 `closed`，不得被复活为 `active`；刷新请求必须返回 `409 Conflict`。此用例必须通过 DB 层状态谓词 mock 或并发 goroutine 注入实现，不得以"handler 内有前置状态检查"替代。
2. **持久化失败后仍保有可用 token（恢复语义）**：模拟 `capabilityRepo.Refresh()` 成功颁发新 token 后 `UpdateEventsToken()` 失败，断言：session 文档中仍保有**至少一个可用 token**（旧 token 或新 token，任一即可），SSE 连接不得因无可用 token 被强制断流；**禁止**测试用例断言"所有 token 应被撤销"——该断言将坏状态（无可用 token）固化为合法回归基线，掩盖后续 H1 类实现缺陷。

## 异步 / 最终一致性验收（不可协商）
## 验收条件硬断言 [通用]

当需求文档包含 REQ + 验收条件时，测试必须在测试名或注释中逐条映射验收条件。feature 中声明的 HTTP 状态码（201/202/401/409 等）必须使用精确断言，禁止使用 `HTTP *` 等通配符。JWT 保护的接口在 smoke/E2E 中必须携带 `Authorization` 头。验收条件未被硬断言覆盖的，任务不得标记完成。

## 异步 / 最终一致性验收（不可协商）[创作平台]

凡涉及异步回写、后台任务、最终一致性、队列消费、定时重试、backfill 的 feature，测试必须满足：
1. **绑定本次测试新建的实体 ID**（`game_id` / `session_id` / `task_id` 等），禁止通过"列表首项"或全局排序采样判断成功。
2. **轮询等待确定性完成信号**——目标字段从空翻转为非空、状态机到达终态、可查询的任务状态、可观测的持久化事件等。信号必须来自持久化数据源或可重放事件，不得依赖单进程内存态。
3. **对外部产出做真实可达性校验**——例如"浏览器可直接访问的 URL"必须执行真实 GET/HEAD 或 `<img>` 加载断言，不得只做 URL 正则匹配、白名单字符串检查或人工 diff。
4. **必须覆盖幂等与并发场景**——同一实体重复触发、并发在线任务与 backfill、进程重启后恢复，不得产生双写、孤儿对象或 last-write-wins 覆盖。
5. **硬性上限：** feature 中声明"超过 N 秒转异步"的路径，必须显式评估是否接入 Redis Streams；选择进程内 goroutine 需在方案里论证跨进程可恢复性，否则视为违宪。

## Plan Review 补充硬检查（不可协商，计入 Critical）[创作平台]

> 以下六项针对创作平台（Backend/ Frontend/ MCP/ Engine/）的 Plan Review。GameServer 的 plan review 不适用这些检查项。

以下六项是对 `.claude/rules/context-repair.md`"Plan Review 硬检查清单"的跨 agent 强制扩展，Claude / Codex / 其他 reviewer 均必须执行：

### 1. 首次 durable write crash 窗口测试

凡涉及锁 / 容器 / 外部 session / reservation / 并发计数的创建流程，plan 与测试矩阵必须显式枚举"首次权威持久化写入（例如 `InsertSession` 或首次 Mongo/Redis Stream 写入）之前" Backend `kill -9` / Pod 驱逐 / 滚动重启的场景，并断言：不残留可写容器、不残留悬空锁或 `active_session_id`、并发计数 / reservation 能恢复到与真实资源一致的值。仅覆盖"每步返回 error 后回滚"或"首次写入之后 kill 容器"都不算通过，不得自评"跨进程可恢复 PASS"。

### 2. 子文档合同一致性（API x Client x Server x Testing）

所有新增状态码（2xx / 401 / 403 / 404 / 409 / 500）、响应字段 / DTO（含 SSE capability token 等）、浏览器原生鉴权替代方案、前端完成条件（例如首屏进入条件是 `workspace.initialized` 还是 `knowledge.seeded`）必须在 `plan/api.md`、`plan/client.md`、`plan/server.md`、`plan/testing.md` 四处逐项对齐；任一子文档缺失或互相冲突即判 Critical，不得以"各子文档自洽"为由标 PASS。负向用例（无 token / 过期 / 错 session / 撤销后 / 失败分支）必须在 testing 中显式存在。

### 3. 列表 / 集合接口的实体 ID 定位验收

凡 plan 引入列表 / 集合 / 搜索 / 分页 / 排行类接口（`GET /games`、`GET /assets`、`GET /sessions` 等），testing.md 必须至少有一条 smoke / E2E 用例通过**本次测试新建的实体 ID** 在返回列表中检索并定位目标项；禁止用"列表首项"、全局排序采样、长度 > 0、字符串包含等作为验收信号。单点接口的 ID 绑定不足以覆盖本条。

### 4. API 文档声明状态码与测试映射表

plan 的 `api.md` / 接口章节中显式声明的**每一个** HTTP 状态码（200 / 201 / 202 / 204 / 400 / 401 / 403 / 404 / 409 / 422 / 429 / 500 / 503 等），必须在 `testing.md` 或 feature 测试矩阵中有**逐条映射**的用例，且断言精确状态码（禁用 `HTTP *` 通配符）。映射表需同时覆盖正向 2xx 路径和每一条负向路径（鉴权缺失 / 鉴权失败 / 资源不存在 / 业务冲突 / 参数非法 / 限流 / 下游故障）；声明 5 个状态码但测试只覆盖 3 个即判 Critical。

### 5. 鉴权能力存在性核验（禁止假设 RBAC / admin）

凡 plan 引用 `admin` / `role` / `claims.Role` / `RequireAdmin` / `isAdmin(...)` / `c.Get("claims")` / admin-only group 等鉴权能力，reviewer 必须在仓库中逐项核对：`Backend/internal/router/middleware.go` 的 `Claims` 是否含 `Role`；`Backend/internal/model/user.go` 的 `User` 是否含 `role`；`Backend/internal/router/router.go` 是否有 admin group / `RequireAdmin()`。任一项缺失即判 Critical，plan 必须二选一补救：(a) 把 RBAC 三件套（Claims.Role / User schema 迁移 / middleware + router wiring）作为本 feature 的**前置基础设施任务**并补齐相应测试；(b) 彻底改为"仅资源 owner 的受保护端点"或"CLI / ops one-off cmd"，从 plan 中删除 admin HTTP endpoint 设计。违反本条会直接导致声明的 `401 / 403 / 404 / 409` 状态码合同无实现基础。详见 `.ai/context/project.md`"认证与授权模型现状（无 RBAC）"。

### 6. `Game` 领域模型落点单一性（禁止跨两套模型改）

仓库中存在两套 `Game` 实现——`internal/model.Game` + `internal/repository.GameRepository`（对外 REST `/api/v1/games/*` 的**权威链路**）与 `internal/game.Game` + `game.GameRepository`（仅 session 内部业务 / ExportHandler 的内部模块）。凡 plan 涉及 `Game` 字段新增（screenshot_url / cover_status / cover_attempt_count 等）、索引变更、repo 扩展，必须显式声明落点并在 `plan.md` / `plan/server.md` / `plan/testing.md` / 文件清单中**只指向一套**。出现"server.md 改 `internal/game/model.go`、文件清单同时列 `internal/repository/game_repo.go`"这类跨两套模型的设计 = Critical，视为落点不确定。额外硬断言：凡 plan 声称"handler 读取字段"时，该字段必须位于 `repository.GameRepository` 返回的 `*model.Game` 上，而不是 `game.Game`。详见 `.ai/context/project.md`"Game 领域模型边界（权威 REST 模型 vs 内部业务模块）"。

### 7. API 响应示例字段类型一致性（不可协商）

<!-- Context Repair: aippy-research Round5 H-R5-3 — buildStatus/publishStatus int→string 改完后，响应示例仍留整数字面量 -->
凡 plan 对任何 Go struct 字段的类型做了变更（如 `int` → `string` 枚举、`bool` → `string` 状态码），**同一 plan 文件中所有 API 响应示例 JSON 内的对应字段必须同步更新为新类型的合法字面量**。示例类型落后于模型声明 → plan-review 判定 **Important**，属于协议文档级错误。

验证方式：plan-review 时逐端点对比 API 响应示例 JSON 字段类型与 Go struct tag / 枚举声明；不一致即触发本条。

### 附加统一约束

`feature.md` 必须与 `plan/api.md` / `plan/testing.md` / `plan/flow.md` 当前事实同步（REQ 描述、验收断言、URL 命名、payload 形态、是否新增 HTTP 入口）；凡本轮已修正的合同若仍残留在 `feature.md`，即判 Critical，必须先同步 feature.md 再进入开发。**plan 迭代内同步时机（不可协商）：** 每轮 plan 修正状态码合同（如 422 细化、新增 409/500 变体等）后，下一轮 develop 阶段开始前必须先更新 `feature.md` 中对应 REQ 的验收断言；plan-review 的 Critical 清单中若含"状态码合同变更"条目，即触发 feature.md 同步义务，不得等到所有迭代结束后才一次性补同步。同时 `plan.md` 摘要 / 数据模型表与 `plan/server.md` 伪码中的同一 payload / 事件名 / repo 路径只保留一版，禁止新旧合同并存。

## 崩溃窗口测试实现质量核验（不可协商）[创作平台]

"测试文件存在"不等于"验收条件真实覆盖"。凡 plan 要求"kill -9 / 进程重启 / Pod 驱逐"场景的崩溃窗口测试，develop-review 必须核查测试文件内容，确认包含以下之一：(a) **真实子进程**——启动独立 Backend 进程，通过 `os.Process.Kill()` 或等价系统调用终止，然后重启并验证恢复；(b) **外部 kill 命令**——`docker kill --signal SIGKILL` 或等价 shell 命令；(c) **CI docker-in-docker job**——`.github/workflows/test.yml` 中有对应独立 job。以下实现**视为验收不通过**，不得打 checkpoint：(1) `repo.Create` / 任何 mock/fake 返回 error 的同进程模拟；(2) 仅 `in-memory fake error` 替代真实崩溃；(3) 仅覆盖"每步返回 error 后同进程回滚"而无真实进程终止。根因：同进程模拟无法覆盖 `rollback()` 来不及执行、Reconciler 自愈、goroutine WaitGroup 假阳性归零等真实 kill 场景（task-07 H9 RECURRING 触发）。

## Develop 收尾产物存在性核验（不可协商，计入 Critical）

任务标记 Done 之前，以及 develop-review 的产物完整性审查中，必须执行以下检查；任一未通过即判 Critical，不得以"后续 task 补充"或"out of scope"降级处理：

### 通用检查（所有领域）
1. **Plan 文件存在性**：从 `plan.md` + `plan/*.md` 提取所有标注 `create` / 新建 / 新增的目标文件路径，用 Glob 逐一核实工作区中真实存在；缺失任意文件 -> 任务不得标记 Done。

### 创作平台附加检查（不适用于 GameServer）
2. **路由注册核验**：plan 声明的每个新增 HTTP 端点，必须在 `Backend/internal/router/router_test.go` 有对应路由注册测试且在 `Backend/tests/smoke/` 有对应 `.hurl` 冒烟文件；缺失任一项 -> Critical。
3. **CI workflow 存在性**：plan / feature.md 中"接入 CI"的表述必须指向 `.github/workflows/` 下**真实存在**的 workflow 文件（主测试入口为 `test.yml`，仓库中**不存在** `ci.yml`）；声明接入 CI 但不指向真实存在的 workflow job -> Critical，禁止以通配符 `*.hurl` 执行代替 job 级存在性验证。
4. **main.go 组件注入核验（不可协商）**：凡当轮新增 Repository / Service / Manager 组件，必须搜索 `Backend/cmd/api/main.go` 确认已注入或有明确 TODO 标注；遗漏注入视为功能不完整，不得标记 Done。此项适用于 develop-log 每轮自检与 develop-review 产物审查，缺失注入即判 Critical。

---

> 以下规则从 v0.0.3 多轮 develop-review / plan-review 反复出现的流程性问题中提取。

## Plan 文件路径预检（不可协商）[通用]

开发阶段开始前，必须对 plan.md 及 plan/*.md 中所有标注 `modify` / `update` 的文件路径执行文件系统存在性检查。路径不存在的必须在开发开始前修正 plan，不得在开发过程中"语义等价替换"（如 `game_handler.go` 等价 `game.go`）。路径一致性是字面的，不是语义的。根因：v0.0.3 多个 feature 的 plan 引用了不存在的文件名，开发者在实现时猜测等价文件导致混乱和返工。

## 路由测试必须使用生产路由装配（不可协商）[创作平台]

`router_test.go` 中的路由注册测试必须调用生产环境的 `setupRouter()` / `Init()` 函数，**禁止**手工拼装 mux + 手动注册路由。手工拼装无法捕获遗漏的中间件、错误的路由组、缺失的路由注册。典型模式：

```go
// ✅ 正确：使用生产路由
func TestRoutes(t *testing.T) {
    r := router.SetupRouter(deps)
    // 断言路由存在
}

// ❌ 违宪：手工拼装
func TestRoutes(t *testing.T) {
    r := gin.New()
    r.GET("/api/v1/users", handler.GetUsers) // 手工注册
}
```

根因：v0.0.3 account / game-server 多处路由测试使用手工 mux，导致实际路由缺失却测试通过。

## 回归命令必须实际执行并留证据（不可协商）[通用]

plan/testing.md 中声明的回归验证命令（`make test`、`make build`、`go vet ./...` 等），必须在**迭代记录或命令执行证据**中保留实际执行的命令和结果摘要（PASS/FAIL + 关键输出行）。证据载体不限于特定文件格式——develop-log.md、CI 日志、终端输出截取均可——但必须可追溯。仅声明"已执行"或"PASS"而无输出证据视为未执行。如果全局命令（如 `make build`）失败，**禁止**替换为子集命令（如只跑 `make proto-gen`）并宣称验收通过——必须修复全局构建或将 feature 状态降级为"partial"。根因：v0.0.3 多处 plan 声明了 `make test` / `make proto-gen` 但迭代记录标 PASS 却无执行证据，实际存在构建失败。

## 协议/传输层修复必须包含负向测试（不可协商）[通用]

修复协议 / 传输层 bug（TCP 帧解析、WebSocket 消息、gRPC 流）时，修复轮次必须同时添加对应的负向测试用例——超时、短写、非法帧、连接中断等。仅修复 happy path 并通过正向测试不足以判定修复完成。根因：v0.0.3 game-server 传输层修复只覆盖 happy path，review 标记的负向场景始终未补测试。

## 常量 / 边界值必须有 go test 断言（不可协商）[通用]

涉及精确常量（帧魔数、消息长度上限、枚举值、协议版本号等）或边界条件的任务，**不得**仅以 `go build` / `go vet` 通过作为验收。必须在 `_test.go` 中对字面值和边界输入做断言。编译通过只证明类型正确，不证明值正确。根因：v0.0.3 game-server 的协议常量仅通过编译验证，实际值错误到 review 才发现。

## 基础设施任务完成必须包含消费者验证（不可协商）[通用]

修改 `go.mod` / `go.work` / Makefile / 代码生成入口等基础设施时，完成标准**不是**子模块自身编译通过，而是**至少一个真实消费者包**（如 `./servers/account_server/...`）编译通过。子模块通过但消费者失败 = 任务未完成。根因：v0.0.3 多处基础设施修改声称完成，但实际消费者编译失败。
