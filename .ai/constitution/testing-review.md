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

## Plan 强制测试文件在 develop 阶段必须落地或拆任务（不可协商，task-11 H3 RECURRING 触发）[通用]

凡 plan.md / plan/*.md 或 feature.md 中被标注为 `[强制]` / `[必选]` / `[迭代 N 修复]` 的新增测试文件（如 `snapshot_sync_test.go`、`TestSnapshotBroadcast_MultiEntity` 等具名用例），develop 阶段必须二选一，缺一判 High（首次）或 Critical（RECURRING）：

1. **本轮 develop 产物落地**：对应 `_test.go` / `.test.ts` / `.hurl` 文件在本轮 `git diff --stat` 中出现，且覆盖 plan 声明的具名用例；编译通过 + `go test` / `jest` / `hurl` 实际执行并全绿。禁止以"下游包测试 14/14 passed"等跨包成绩冒充本包测试产物——develop-review 必须回溯测试产物是否属于本任务声明的目录（如 `GameServer/servers/room_server/internal/game_net/`）。
2. **显式拆分为独立任务**：若本轮因依赖未就绪（Map 未接入 / repo 未建 / mock fixture 缺失）无法交付测试，必须在 `tasks/` 下新建独立任务号（如 `task-XX-tests.md`）并在 plan 迭代记录中显式声明"测试文件已拆分到 task-XX"；拆分任务需包含验收条件与预期交付轮次，否则按未拆分处理。

**develop-review 硬检查：** 对 plan 中 `[强制]` 标注的测试文件执行"plan 文件清单 vs 工作区产物"机械核验——缺失且无拆分任务 → 直接判 High/Critical，不得以"功能代码已实现"降级为 Medium。

**跨包测试冒充的机械核验（task-11 C1 RECURRING 触发）：** develop-review 阶段必须执行 `ls <task 声明目录>/*_test.go`（或 `git diff --stat HEAD | grep "<task 声明目录>.*_test.go"`）。命中 0 个文件即等同"本包零测试产物"——review-input 中任何聚合测试计数（"N/N passed"、"14/14 passed"）对本 task **不构成交付证据**，一律视同 H3/C1 STILL-PRESENT，按 RECURRING 规则判 Critical。**auto-work 生成侧附加硬要求**：`review-input-develop.md` 的 `Test Results Summary` 段落必须同步标注"本包测试数 / 总测试数"（格式建议 `game_net_tests: 0/0 | repo_total: 14/14`），缺失即视同输入不完整，按 reviewer-brief §零-B 第 5 条阻断审查。

**根因**：task-11 的 plan 迭代3 H6 明确要求 `snapshot_sync_test.go` 落地三条具名用例，develop 阶段仅交付实现代码并在 review-input 引用跨包测试数据伪造验收，导致核心回归（frame_id 单调性 / 未握手 Session 过滤 / 多 Entity 序列化）无守护。允许"下轮补"会持续掩盖"测试先行"宪法 §4 被绕过的事实。

## Plan 引用的 API / 方法必须存在（不可协商，task-11 CR-2 触发）[通用]

Plan 中所有显式命名的 API / 方法（形如 `X.Y()` / `pkg.Func` / `Map.Post()` / `Registry.All()` 等）**必须**在 plan-review 阶段由 reviewer 通过 `grep` 在代码库中确认真实存在；若尚未实现，plan 必须在同文件内声明对应的**前置任务 + 预期实现位置**（如 `task-XX 新增 Actor.Post(func())` 并阻塞本任务）。

**plan-review 硬检查：**
1. 从 plan.md / plan/*.md / task-*.md 验证标准中抽取所有被当作硬约束使用的方法名（匹配 `\.[A-Z][a-zA-Z]+\(` 或 `[A-Z][a-zA-Z]+\.[A-Z][a-zA-Z]+\(`）；
2. 对每个方法执行 `grep -rn "func.*<Name>\|type.*<Recv>" <目标目录>`；
3. 无命中且无前置任务声明 → 判 plan-review **Important**，不得进入 develop 阶段。

**develop-review 相应核验：** 若发现本轮实现以 `WARNING` / `TODO` 形式搁置的"原本应经由 X.Y 派发"的路径，必须回溯 plan：是 developer 违反 plan，还是 plan 引用了虚构 API？后者须补 CR 指回 plan-review 链路，不得仅追究 developer。

**根因（task-11 CR-2）**：task-11 plan §5 与验证标准以 `Map.Post()` 作为硬约束，但 `GameServer/common/actor/actor.go` 的 Actor 接口只有 `Send` / `SendWithResult` / `SendWithResultTimeout`，`Map.Post` 不存在；plan-review 放行"虚构 API"导致 developer 只能以"保留 WARNING 注释"的方式形式合规，reviewer 很难判定是 developer 偷懒还是 plan 无法落地。修复方向为在 plan-review 阶段对每个引用的 API 执行存在性 grep。

## Task verify_commands 必须覆盖 plan 可自动化验证条目（不可协商，task-11 CR-3 / task-12 CR-2 触发）[通用]

凡 plan 声明 `[强制]` / `[必选]` 测试文件的任务，其 `tasks/task-NN.md` 的 `verify_commands` **必须**满足以下全部条件：

1. **测试执行命令对齐语言栈**：Go 任务必须包含 `go test -race -count=1 ./<目标目录>/...`；TypeScript 必须包含 `jest --testPathPattern '<目标目录>'`；HTTP 冒烟必须包含 `hurl <目标 .hurl>`。仅 `go build` / `tsc --noEmit` 不构成测试验证，视为未覆盖。
2. **覆盖 plan 验证标准中可自动化条目**：plan 中验证标准若涉及 frame_id 单调性 / 状态过滤 / 错误路径 / 边界值 / TOCTOU 等可断言行为，至少要有一条 verify 命令跑到对应测试用例。task.md 作者须在 verify_commands 上方的注释中列出"本任务验收对应 plan 验证标准 A / B / C 共 N 条，由 `go test ...` 覆盖"。
3. **task-guardian 交叉比对**：扫描 `verify_commands` 时对"plan 强制测试文件 vs task verify 命令"做机械比对——plan 要求测试文件但 `verify_commands` 不含 `go test` / `jest` / `hurl` 即视同 H3/C1 STILL-PRESENT，直接判 Critical。

### 高风险任务自动识别（task-12 CR-2 触发，即使 plan 未标注 `[强制]`）

即使 plan 未显式标注 `[强制]` / `[必选]` 测试文件，只要 task 目标命中以下任一**高风险特征**，`verify_commands` 同样必须包含 `go test -race -count=1 ./<目标目录>/...`（或语言栈等价命令）+ 至少一条并发 / 超时 / 状态机测试用例，仅 `go build` 不构成验收：

- 后台定时 goroutine（含 `ticker` / `time.After` / cleanup loop / heartbeat reaper）
- CAS 状态机（`CompareAndSwap*` / 原子状态切换）
- timeout / deadline 触发的生命周期清理（session cleanup、entity 清理、资源回收）
- channel close 协议（sender-receiver、done chan、broadcast 前的关闭状态判定）
- 对多订阅者的 broadcast / 通知路径

### Task scope 本身为测试文件的强制 verify 规则（task-13 CR-1 触发）

当 `tasks/task-NN.md` 本身满足以下任一条件时，`verify_commands` **必须**直接运行对应测试，仅 `go vet` / `go build` / `tsc --noEmit` 视同"只检查语法不跑测试"，直接判 Critical（RECURRING）：

1. 任务的 `新增` / `modify` 范围主要是 `_test.go` / `*.test.ts` / `*.test.tsx` / `.hurl` 文件（即任务本体就是补测试）；
2. `验证标准` 段落显式列出具名用例（如 `TestHandshake_Success` / `TestEntityEnter_InvalidType_ReturnsError` / `describe(` / `test(` / `GET .+ HTTP/1.1`）；
3. 任务名或描述含 "单元测试" / "unit test" / "补测试" / "测试覆盖"。

**必须落地的命令**（按语言栈）：
- Go：`go test -count=1 ./<目标目录>/...` 或 `go test -run '<TestName>' ./<目标目录>`
- TypeScript：`jest --testPathPattern '<目标目录>'`
- HTTP 冒烟：`hurl <目标 .hurl>`

如命中并发 / 生命周期特征（见上一小节），须同时追加 `-race` 或降级并发压力测试替代。

**根因（task-13 CR-1）**：task-13 的 scope 就是新增 `frame_handler_test.go`、验证标准列出了 `TestHandshake_*` / `TestEntityEnter_*` / `TestSessionClose_*` 五条具名用例，但 `verify_commands` 只有 `go vet`——若 auto-work 按 verify_commands 推进，这些测试会在 review 时根本没被执行。既有「plan `[强制]`」触发规则依赖 plan 显式标注，但"task 本身就是测试"已是不可协商的触发条件，不能等 plan 标记。

**auto-work 生成侧门禁**：develop-review 入口前，`auto-work` 必须对当前 task 执行关键字扫描（task-NN.md 标题 / 描述 / verify_commands / 变更文件列表匹配上述特征）；命中但 verify_commands 仅 `go build` / `go vet` 即视同 C2 / CR-1 STILL-PRESENT，**阻断进入 reviewer 阶段**，回退至 develop 阶段修正 task 文件并补测试。此门禁属 Triple-Check Gate 机械判定，不得依赖 reviewer 事后识别。

**并发测试替代方案（`-race` 不可用时）**：Go 工具链未启用 cgo 导致 `go test -race` 返回 `-race requires cgo` 时，允许改用"并发压力测试"替代——但必须在 `verify_commands` 注释中显式记录降级原因（`# -race unavailable: CGO_ENABLED=0, using N-goroutine stress test as fallback`）并在测试用例中通过 `sync.WaitGroup` + `t.Parallel()` 启动 ≥ 100 并发 goroutine 触发目标路径。禁止以"当前环境不支持"为由跳过并发验证。

**根因（task-11 CR-3）**：`task-11.md` verify_commands 仅 `cd GameServer && go build ./...`，无法验证 plan §5 声明的 5 条验证标准。结果即使 plan 声明 `[强制]` 测试，task-guardian 扫不到测试调用也无法机械阻断，Critical 级门禁形同虚设。

**根因（task-12 CR-2）**：task-11 已沉淀 "verify_commands 必须覆盖自动化验证条目" 规则，但 task-12 仍以 `go build` 作为唯一 verify_command——因为该 task 的 plan 未显式标注 `[强制]` 测试文件，原规则不触发。实际上 task-12 核心目标即 "定时 goroutine + CAS + 生命周期清理 + reason=1 广播"，本身就是不可协商的高风险特征；规则需从"plan 声明驱动"扩展为"task 特征驱动"，由 auto-work 在生成侧机械扫描关键字触发门禁。

## review-input diff 段落必须覆盖未跟踪核心产物与 task scope（不可协商，task-13 CR-2 触发）[通用]

`review-input-develop.md` / `review-input-acceptance.md` 的 `## Git Diff --stat` 与 `## Changed Files` 段落**必须**反映本轮 task 的真实产物全集，不得遗漏未跟踪文件（`git status --short` 中的 `??`），也不得夹带上一 task 的历史 diff。生成侧与 reviewer 侧同时承担以下责任：

1. **生成侧必须三源采集**：auto-work / 其他脚本生成 review-input 时，不得只用 `git diff --stat` / `git diff --name-only`，必须**同时**采集 `git status --short` 中的未跟踪文件（`??`）并并入 `## Changed Files` 段。单独使用 `git diff` 会漏掉"本轮新增但尚未 `git add`"的核心测试文件（如 `frame_handler_test.go`）。
2. **生成侧必须做 scope 交集校验**：生成完毕后对照当前 `task-NN.md` 的 `新增` / `modify` 清单，确认 `Changed Files` 与 task 声明的核心产物**至少有一个交集**。交集为空 → 视为输入生成失败，**不得写盘并进入 reviewer 阶段**，回退至 develop 阶段补 commit 或修复 task 声明。
3. **生成侧必须阻断跨 task 污染**：若 `Changed Files` 中出现上一 task（task-(N-1)）的核心实现文件且当前 task 的核心文件缺位，视为 diff 跨 task 污染 → 同样回退重新生成，不得以"文件顺带改到"为由放行。
4. **reviewer 侧兜底**：reviewer 遇到上述任一情形仍要按 `.ai/context/reviewer-brief.md` §零-B 第 4 / 5 条处置（`⚠️ diff stale` 或 `REVIEW_BLOCKED: INPUT_INCOMPLETE`），不得因"生成侧本应过滤"而降级。

**根因（task-13 CR-2）**：task-13 的核心产物 `frame_handler_test.go` 是未跟踪文件（`git status --short` 显示 `??`），但 review-input 只采集 `git diff --stat`，导致该文件完全不出现在 Changed Files；同时 `Changed Files` 仍保留 task-11/12 的 `snapshot_sync*` diff，本轮新产物缺位却有旧 diff 冒充交付。reviewer 即使按 §零-B 第 4 条发现 `diff stale` 也只能兜底处理，系统性的正确修复是生成侧在写盘前就拒绝这种输入。

**与 `.claude/commands/auto-work.md` 的关系**：auto-work 阶段四 `review-input-develop.md` 生成流程必须镜像本规则为机械门禁（三源采集 + 交集校验 + 跨 task 污染阻断）。本规则为权威语义来源，auto-work 未落地时 reviewer 侧仍须兜底。

## Developer 侧预检清单（不可协商，task-11 CR-1 触发）[通用]

develop 执行单元（claude -p 子进程 / Agent）在提交代码前，**必须**执行以下预检，任一缺失即视同 develop 未启动，不得标记任务完成：

1. **回溯消费最新 Context Repairs**：读取当前 feature 的 `Docs/Version/<ver>/<feature>/develop-review-report-*.md`（取最新版）的 `## Context Repairs` 段；对每条 CR 的"目标文件"生成一行 `已读取 <文件路径>，本轮产物中已规避 <规则名>` 的 ack 日志，写入 `develop-log.md` 或 `develop-iteration-log-task-NN.md`。缺 ack 不得进入 review。
2. **协议字段类型扫描**：对本轮新增或修改的 `.go` 文件执行 `grep -n "strconv\.Itoa(int(\|fmt\.Sprintf(\"%d\"" <file>`；任何命中必须回溯对应 proto 字段类型（见 `.ai/context/reviewer-brief.md` 高频审查盲区第 7 条）——字段类型为 `string` 即视为 H2 重现，须改为显式 `map[EnumType]string` 映射后再提交。
3. **测试产物存在性自检**：对 plan 中 `[强制]` / `[必选]` 测试文件执行 `ls <task 声明目录>/*_test.go`（或等效 glob）；返回 0 文件且未在 `tasks/` 下拆分独立任务 → 视同 H3 重现，须先落地测试再提交。
4. **输入段落完整性自检**（auto-work 生成侧）：生成 `review-input-develop.md` 后自检是否包含 `## Git Diff --stat` / `## Changed Files` / `## Test Results Summary (本包 / 总)` 三段；缺失即回退重新生成，禁止进入 reviewer 阶段（见 `.claude/commands/auto-work.md` 阶段四相应条目）。

**根因（task-11 CR-1）**：R2 已针对 H2（proto 字符串字段用 `strconv.Itoa`）与 H3（plan 强制测试缺失）新增了 reviewer 侧硬规则（`reviewer-brief.md §7`、`testing-review.md` 前述小节），但 R4 作为规则出台后的首轮 develop，两条同类错误再次发生——说明"reviewer 规则只覆盖 reviewer 侧发现能力，不减少 developer 犯错率"。本小节将 reviewer 侧规则镜像为 developer 侧预检清单，闭合"规则已写 → developer 不看"的系统性缺口。

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

## Bug Fix 回归测试强制要求（不可协商）[通用]

<!-- Context Repair: task-01 H3 RECURRING — C2(GameID) FIXED 但无对应回归测试，连续两轮 OPEN -->
凡本轮 develop-review 报告中某问题状态从 OPEN → FIXED，reviewer 必须核实：

1. 修复对应的代码行在工作区中**存在至少一个针对性单元测试或集成测试用例**——grep 修复函数 / 修复参数 / 修复字段，确认命中测试文件，而非仅在其他测试路径中间接经过。
2. 若无对应回归测试，**将测试缺失标注为 High**（首次）或 **Critical**（RECURRING——同一修复两轮无测试）。
3. 此约束优先于"FIXED 无需再查"的惯性——Critical/High bug 修复不带回归测试视为修复不完整，不得标记 DONE 或进入下一迭代。

验证方式：reviewer 在确认修复代码存在后，紧接着执行 `grep -n "<修复的字段/函数/参数>" *_test.go`，确认至少一条命中；否则触发本条。

## 错误分类路径重构必须同步补充边界测试（不可协商）[通用]

<!-- Context Repair: v0.0.4 thin-client task-03 H3 — C1 修复（ErrAlreadyExists→202）后无对应回归测试，M7 连续三轮 RECURRING 升级为 High -->
凡涉及以下任意一类**高风险修改**，必须在同一 diff 中补充对应边界测试用例，缺一不可：

- **logger 级别变更**：将某 error 分支从 `logger.Error` 改为 `logger.Warn` / `logger.Info`
- **HTTP 状态码变更**：某 error 路径的响应码发生变化（如 500 → 202、409 → 200）
- **幂等逻辑变更**：新增或修改 `ErrAlreadyExists` / `ErrIdempotent` 类分支

**必须包含的测试要素（三件套，缺任一 Reviewer 升级为 High）：**

1. **触发该 error 的最小 stub**：通过 fake/mock repo 预置触发条件（如预存相同 `IdempotencyKey`），确保修复路径在测试中真实执行。
2. **精确断言 HTTP 状态码**：断言修复后的响应码（如 202），禁止使用 `HTTP *` 通配符。
3. **日志级别验证**（仅当 logger 级别被修改时）：使用 zaptest observer 断言修复路径**不触发** `logger.Error`；触发 `logger.Warn` 或 `logger.Info` 的可选断言。
   > **禁止用 `zap.NewNop()` 替代 zaptest observer**——`NewNop()` 丢弃所有日志且无任何断言，等价于第 3 件套缺失，触发 **High**（RECURRING → Critical，无豁免）。必须使用 zaptest observer core：`observer.New(zap.InfoLevel)` + `zap.New(core)` + `observedLogs.FilterLevel(zap.ErrorLevel).Len() == 0`。

**Reviewer 判定机制**：
- 修复路径无任何对应测试 → 首次 **High**，RECURRING（连续两轮）→ **Critical**
- 同一修复点连续三轮无测试且代码逻辑回滚风险高 → 自动升级为 Critical 且不得标记任务 Done

**典型正确测试结构（Go，zaptest observer）：**
```go
func TestHandler_CreateSession_Idempotent(t *testing.T) {
    // 1. 预存相同 idempotency_key 触发 ErrAlreadyExists
    repo := &FakeSessionRepo{existingKey: "idem-001"}
    h := NewHandler(repo, zaptest.NewLogger(t))

    w := httptest.NewRecorder()
    req := newCreateSessionRequest(t, "idem-001")
    h.ServeHTTP(w, req)

    // 2. 精确断言 HTTP 202
    assert.Equal(t, http.StatusAccepted, w.Code)
    // 3. 断言 body 含幂等标记
    var body map[string]interface{}
    json.Unmarshal(w.Body.Bytes(), &body)
    assert.Equal(t, true, body["idempotent"])
}
```

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

### 8. Signal 连接对称性（不可协商，physic-door CR-1）

<!-- Context Repair: physic-door plan-review CR-1 — plan.md 接口设计伪代码含 3 个 connect() 但无任何 disconnect()/_exit_tree() 路径，plan-review 未拦截，Critical 带入 develop -->

凡 plan.md 中接口设计或伪代码包含任意 `.connect()` 调用，plan-review 必须核查是否同时声明了对称的断连路径：

1. **默认要求**：每个 `.connect()` 必须有配对的 `_exit_tree()` + `.disconnect()` 路径；缺失任意一条 → **plan-review 判定 Critical**，阻断进入 develop。
2. **CONNECT_ONE_SHOT 豁免**：若 `.connect()` 使用了 `CONNECT_ONE_SHOT` 标志，且 plan 中已明确说明该信号仅触发一次（如"动画播完一次后不再使用"），允许豁免显式 `disconnect()`；但必须在 plan 中就地注明豁免理由。多次触发场景（如开关门状态机、碰撞触发器）**不得使用 CONNECT_ONE_SHOT 豁免**。
3. **子节点信号注意**：连接到子节点（而非 `self`）的 signal，在 `remove_child` 或 `queue_free` 后不会自动断连；plan 涉及此类场景时必须显式声明 `_exit_tree()` 断连策略。
4. **plan-review 执行方式**：从 plan.md 全文 grep `.connect(` 并列出所有命中行；对每个命中行在同文件内搜索对应的 `.disconnect(` 或 `_exit_tree()`；无配对且无 CONNECT_ONE_SHOT 豁免声明 → Critical。

**根因（physic-door plan-review P-01）**：`PhysicDoor._ready()` 含 3 个 `.connect()`，plan 全文无 `_exit_tree()` / `disconnect()` 路径；engine.md 虽已有"Signal 连接与断连对称（不可协商）"节，但该约束未被 plan-review 阶段覆盖，导致 Critical 带入 develop。

### 附加统一约束

`feature.md` 必须与 `plan/api.md` / `plan/testing.md` / `plan/flow.md` 当前事实同步（REQ 描述、验收断言、URL 命名、payload 形态、是否新增 HTTP 入口）；凡本轮已修正的合同若仍残留在 `feature.md`，即判 Critical，必须先同步 feature.md 再进入开发。**plan 迭代内同步时机（不可协商）：** 每轮 plan 修正状态码合同（如 422 细化、新增 409/500 变体等）后，下一轮 develop 阶段开始前必须先更新 `feature.md` 中对应 REQ 的验收断言；plan-review 的 Critical 清单中若含"状态码合同变更"条目，即触发 feature.md 同步义务，不得等到所有迭代结束后才一次性补同步。同时 `plan.md` 摘要 / 数据模型表与 `plan/server.md` 伪码中的同一 payload / 事件名 / repo 路径只保留一版，禁止新旧合同并存。

## Shell 脚本验收行为测试（不可协商）[通用]

`bash -n`（语法检查）不等于行为验证。凡任务交付物含 Shell 脚本且验收条件依赖该脚本正确执行，develop-review 必须确认验收覆盖了分支行为，而非仅语法正确性：

1. **语法检查不覆盖的典型缺陷**：注释化的条件分支（`#if ...`）、`exit` 在意外位置无条件触发、变量未赋值时静默空值传递
2. **最低行为测试要求**：使用 stub 或 mock 覆盖外部命令（`docker`、`sudo`、`systemctl`、`groups` 等），至少断言成功路径（以 0 退出）和失败路径（以非零退出并打印诊断信息）两条分支
3. **判定机制**：验收命令仅包含 `bash -n` 而无行为级断言 → develop-review 判定 High；RECURRING → Critical，计入宪法 §8 门禁

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

## ThinClient / GDScript 任务最低可执行验证（不可协商）[Engine]

<!-- Context Repair: v0.0.4 thin-client task-03 M1 RECURRING — verify_commands: [] 且无 Godot headless 执行证据，仅凭静态 grep 标记全 PASS；宪法测试规则原本偏 Backend/HTTP，对 GDScript autoload 无约束 -->

凡涉及 `ThinClient/autoload/*.gd`、`ThinClient/scenes/*.gd`、`project.godot` 或任何 GDScript 场景脚本的任务，必须满足以下最低可执行验证要求：

1. **Godot headless 解析证据**：`verify_commands` 至少包含一条 `godot --headless --import <project.godot>` 或等价 headless 解析/启动命令，并在迭代日志中留存实际输出（exit code + 关键输出行）；**静态 grep 代码形态不等于解析通过**。
2. **信号绑定 smoke 覆盖**：若任务包含 `.connect()` 调用或 autoload 节点间信号绑定，必须提供 Godot headless smoke 启动或 GUT 测试验证该路径无运行时错误；不得以"代码结构看起来正确"替代。
3. **环境缺失时的报告义务**：若运行环境中 `godot` 命令不可用，**必须**在 review 报告中显式标注 `[ENVIRONMENT_MISSING: godot] 以下验收项未完全验证`，并列出未验证的 autoload/场景脚本列表；不得仅凭静态 grep 将所有 task 标记为全 PASS。
4. **project.godot 版本一致性**：若任务包含 `project.godot` 的 `config/features` 变更，还必须满足 `.ai/constitution/engine.md`「project.godot 引擎版本元数据与工具链一致性」的要求——版本号与仓库容器脚本不一致即判 **High**；`[ENVIRONMENT_MISSING: godot]` 不豁免此项。

**执行侧阻断义务（不可协商）**：
- 当本机缺少 `godot` 命令时，执行者（Claude / 自动化脚本）在 develop-iteration-log 中写入任务状态时，必须使用 `BLOCKED_ENV` 或 `PARTIAL_VERIFICATION`，**不得写 `status: completed`**。
- 只有在迭代日志中附带了可复现的外部 CI/Godot headless 执行日志（含 exit code 和关键输出行）时，方可升级为 `completed`。
- "环境缺失但代码看起来正确"不构成 `completed` 的合法理由；完整验证需要真实 Godot 进程执行。

**Reviewer 判定机制**：
- `verify_commands: []` 且无 Godot 命令执行记录 → 任务不得标记全 PASS；首次标注 **Medium**，RECURRING（连续两轮）→ **High**，**计入宪法 §8 门禁计数**。
- 工作区含 `ThinClient/` 文件但 review-input 无 `[ENVIRONMENT_MISSING]` 标注、无 headless 执行记录 → 同上判定，reviewer 不得以"代码形态满足验收标准"通过。
- **连续两轮按 High 计入门禁**：宪法 §8「HIGH+ 问题累积 ≥ 2 条时，禁止进入下一轮迭代」；ThinClient 任务无 Godot 验证属可计入 High，不得以「环境缺失」豁免计数。环境缺失只影响 `[ENVIRONMENT_MISSING]` 标注义务，不影响门禁计数。
- **自动写入义务**：涉及 `ThinClient/scenes/*.gd` / `.tscn` 的任务，若 review-input 无 Godot headless 执行证据，reviewer 在报告中**必须**自动写入 `[ENVIRONMENT_MISSING: godot]` 并禁止标记全 PASS，不依赖执行者主动声明。
- **执行侧状态核查**：develop-iteration-log 中出现 `status: completed` 但无 Godot 执行证据 → reviewer 直接将对应 task 验收标记为 FAIL，不接受执行者自述。

## ThinClient 空壳实现拒收规则（不可协商）[Engine]

<!-- Context Repair: v0.0.4 thin-client acceptance CR-2 — SyncManager.gd、ResourceCache.gd、SSEManager.gd、SessionScene.gd 均为 1 行空壳，文件存在性检查通过但实现缺失；P0 链路全部未实现 -->

凡涉及 ThinClient 核心功能脚本（`ThinClient/scenes/*.gd`、`ThinClient/autoload/*.gd`、`ThinClient/scripts/*.gd`）的任务，**文件存在不构成实现完成证明**。须额外满足：

1. **关键 API 出现性检查**：验收前必须 grep 目标脚本，确认关键实现 API 在文件中存在。各功能类别对应必需 API：
   - WS 连接（SyncManager）：`WebSocketPeer`
   - 资源缓存（ResourceCache）：`HTTPRequest`、`ResourceLoader`
   - SSE/Chat（SSEManager/SessionScene）：`HTTPClient` 或 `_on_` 信号处理方法（不得以 `extends Node` 空壳通过）
   - 输入回传：`InputEvent`
2. **最小有效代码行数**：脚本正文（扣除 `class_name`/`extends`/注释行）须含 ≥ 5 行有效逻辑代码；仅含 `pass`、空方法体或孤立属性声明不计入有效行。
3. **空方法体连续拒绝**：`_ready()` 仅含 `pass`、空 `func init_session() → pass` 等结构，reviewer 必须标注 `STUB_ONLY`，禁止标记该 REQ 实现 PASS。

**Reviewer 判定机制**：
- 核心功能脚本 grep 关键 API 无命中 → 标注 `STUB_ONLY`，对应 REQ 代码实现维度判定 FAIL；首次 **High**，RECURRING（连续两轮）→ **Critical**，计入宪法 §8 门禁计数。
- `verify_commands` 含 grep 但目标关键 API 未命中 → 同上判定，不得以"文件已存在且能解析"豁免。
- 门禁说明：`STUB_ONLY` 空壳属于"实现缺失"，与环境缺失（`ENVIRONMENT_MISSING`）是两个独立拒收条件，后者豁免的是 headless 执行验证，不豁免 grep 关键 API 检查。

## GDScript 行为验证强制要求（不可协商，game-net acceptance CR-1）[通用]

凡 `tasks/task-NN.md` 的验收条件涉及以下任一 GDScript 行为场景，`verify_commands` **必须**包含 Godot headless 脚本测试（`godot --headless --script <test>.gd`）或等价可执行断言；纯文件存在性检查（`test -f` / `ls` / `grep` 静态搜索）**不构成**行为验证，直接判 `VERIFY_COMMANDS_NOT_RUN`：

- 信号发射与接收（`signal` / `emit_signal` / `connect`）
- 网络连接状态（连接成功 / 断线 / 重连 / 心跳超时）
- 消息队列入列 / 出列顺序
- 场景树节点的增删（`add_child` / `remove_child` / `queue_free` / `_ready` / `_exit_tree`）
- 场景切换或重载（`get_tree().change_scene_to_*`）
- UI 状态变更（按钮可见性 / 标签文本 / 错误提示弹出）
- Player / Entity / Component 生命周期钩子（`_ready` / `_process` / `_exit_tree`）
- 模式切换（联网 / 单机）产生的分支行为

**允许纯存在性检查的场景**：资源占位文件（`.uid` / `.import` / 素材 `.png` / 骨架 `.tscn` 无逻辑内容）、空目录骨架。对于同时含"文件创建 + 行为实现"的任务，至少需要一条行为断言，存在性断言可补充但不能替代。

**develop-review 硬检查**：任务描述 / 验收标准含上述行为关键词，但 `verify_commands` 仅有 `test -f` / `ls` / `grep` → 判 `VERIFY_COMMANDS_NOT_RUN`，不得放行。

**触发条件**：game-net acceptance CR-1 — REQ-001/003/011/022/030/031/032 均因"有文件·无行为测试"同类缺口失败。

## 跨端联网 feature P0 验收门禁（不可协商，game-net acceptance CR-3）[通用]

凡 feature 同时涉及 GameServer 服务端实现 + Godot 客户端对接（跨端联网），其 P0 级 REQ（端到端握手、Entity 注册与查询、Entity 下线清理、游戏消息下行等）在 develop review 和 acceptance review 阶段必须同时满足以下条件，缺一直接 FAIL，不得以 stub / placeholder 注释降级为 PASS：

1. **真实行为落地要求**：P0 REQ 的服务端实现**必须**体现真实业务逻辑——不得以 `Register(nil)` / 仅 demo log / `TODO(后续任务接入 Map Actor)` 注释代替实际对象创建、状态更新或广播。
2. **可执行 e2e 证据**：每条 P0 REQ **至少**命中以下之一：
   - 真实 TCP e2e 测试（Go build tag `integration` 或 `go test -run TestE2E*`）断言跨端行为（需验证具体 REQ 的业务语义，仅握手 ACK 不足以覆盖 Entity / 游戏消息类 REQ）；
   - 或 `godot --headless --script` 脚本断言客户端侧行为。
3. **禁止以编译 + 单侧单元测试组合替代**：`go build` + 单侧 `frame_handler_test.go` 通过 **≠** 跨端行为覆盖；P0 REQ 对应路径在 Go 侧有注释或调用但实际业务逻辑是 stub，则单侧测试虽通过也视为 P0 FAIL。

**develop-review 硬检查**：对 plan 标注 P0 / P0-Must 的 REQ，develop-review 必须回溯实现代码（非仅 diff 摘要），核实：(a) 服务端无 `Register(nil)` / demo log stub；(b) 对应 e2e 测试用例覆盖 REQ 业务语义。未满足即判 Critical，不得进入 acceptance 阶段。

**触发条件**：game-net acceptance CR-3 — REQ-004/012/013/031 均以 stub 实现通过 develop review。

## GameServer 断线清理路径 detached goroutine 验收检查（不可协商，game-net acceptance CR-4）[通用]

凡 feature 包含 GameServer 断线 / Session 关闭清理逻辑，acceptance review 阶段必须对清理相关目录执行以下机械检查；任一命中且无合规证明 → 对应清理相关 REQ 直接 FAIL：

```
rg "safego\.Go|go func|time\.After|time\.NewTimer" \
  GameServer/servers/<service>/internal/game_net/ \
  GameServer/servers/<service>/internal/<handler>/
```

**命中后的合规判定**：
- **合规**：`wg.Add(1)` 在同一代码块 + `defer wg.Done()` 在闭包内；或 goroutine 内部仅向已纳入 `wg` 的 `cleanupLoop` deadline 队列登记（不直接执行清理逻辑）。
- **违规**：goroutine 直接执行清理逻辑（如 `cleanupSessionEntities` / registry 注销 / 广播 EntityLeave）但无 `wg.Add` 追踪 → 违反生命周期规范，`Stop()` 无法等待 grace 清理完成。

**与 `GameServer/CLAUDE.md`「Session 清理所有权协议」§5 的关系**：§5 定义 develop 阶段的 review 检查点；本节将同一检查点在 **acceptance** 阶段再次机械执行，形成双层防护。

**触发条件**：game-net acceptance CR-4 — `frame_handler.go:211-219` 的 `OnSessionClose` grace goroutine 使用 `safego.Go` 未接入 `server.wg`，REQ-014 在 develop review 阶段未被捕获。

## ThinClient Mock 传输注入机制强制声明（不可协商）[Engine]

<!-- Context Repair: v0.0.4 test-thin-client plan-review C1 RECURRING — mock WS 注入路径连续三轮未闭环：plan 假设通过不存在的 UI 控件覆盖连接地址；mock payload 字段与 SyncManager 实际消费字段不一致；真实 SyncBroadcaster 链路被完全绕过 -->
<!-- Context Repair: v0.0.4 test-thin-client plan-review C4 RECURRING — SSE mock endpoint 路径与 ThinClient 实际请求路径不一致（`/api/v1/events` vs `/api/v1/sessions/{id}/events?token=...`），原规则只覆盖 payload 字段未覆盖 URL 路径 -->

凡 plan 使用 mock Backend / mock WS server / mock SSE 端点验证 ThinClient / GDScript 客户端行为，必须满足以下三条，缺一 plan-review 判 Critical：

1. **注入机制显式定义（必须已实现或本 task 明确新增）**：plan 必须指定具体注入方式。合法方式示例：
   - 修改 `ThinClient/config/client_config.cfg` 中的连接地址字段（同时确保 Session 响应 `sync_ws_url` 为空使 fallback 生效）
   - 提供测试专用 Backend 响应（令 `sync_ws_url` 返回 mock 地址）
   - 环境变量或命令行参数传入 mock URL
   - 测试场景脚本在 `_ready()` 中直接注入 mock URL

   **禁止**以下无工具链支撑的注入方式：引用不存在的 UI 控件、"手动修改响应"但无脚本/工具支持、通过不具备该功能的场景（如 SettingsScene 缓存清理 UI）控制连接参数。

2. **Mock 服务端点路径与 payload 字段双重对齐**：

   - **Endpoint URL 路径**：mock server 的 HTTP 路由路径（含路径参数与 query 参数格式）必须与 ThinClient 实际请求的 URL **逐字**一致。例如若 `SSEManager.gd` 请求 `GET /api/v1/sessions/{id}/events?token={events_capability_token}`，mock server 必须实现 `/api/v1/sessions/:id/events` 路由，而非简化路径 `/api/v1/events`。reviewer 必须 grep 目标脚本中的 URL 构造逻辑（`connect_sse()` 参数、`_url =`、`_sse_url =` 等），与 plan mock server 路由定义逐字比对。
   - **Payload 字段**：plan 中 mock server 下发的消息 payload 字段，必须与目标 GDScript 脚本中实际读取的字段名**逐字**一致。reviewer 必须 grep 目标脚本（如 `SyncManager.gd`）中 `msg.get("field")` / `msg["field"]` 等读取调用，与 plan 中 mock payload 定义逐字段比对。
   - 任一不符 → Critical，不得以"语义等价"为由通过。

3. **恢复步骤声明**：plan 必须包含测试结束后的显式恢复步骤（如：恢复 `client_config.cfg`、停止 mock server、重置环境变量），确保测试机能恢复正常 Backend 连接状态。

**Reviewer 判定机制**：
- 注入步骤引用不存在 UI 控件或无脚本支撑 → Critical（注入路径缺失）
- mock endpoint URL 路径与 ThinClient 实际请求路径不一致 → Critical（端点路径契约不一致）
- mock payload 字段与 GDScript 实际读取字段不一致 → Critical（消息契约不一致）
- 无恢复步骤声明 → Important
- RECURRING（连续两轮同类问题）→ 升一级；Critical RECURRING 计入宪法 §8 门禁，无豁免

## Godot 资源装配非空轨道核验（Develop 阶段强制）[Engine]

<!-- Context Repair: v0.0.1 animator develop-review task-01 C2 / task-01 round 2 C2 RECURRING — animation_library.tres 仅含 `resource_name/length/loop_mode/step` 的 stub 条目而无 `tracks/*` 骨骼关键帧；第二轮改为"所有动画都只有同一条 `Rig/Skeleton3D:Root` 零位移轨道"的伪真实形式继续绕过旧规则；条目数量/track_count 可被 grep 通过但 AnimationPlayer 播放时不会驱动 Skeleton3D，develop-review 被"条目数量存在"误导 -->

凡 task 交付 Godot 动画资源（`AnimationLibrary` / `.tres` / `.res`）或角色根场景（含 `Skeleton3D` + `MeshInstance3D` + `AnimationPlayer` 的 `.tscn`），**"文件存在 + `gd_resource` 头 + 条目数量" 不构成实现完成证明**。develop-review 须逐项核验：

1. **AnimationLibrary 抽样骨骼轨道断言**：`verify_commands` 至少对代表动画（Idle / Walk / Attack 任选一条以上）断言资源内包含 `tracks/*` 子节或等价骨骼关键帧数据；仅 grep `resource_name=` / `Animation` 条目数 / `loop_mode=` 判为误报通过，reviewer 判 **STUB_ANIMATION_LIBRARY**（首次 High，RECURRING → Critical，计入宪法 §8 门禁）。
   - **非根骨骼轨道强制（v0.0.1 animator task-01 round 2 C2 RECURRING 触发）**：抽样动作必须至少包含一条 `path=NodePath("Rig/Skeleton3D:<非 Root 骨骼>")` 或 `type="rotation_3d"` / `type="scale_3d"` / 属性轨道；全库仅有 `Rig/Skeleton3D:Root` 下的 `position_3d` 轨道即视同"单轨道伪真实"——即便每条动画都有 `tracks/*` 子节，仍判 `STUB_ANIMATION_LIBRARY`。reviewer 侧机械检查命令：`grep -c 'NodePath("Rig/Skeleton3D:[^R][^o]' <animation_library.tres>` 必须 ≥ 1；命中 0 即阻断。
   - **全库禁止退化为同一组常量（同 CR）**：抽样动作的 key 数据不得在全库中退化为"同一个 `PackedFloat32Array(0, 1, 0, 0, 0)` / 同一组零位移常量"。reviewer 抽取 `<AnimationLibrary>` 内首 3 条动画的 `tracks/0/keys` 字段 `sort -u | wc -l`，若 == 1 则视为全库同构 stub，判 `STUB_ANIMATION_LIBRARY`（同上判级）。
   - **verify 脚本断言升级**：`verify_*.gd` / `test_*.gd` 不得以 `animation.get_track_count() > 0` 作为通过门槛；必须同时断言：(a) 存在至少一条非 `Rig/Skeleton3D:Root` 的骨骼轨道路径；(b) 所有动画的 key 数据并非全库唯一常量；(c) 每条动画的 `get_track_count() ≥ 2` 或至少 1 条非 `position_3d` 轨道。仅 `get_track_count() > 0` 视同"只计轨道数不核内容"，本节判 STUB 不豁免。

2. **场景节点树实测**：task 声称交付"含 `Skeleton3D` / `MeshInstance3D` 的角色根场景"时，`.tscn` 文本必须出现 `type="Skeleton3D"` / `type="MeshInstance3D"` 节点；仅 `[ext_resource]` 引用 FBX + 空壳 `AnimationPlayer` 不构成"已导入骨骼场景"，判 **STUB_SCENE**（同上判级）。
   - **FBX-to-`.tscn` 导入任务的 `test -f` only 阻断（v0.0.1 animator task-02 H1 触发）**：凡 task 声称把 `.fbx` 骨架/模型导入为可实例化、可渲染的 `.tscn`（典型验收语：*"可在临时场景中实例化，MeshInstance3D 正常渲染"* / *"无 null 报错"*），`verify_commands` 仅列 `test -f` / `ls <path>` / `stat <path>` 视为**存在性-only**，直接判 `FBX_WRAPPER_EXISTENCE_ONLY`（首次 High，RECURRING → Critical，计入宪法 §8 门禁）。合规落地必须满足以下任一：
     - (a) **落盘的 `.tscn` 文本包含 `type="Skeleton3D"` 与 `type="MeshInstance3D"` 节点**（即在 Godot 编辑器中已保存为展开的节点树，而非仅 `[ext_resource type="PackedScene"]` + `[node ... instance=ExtResource(...)]` 的 FBX wrapper）；
     - (b) **提供随 task 提交的 headless scene-load 断言脚本**（`godot --headless --script load_<name>.gd` 或 GUT 用例），脚本内逐一断言 `get_node()` 能取到 `Skeleton3D` / `MeshInstance3D` 子节点，且环境缺失 Godot 时必须在迭代日志补 `[ENVIRONMENT_MISSING: godot]` 标注 —— 脚本本身落盘即可，不因环境缺失豁免脚本存在性。

3. **Headless 导入 / scene-load 证据归档**：至少提供一条 `godot --headless --import` 或 `godot --headless --script <scene_load.gd>` 的 exit code + 关键日志行，确认资源可解析且 AnimationPlayer 可加载对应 AnimationLibrary；无执行证据时按「ThinClient / GDScript 任务最低可执行验证」§3 写入 `[ENVIRONMENT_MISSING: godot]`，**但仍判 STUB 拒收** —— 环境缺失豁免的是 headless 执行本身，不豁免资源内容核验（文本断言可离线执行）。

4. **骨骼根节点名与 Key 映射回填核验**：plan / task / 权威映射文档中声明要回填的 Armature / Skeleton3D / 根 Bone 节点名仍保留 `<ArmatureNode>` / `<Skeleton3D>` / `<RootBone>` / "首次 Godot 打开后确认" / "待验证字段" 等占位符即视为"合同未落地"，判 High（首次）→ Critical（RECURRING）；下游 AnimationTree / `.gd` 消费该映射时会继续依赖猜测路径。
   - **"已填写/已核实"声称 × 占位符残留双向扫描（v0.0.1 animator task-01 round 2 M1 RECURRING 触发）**：plan / task 中同时出现"已填写"/"已核实"/"已回填"类声称与任一未闭环占位符（`<[^>]+>` / `首次 Godot 打开后确认` / `待验证字段` / `待填写` / `TBD`）时，直接判 `AUTHORITY_MAPPING_PLACEHOLDER_RESIDUAL`；禁止放行"文档声称已填但正文仍是 `<ArmatureNode>`"的伪闭环状态。该信号由 auto-work G8 在写盘前机械阻断（见 `.ai/context/auto-work-gates.md` G8）。

5. **资源文件自白式拒收**：`animation_library.tres` / `.tscn` 内出现 "stub" / "placeholder" / "replace with actual clips" 等自白字样 → 自动触发拒收，不接受"占位先行、后续补齐"；task 必须退回未完成状态或拆分为独立后续 task 明确承接。

**与「ThinClient 空壳实现拒收规则」的关系**：本规则覆盖 Godot 资源（`.tres` / `.res`）与角色根场景（`.tscn`）的**内容**核验，与 GDScript 脚本空壳规则并列；同一 task 含脚本 + 资源改动时两条规则同时生效。

## Godot gameplay feature 最低验证（Plan 阶段强制）[Engine]

<!-- Context Repair: v0.0.1 animator plan-review — 9 个 REQ 均无自动化硬断言，验收方式全部为"编辑器 Play / 观察"；animator、未来任何 gameplay feature 均面临此缺口，属系统性问题而非单次实现失误 -->

凡 plan 新增或修改 `.gd`、`.tscn`、`project.godot` 或 Godot 资源装配（含动画状态机、动画树、碰撞体、攻击伤害逻辑、血量/属性、输入映射），**Plan 阶段必须满足以下最低验证要求**，缺项 plan-review 判 Important（首次）或 High（RECURRING）：

1. **至少一条可执行解析命令**：plan 的验证章节必须声明至少一条 `godot --headless --import <project.godot>` 或等价 headless 解析/启动命令；仅描述"编辑器 Play"或"手工观察"不构成可机械重复的验收证据。

2. **含状态机 / 配置读取 / 伤害血量 / 输入映射功能的强制测试要求**：以下类别的 REQ，plan 测试章节必须声明至少一种测试机制：
   - **GUT 测试脚本**：落地于 `test/` 目录下的 `GutTest_*.gd` / `test_*.gd`，逐 REQ 断言状态转换、数值计算、信号发出
   - **测试场景脚本**：专用 `.tscn` + GDScript 驱动程序，以 headless 方式执行
   - **可执行 smoke**：`godot --headless <scene_path>` 并断言 exit code = 0 且关键日志包含预期输出

3. **逐 REQ 验收映射**：测试章节必须对每条功能 REQ 逐一声明：(a) 验收断言的具体内容（非"观察输出正确"等主观描述），(b) 证据归档路径（如 `docs/version/<ver>/<feature>/test-evidence/req-XX.log`）。

**Reviewer 判定机制**：
- plan 测试章节全部为"在编辑器 Play 验证"或无验收命令 → Important（首次）；RECURRING（连续两轮）→ High，计入宪法 §8 门禁计数
- 含状态机 / 伤害逻辑 / 输入映射 REQ 但无 GUT / 测试场景 / headless smoke 声明 → High（首次）；RECURRING → Critical
- 逐 REQ 验收映射缺失（仅有 feature 级总结，无 REQ 级断言） → Important

**与 ThinClient 规则的关系**：本规则覆盖所有 Godot gameplay feature（含但不限于 ThinClient 以外的游戏脚本），是对「ThinClient / GDScript 任务最低可执行验证」的补充，而非替代；ThinClient autoload 相关任务同时适用两条规则。

## 测试类 Feature Plan 必须包含执行与证据归档任务（不可协商）[通用]

<!-- Context Repair: v0.0.4 test-thin-client plan-review C5 — feature 目标是 E2E 测试+修复，但全部 task 仅产出文件，无执行任务；开发可在未运行任何 ThinClient E2E 的情况下完成所有任务并标记 Pass -->
<!-- Context Repair: v0.0.4 test-thin-client plan-review C1 RECURRING — 执行 task 中门禁命令使用 `cmd | tee log`，`$?` 读取的是 tee 退出码而非实际命令退出码，Godot/hurl 失败仍可打印 [OK] -->

凡 feature 的核心目标包含"测试验收"、"E2E 验证"、"回归测试"或"端到端测试+修复"，plan 必须包含至少一个独立的**执行与证据归档任务**，该任务须满足：

1. **执行步骤可运行且 exit code 真实**：列出实际可执行的命令（如 `setup-env.sh`、`hurl sessions.hurl`、mock server 启动、Godot headless 启动），而非仅描述产物创建；凡命令通过管道输出（如 `cmd | tee log.txt`），必须在脚本开头声明 `set -o pipefail` 或在管道后立即读取 `${PIPESTATUS[0]}` 保存真实退出码；仅读取 `$?` 获取 `tee` 退出码属于门禁失效，不构成"exit code 为 0"的有效证据；
2. **证据归档要求**：明确要求保存命令输出（exit code + 关键日志行）、截图或录像、每个 REQ 的 Pass/Fail 状态到指定文件路径；
3. **完成门槛**：每个 REQ 的 Pass/Fail 结论必须依据实际执行证据，占位符（如"实际结果测试执行时填写"）不得标记 Done；没有执行证据的 REQ 不得标记 Pass。

**Reviewer 判定机制**：
- plan 执行顺序仅描述文件产物创建、无任何执行类 task → High（首次），RECURRING → Critical，计入宪法 §8 门禁
- task 验收条件全部为"文件存在/包含章节"而无命令执行断言 → Important
- 任一 REQ 保留"实际结果待填写"占位符并标记 Pass → 不接受，reviewer 直接将对应 REQ 判 FAIL
- 执行 task 中管道命令未声明 `set -o pipefail` 或未读取 `${PIPESTATUS[0]}` → Important（首次），RECURRING → High，计入宪法 §8 门禁
