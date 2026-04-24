# GameMaker 共享开发宪法（核心原则）

Version: 1.4
Scope: Claude Code / Codex / 其他在本仓库工作的 AI agent

本文件是项目级最高规则。任何 agent 的本地偏好、命令系统或自动化流程，都不得违反这里的约束。

> **领域隔离声明：** 本仓库包含三个知识隔离的领域：
> 1. **创作平台**（Frontend/ Backend/ MCP/ Engine/ Tools/ Editor/）— AI 驱动的游戏创作链路
> 2. **容器游戏制作**（Engine/ + Backend 容器管理）— Godot 容器内的游戏构建
> 3. **游戏服务器**（GameServer/）— 独立部署的实时游戏服务器框架（多进程、TCP/KCP、Protobuf）
>
> 本宪法第 1-4、8-11 节为通用规则，适用于所有领域。**第 5-7 节仅适用于创作平台领域**，GameServer 有自己的架构模式（Actor + FSM + Protobuf），不受这些节约束。
> GameServer 的开发规范见 `GameServer/CLAUDE.md`（通用入口），各子服务有独立的 `servers/<name>/CLAUDE.md`。

> **模块详细规则按需加载（不默认装载）：**
> - Backend 并发 / 生命周期 → `.ai/constitution/backend.md` + `.ai/context/backend-lifecycle.md`
> - 测试验收 / Plan Review 硬检查 → `.ai/constitution/testing-review.md`
> - 跨模块通信 → `.ai/constitution/cross-module.md`
> - Engine 多平台兼容 → `.ai/constitution/engine.md`
> - 调研信息质量 / teaser 判定 / 第三方来源分层 / 规模数字时点 → `.ai/constitution/research.md`

## 1. 简单优先

- 只实现需求明确要求的内容，不做预支设计。
- 先用现有依赖和标准库解决问题，再考虑新增依赖。
- 简单函数和清晰数据结构优先于过早抽象。
- **实现功能时优先复用项目现有技术栈的语言**（创作平台：Go / TypeScript / Python / GDScript；GameServer：Go / Protobuf）。**不得为单点需求引入新语言**——新语言会带来构建链、依赖管理、CI、部署、人力维护等全链路成本。确需引入时，必须在 plan / 设计文档中说明理由（现有语言无法胜任、生态显著优势、已评估替代方案）并取得确认后才能落地。

## 2. 明确性与可观测性

- 错误必须显式处理，禁止静默吞错。
- 记录错误时必须带上下文日志。
- 注释解释"为什么"，不要重复代码表面含义。
- **注释不得虚报运行时约束的满足状态**：凡涉及并发串行化（Actor / Map.Post）、锁保护、事务原子性、context 传播、资源归属等运行时约束，若代码并未真实满足该约束，严禁留"与 X 等价 / 模拟 X 契约 / 日后替换即可"类注释；必须以 `WARNING` / `TODO(任务号)` 就地标注真实状态，说明"当前实现**不**满足 X 约束，依赖 X 的读写路径不得复用本段代码"。违反该原则的最常见形式是用裸 goroutine 充当 Actor/Map.Post（详见 `GameServer/CLAUDE.md` 反模式清单）。

## 3. 低耦合高内聚

- 一个模块只负责一类职责。
- 依赖方向保持单向，禁止循环依赖。
- 业务层依赖接口，不直接依赖基础设施实现。
- 入口层负责组装依赖，业务代码不自行拼装基础设施。

## 4. 测试先行

- 新功能和缺陷修复优先从失败测试开始。
- Go 使用 `testing`，TypeScript 使用 Jest，Python 使用 pytest。
- 新增 HTTP 端点时，必须同时补上路由注册测试和 smoke 测试。
- **Task `verify_commands` 必须能实际运行测试**。仅 `go build` / `go vet` / `tsc --noEmit` 只验证编译/语法，不构成测试验证；任务 scope 是 `_test.go`、`*.test.ts`、`.hurl` 或验证标准列出具名用例时，`verify_commands` 必须直接调用对应的 `go test -count=1` / `jest` / `hurl` 命令。**迭代日志/`review-input` 中 `verify_commands` 的执行证据必须逐字包含 `tasks/task-NN.md` 声明的命令串**（task-12 round-12 CR-2）；以 `go build` / `go vet` 代替 `go test` 视为 `VERIFY_COMMANDS_NOT_RUN`，禁止 `status: completed`。**`-race requires cgo` 等环境不可用场景**下，必须在 `verify_commands` 显式标注降级原因，并挂接**具名的** stress fallback 测试（≥100 goroutine 的并发 cleanup/close/send 压测）及其确切命令，否则仍判 `VERIFY_COMMANDS_NOT_RUN`。此项由 auto-work 生成侧在进入 review 前机械阻断（task-11/12/13/14/15 CR RECURRING，task-12 round-12 CR-2 扩展）。
- **存在性检查不得冒充行为验证**（task-32 H1）：当 `tasks/task-NN.md` 的「验证标准」描述了可执行行为（具名函数签名 / 按钮或信号处理器副作用 / 运行时状态切换 / 场景重载 / 节点树裁剪等），`verify_commands` 必须包含一条能触发该行为的可运行断言（GDScript 脚本级 smoke、`godot --headless --script` 断言脚本、`go test` / `jest` / `hurl` 等），并在断言内核实"任务描述的副作用是否真的发生"。`bash -c "test -f <path>"` / `ls <path>` 这类**仅文件存在性**命令只允许用于纯文件占位型任务（资产 `.uid` 占位、空目录骨架、素材落盘），若 task 的验证标准同时含行为描述与存在性断言，则 `verify_commands` 至少需要一条行为断言，否则判 `VERIFY_COMMANDS_NOT_RUN`。由 auto-work 生成侧机械门禁 G1 识别「存在性-only + 任务描述含行为」的组合并阻断进入 reviewer。
- **task scope 与实际 diff 的交集必须非空**（task-12 C1 RECURRING）：`tasks/task-NN.md` 声明的核心交付物必须出现在 `git diff --name-only ∪ git status --short` 中；若核心文件声明存在但 diff 中完全不含该文件的改动，视为 task scope 与交付脱钩，阻断 reviewer 阶段。
- **review-input 工作区覆盖率必须 100%**（task-12 round-8 CR-1 RECURRING）：`review-input-*.md` 的 `## Changed Files` 必须逐一覆盖 `git diff --name-only ∪ git status --short` 的全部工作区文件（含未跟踪 `??` / rename / delete）；任一工作区文件未在摘要中出现即视为输入不完整，禁止进入 reviewer 阶段。
- **文档化事实 ≠ 修复缺陷**（task-12 round-12 CR-1 RECURRING）：当 `review-input-*.md` / 迭代日志 / 任何产物文档中已经承认 `Changed Files ∩ task scope = ∅`、工作区覆盖不完整、`-race` 未执行等违宪事实时，**必须删除当前 `review-input-*.md` 并回退 developing**；"把事实写入文档"不构成修复，reviewer 下一轮遇到这类文档化承认必须直接判 `WORKSPACE_COVERAGE_INCOMPLETE` / `SCOPE_INTERSECTION_EMPTY` / `VERIFY_COMMANDS_NOT_RUN` 为 Critical [RECURRING]，且三个信号在同轮内视为 **non-recoverable**（本轮不得靠局部修补放行，必须回退到最近一次合规快照再重跑）。
- **`review-input-*.md` 必须含顶层独立 `## Gate Results` 段**（task-12 round-14 CR-2）：生成侧在写盘前必须在 `review-input-*.md` 顶层追加独立的 `## Gate Results` 段，字段至少包含 `tracked / untracked / listed / missing / scope_intersection / status`，字段值必须来自对当前 `git diff --name-only ∪ git status --short --untracked-files=all` 的实测结果；仅出现在 `## Changed Files` diff 内容内部、迭代日志叙述或注释中的 Gate Results 不构成门禁证据，reviewer 直接判输入不完整并阻断。
- **scope 交集的证据域只能是当前工作区**（task-12 round-14 CR-1）：develop-review 的 `Changed Files ∩ task scope` 计算**必须**以当前 `git diff --name-only ∪ git status --short --untracked-files=all` 为唯一来源。禁止使用 `git log`、历史 commit、上一轮 reviewer 结论、迭代日志叙述或任何"联合历史"口径（如 `git_log_union_working_diff`）将过去的交付伪装成本轮 scope 交集；违者直接判 `SCOPE_INTERSECTION_EMPTY` Critical [RECURRING]。若需要验收已提交历史，仅在 **acceptance review** 阶段改用 `base..HEAD` 口径，且必须在 task 文件中显式声明 review 阶段与口径。
- **review-input 三源采集必须出自同一 `git -C <repo-root>` baseline**（v0.0.1 animator task-01 CR-1 首触 → task-02 CR-1 RECURRING）：生成 `review-input-*.md` 时，`## Git Diff --stat` / `## Changed Files` / 三源合并文件清单必须在**同一次**针对 `FEATURE_DIR` 所属 repo 根的 `git -C <repo-root>` 调用内采集，禁止拼接上一阶段 / 其他 feature / 历史 develop-loop 缓存的 diff（v0.0.1 animator task-02 实证：review-input diff 全部来自 v0.0.4 test-thin-client，task-02 三个交付物反而一个都没上榜；task-01 round N 实证：Template/TP-UGC-3D feature 的 review-input 内嵌 `E:/GameMaker` 根仓库 diff 与 `v0.0.4/test-thin-client` 文件）。生成侧须在生成 `## Gate Results` / `## Git Diff --stat` / `## Changed Files` **之前**执行 `git rev-parse --show-toplevel` 并断言其与 feature 根一致，不一致即判 `STALE_REVIEW_INPUT_CROSS_FEATURE` 阻断写盘；`## Changed Files` 含任一工作区外路径亦同样阻断。
- **FBX → `.tscn` 导入任务禁止 `test -f` only**（v0.0.1 animator task-02 H1）：凡 task 声称把 `.fbx` 骨架/模型导入为可实例化 / 可渲染的 `.tscn`（验收语含 *"实例化"* / *"MeshInstance3D 正常渲染"* / *"无 null 报错"*），`verify_commands` 仅为 `test -f` / `ls` / `stat` 视为 `FBX_WRAPPER_EXISTENCE_ONLY`，由 auto-work G1 机械阻断，必须补：(a) 展开 `Skeleton3D` / `MeshInstance3D` 节点的 `.tscn`，或 (b) headless scene-load 断言脚本。详细规则见 `.ai/constitution/testing-review.md §Godot 资源装配非空轨道核验`（Template 版已固化）。
- **reviewer 能识别 ≠ 生成侧可反复失效（write-path enforcement failure）**（v0.0.1 animator task-01 round 4 / task-02 round 4 / task-03 CR-1 RECURRING）：凡 reviewer 侧已能稳定识别并 RECURRING 标注的违规（`GATE_RESULTS_MISSING` / `GATE_RESULTS_NOT_TOPLEVEL` / `STALE_REVIEW_INPUT_CROSS_FEATURE` / `FBX_WRAPPER_EXISTENCE_ONLY` / `SCOPE_INTERSECTION_EMPTY` / `WORKSPACE_COVERAGE_INCOMPLETE` / `FIXED_CLAIM_MISMATCH` 等），生成侧**必须**同步在 `.ai/context/auto-work-gates.md` 绑定**写盘前（G1-G5 / G7）+ 写盘后（G6 post-write validator）**双重机械门禁，并在 `.claude/commands/auto-work.md §收敛前必跑清单` 显式引用这些门禁；权威语义写入 `.ai/constitution/*.md` / `.ai/context/reviewer-brief.md` 而无生成侧机械门禁绑定 → 视为**write-path enforcement failure**（权威规则存在但工作流不执行）、上下文修复未闭环，下一轮 reviewer 直接计入宪法 §8 门禁。task-01 round 4 实证：`## Gate Results` 必须位于 `## Changed Files` / `## Git Diff --stat` 之前的位序规则已在 `reviewer-brief.md §零-B 第 8 条` 和 G6(a) 同时固化，但 Round 4 生成器仍产出缺 `## Gate Results` 的 `review-input-develop.md` —— reviewer 不得靠重建 diff 绕过失败的生成侧门禁，必须以 `REVIEW_BLOCKED: INPUT_INCOMPLETE: GATE_RESULTS_MISSING` 直接阻断。上下文修复落点判断见 `.claude/rules/context-repair.md §判断标准`。
- **迭代日志 FIXED 声称必须与落盘 review-input 文件交叉校验**（v0.0.1 animator task-03 round 4 C1 / C2 RECURRING）：`develop-iteration-log-task-NN.md` 中的 `FIXED` / `STILL-PRESENT` 处置状态**不得**作为本轮合规的充分证据；G6 post-write validator 必须在 reviewer 启动前重新打开落盘的 `review-input-*.md`，对 log 声称"Gate Results 已加入 / 三源已重采 / 未跟踪核心产物已列入 Changed Files"等每一条 FIXED 证据，逐条与磁盘内容比对。声称与落盘不一致 → 以 `FIXED_CLAIM_MISMATCH` / `POST_WRITE_VALIDATOR_MISSING` 信号删除半成品 `review-input-*.md` 并回退 developing，reviewer 遇到"日志 FIXED 但文件仍不合规"组合直接判 Critical [RECURRING]，不得以"已写入处置表"为由放行。配套 reviewer 入口校验见 `.ai/context/reviewer-brief.md §零-B` 第 8 条（Gate Results 顶层段强制）。
- **reviewer `REVIEW_BLOCKED` 必须以机器门禁形式记录到迭代日志**（v0.0.1 animator task-05 CR-2）：reviewer 返回 `REVIEW_BLOCKED: <SIGNAL>`（`GATE_RESULTS_MISSING` / `INPUT_INCOMPLETE` / `PHASE_MISMATCH` / `AUTHORITATIVE_REFERENCE_BROKEN` / `POST_WRITE_VALIDATOR_MISSING` / `FIXED_CLAIM_MISMATCH` 等）时，`develop-iteration-log-task-NN.md` / `plan-iteration-log.md` 必须在本轮末尾追加完整的 `[BLOCKED: <SIGNAL>]` 记录，字段至少包含：触发的 validator 命令（逐字）、validator 失败 stdout 片段、重新生成 review-input 的证据（新的 `git rev-parse --show-toplevel` / `## Gate Results` 字段值 / 落盘文件摘要）。仅有 baseline 行或人工叙述"已处理"视为 `BLOCKED_NOT_RECORDED_AS_ENFORCEMENT` 流程门禁缺口，reviewer 下一轮直接判 Critical [RECURRING] 计入本节门禁（task-05 实证：reviewer 返回 `REVIEW_BLOCKED: INPUT_INCOMPLETE: GATE_RESULTS_MISSING`，`develop-iteration-log-task-05.md` 仅 baseline 行，缺 validator 命令 / 失败输出 / 重新生成证据）。
- **`.ai/` 引用必须在当前工作区 `.ai/` 树内可达**（v0.0.1 animator task-05 CR-1）：任何 `.ai/` 文件（`constitution.md` / `README.md` / `context/*.md` / `constitution/*.md`）对 `.ai/` 子路径的引用，必须在**该文件所在的 `.ai/` 树**内可直接读取（root `.ai/` 和 Template/TP-UGC-3D/.ai/ 是两棵独立的树，互不隐式继承）。root 侧新增权威文件时必须同步落到所有存在的 `.ai/` 树（全量复制或"权威来源: root `.ai/...`，本文件只做指针"的指针文件二选一）。引用路径在当前工作区不可读 → 下一轮 reviewer 判 `AUTHORITATIVE_REFERENCE_BROKEN` / `GATE_RULES_MISSING_FROM_WORKSPACE` Critical，计入本节门禁。
- **`Tests: 0/0 passed` + 依赖 headless/测试验证的 FIXED 声称 = `FIXED_CLAIM_MISMATCH` Critical**（v0.0.1 animator task-01 round 5 CR-3）：凡 `develop-iteration-log-task-NN.md` / `review-input-*.md` 把某条 CR 标记为 `FIXED` 且修复依赖 headless/Godot/测试验证（例如"`verify_human_character.gd` 已覆盖 C1/C2/H1"、"headless scene-load 已通过"、"AnimationPlayer 已驱动 Skeleton3D"），则 `## Test Results Summary` **必须**同时满足：(a) 任一包/总计数不得为 `0/0 passed`；(b) 必须携带该具名测试的**实际命令**、**退出码**、**关键 stdout/stderr 片段**三项证据，缺一即 `FIXED_CLAIM_MISMATCH` Critical [RECURRING]，与 `-race` 未跑同级处理。环境缺失 Godot 等依赖 → 必须改写为 `[ENVIRONMENT_MISSING: godot]` 并撤销 `FIXED`，不得同时保留 `FIXED` 与 `Tests: 0/0 passed`。配套写盘后机械门禁见 `.ai/context/auto-work-gates.md §G6 第 5 项 FIXED_CLAIM_MISMATCH 对照表` 新增行「依赖 headless/测试的 FIXED × 0/0 passed」。
- 详细的验收硬检查、Plan Review 检查项、产物核验规则 → `.ai/constitution/testing-review.md`
- 详细的 auto-work 生成侧机械门禁清单（G1-G6，review-input 三源采集、工作区覆盖率、scope 交集、verify_commands 实跑、CR ack 日志、`Gate Results` 机器可读计数块、phase-switch 完整性与 stale develop-input 阻断、写盘后 post-write validator 再校验、**task scope ∩ Changed Files 独立校验**）→ `.ai/context/auto-work-gates.md`
- **G6 须独立校验 task scope ∩ Changed Files**（v0.0.1 animator task-08 CR-1）：G6 post-write validator 必须从 `tasks/task-NN.md` 直接提取核心 scope 文件并与 `## Changed Files` 段内容比对（不依赖 Gate Results 数值）；交集为空时触发 `SCOPE_INTERSECTION_EMPTY`，删除半成品并退回 developing。与 G6(e)「逆向 stale 路径检测」互补：(e) 防 Changed Files 含工作区不存在的历史路径；本条防 task 核心产物在 Changed Files 中缺位。详见 `.ai/context/auto-work-gates.md` G6 第 6 条。
- **G6(a2) 须从落盘文件提取并强制校验字段值 + `## Git Diff --stat` 顺序约束**（v0.0.1 animator task-11 CR）：G6 post-write validator 在确认 `## Gate Results` 顶层结构后，必须从文件实际提取 `missing:` / `scope_intersection:` 字段值并验证 `missing==0` / `scope_intersection≥1`；同时检查 `## Gate Results` 出现在 `## Git Diff --stat` **之前**（原仅检查在 `## Changed Files` 之前）。两项均为写盘前（G2）和写盘后（G6）双侧机械门禁。详见 `.ai/context/auto-work-gates.md` G6(a2)。
- **G8：Godot 资源装配伪真实轨道 + 权威映射占位符残留**（v0.0.1 animator task-01 round 2 C2 + M1 RECURRING 触发）：写盘前 + G6 post-write 双侧机械门禁，覆盖两类本轮 reviewer 侧实证失效的伪闭环形态。(a) `animation_library.tres` 全库仅有 `Rig/Skeleton3D:Root` 下 `position_3d` 轨道或全库 key 数据退化为同一组常量 → `STUB_ANIMATION_LIBRARY`；verify 脚本以 `get_track_count() > 0` 作为通过门槛视同"只计轨道数不核内容"；(b) plan / task / asset-import / mapping 文档同时出现"已填写/已核实/已回填"类声称与任一未闭环占位符（`<ArmatureNode>` / `首次 Godot 打开后确认` / `待验证字段` / `TBD`）→ `AUTHORITY_MAPPING_PLACEHOLDER_RESIDUAL`，禁止放行"声称已填但正文仍是 `<ArmatureNode>`"的伪闭环。详见 `.ai/context/auto-work-gates.md` G8 + `.ai/constitution/testing-review.md §Godot 资源装配非空轨道核验`（第 1 条非根骨骼轨道强制 + 第 4 条占位符双向扫描）。

## 5. 并发与任务安全（创作平台专属）

> **作用域：** Backend/ MCP/ Engine/ 创作平台链路。不适用于 GameServer/（GameServer 使用 Actor 模型处理并发，见其自有文档）。

- Redis Streams 任务消费必须幂等，成功后 ACK，失败要记录并重试或进入死信处理。
- Go 的阻塞操作必须传播 `context.Context`。
- 容器必须有资源限制、生命周期追踪和健康检查。
- 详细的锁、连接、ctx 取消、goroutine 信号化规则 → `.ai/constitution/backend.md`

## 6. 多平台兼容（创作平台专属）

> **作用域：** Engine/ 及创作平台导出链路。不适用于 GameServer/。

- Engine 层决策必须优先保证 iOS / Android 可导出。
- 禁止引入仅支持单一移动平台或仅适合桌面端的引擎依赖。
- 性能基线以移动端设备为准，而不是桌面端。
- 详细的平台导出规则 → `.ai/constitution/engine.md`

## 7. 跨模块通信（创作平台专属）

> **作用域：** Frontend ↔ Backend ↔ MCP ↔ Godot 创作平台链路。不适用于 GameServer/（GameServer 使用 Protobuf + TCP 的服务间通信模型）。

- Client <-> Server 用 REST / SSE；Server <-> MCP 用 HTTP；MCP <-> Godot 用 TCP / WebSocket。
- 所有外部输入必须经过 schema 或 binding 校验。
- MCP 工具应保持语义化，不直接暴露底层 Godot API 细节。
- 详细的鉴权、契约、幂等规则 → `.ai/constitution/cross-module.md`

## 8. Review 闭环

- Review 发现的 CRITICAL / HIGH 问题必须在下一轮迭代开始前处置。
- 每轮迭代记录必须包含"上轮 Review 问题处置表"。
- **门禁**：计入门禁的 HIGH+ 问题累积 ≥ 2 条时，禁止进入下一轮迭代。
- 状态定义（FIXED / SPLIT / ACCEPTED_RISK / POSTPONED / OPEN）及出池条件详见 `.ai/context/reviewer-brief.md`。

## 9. 错误分层与日志分级

- **错误变量分层**：sentinel error 必须定义在它所属的语义层（repository 层 vs service 层）。
- **日志级别**：Error/Fatal 仅用于非预期系统故障；业务正常路径（如 404）记为 Error 视为违宪。
- **错误日志上下文**：每条错误必须包含操作名、实体 ID、失败原因。

## 10. 共享上下文治理

- `.ai/` 是跨 agent 的共享事实源。
- `.claude/` 是 Claude 专用运行时层，不单独定义项目事实。
- 更新项目级规则时，先改 `.ai/`，再同步必要的 agent 专用文件。

## 11. 冲突解决

优先级如下：

1. 宪法核心原则（本文件）及模块详细规则（`.ai/constitution/*.md`）
2. 共享项目文档，例如 `.ai/context/project.md` 与 `Docs/Architecture/`
3. agent 专用运行时文件，例如 `.claude/commands/*`、`.claude/skills/*`
