---
description: 给一个需求，AI自动完成调研→方案→开发全流程
argument-hint: <version_id> <feature_name> [需求描述]
---

## 设计原则（优化 auto-work 时必须遵守）

所有 AI 模型都有上下文窗口限制，而 auto-work 是一个流程很长的工作流。
**任何对 auto-work 的优化都必须遵守以下原则：**

### 1. 独立执行单元，独立上下文
- 每个可独立完成的工作阶段，必须在**独立的上下文窗口**中执行，零历史污染
- **模式A（Bash 编排）**：通过 shell 脚本调用 `claude -p` 启动独立 CLI 进程
- **模式B（Agent 编排）**：当 `claude -p` 不可用时（沙箱、IDE、权限限制），通过 `Agent(mode: "bypassPermissions")` 启动独立子 Agent——每个 Agent 同样拥有完全独立的上下文窗口
- 两种模式提供等价的上下文隔离保证，区别仅在于执行载体
- 禁止在一个执行单元中堆积多个阶段的工作，避免长流程上下文膨胀导致质量下降
- 执行单元之间**不共享运行时上下文**，只通过持久化文档交流

### 1.5 对抗审查与收敛（Triple-Check 收敛法）

auto-work 采用执行者 + 审查者分离架构，利用角色分工加速 Bug 收敛：

**角色分工：**
- **执行者**：编码实现、修复代码、生成测试
  - 模式A：`claude -p` 独立 CLI 进程
  - 模式B：`Agent(model: "opus")` 独立子 Agent
- **审查者**：对抗审查、找茬挑错、验证修复
  - 模式A：`codex exec --full-auto`（跨模型对抗，审查质量最高）
  - 模式B：`Agent(model: "sonnet")` 以"严苛架构审查者"角色（同模型角色对抗，质量略低但仍有效）

**三步收敛循环：**

| 步骤 | 执行者 | 动作 | 关键机制 |
|------|--------|------|----------|
| 1. 编码+自检 | Claude | 实现功能 + 生成测试 + 运行测试 | 确保代码自洽 |
| 2. 对抗审查 | Codex | 以"严苛架构师"视角找 Claude 盲区 | 跨模型找茬 |
| 3. 闭环修复 | Claude | 基于 Codex 报告修复，不得轻视 | 认真对待跨模型发现 |

**对抗审查重点（Codex 额外关注）：**
- 并发竞态条件、资源泄漏、异常路径盲区
- 边界输入（nil/空/超长）、安全漏洞、测试质量
- 上轮未修复的 [RECURRING] 问题

**收敛前必跑清单（Triple-Check Gate）：**
- 所有受影响 Go 包必须执行 `go test -short -count=1 ./涉及包/...` 且全绿，包级 gate 失败即阻断
- E2E 变更必须执行 `go test -tags=integration -count=1 ./tests/e2e/...` 且全绿
- 关键链路测试禁止使用通配符状态码（`HTTP *`）、禁止把关键步骤设为可选执行
- Fake 依赖必须实际接入测试 setup 并跑通 happy path（参见 `.claude/guides/fake-env-closure.md`，仅在 fake/mock 集成测试场景按需读取）
- 以上任一条未满足，不得标记任务完成或进入提交

**争论停机准则（两种模式通用）：**
- 如果 CRITICAL 问题数连续 3 轮不变（执行者修了但审查者仍然报同样的问题），自动停机
- 停机原因标记为"审查争论停机"，需人工介入定义业务规则
- 避免两个角色在同一逻辑点上无限循环

**环境变量（模式A Bash 编排）：**
- `CLAUDE_MODEL_LIGHT`：调研/分类/plan/文档/验收等轻量阶段使用的模型（省 token），如 `sonnet`
- `CLAUDE_MODEL_CODE`：编码/开发/修复/补救等重度阶段使用的模型（编码能力强），如 `opus`
- `CLAUDE_MODEL`：全局兜底模型（不区分阶段，向后兼容）。如果设了 LIGHT/CODE 则此变量被覆盖
- `CODEX_MODEL`：指定 Codex 审查模型（如 `o3`、`o4-mini`），默认使用 Codex CLI 默认模型
- `REVIEW_SHARD_MODE`：review 分片模式（`single`/`parallel`），默认自动判断。设置后同时覆盖 develop/plan review 和 acceptance review。auto 逻辑：S/M 级强制 single；L 级在变更文件>15 或目录>4 或上轮 critical>0 时升级为 parallel；acceptance 阈值为文件>20 或目录>5。

**Agent 参数（模式B Agent 编排）：**
- 轻量阶段 Agent：`model: "sonnet"`
- 编码阶段 Agent：`model: "opus"`
- 所有 Agent：`mode: "bypassPermissions"`
- Review Agent 使用"严苛架构审查者"角色（替代 Codex 跨模型对抗，质量略低但保持隔离）

**模型分配策略（两种模式通用）：**

| 模型 | 适用阶段 |
|------|---------|
| LIGHT (sonnet) | 需求分类、技术调研、feature.md 生成、plan 迭代、任务拆分、验收门禁、文档生成、review |
| CODE (opus) | S-Track 开发、逐任务开发、Task Guardian 补救、验收补救 |

用法示例：
```bash
# 模式A：调研用 sonnet 省 token，编码用 opus
CLAUDE_MODEL_LIGHT=sonnet CLAUDE_MODEL_CODE=opus bash .claude/scripts/auto-work-loop.sh v0.0.3 asset-search

# 模式A 向后兼容：全程同一模型
CLAUDE_MODEL=sonnet bash .claude/scripts/auto-work-loop.sh v0.0.3 asset-search

# 模式B：自动检测到 claude -p 不可用时，通过 Agent tool 的 model 参数控制
# 无需环境变量，模型选择由编排协议内定
```

### 1.6 上下文修复责任（Context Repair Loop）

auto-work 中，审查者的职责不止是找代码问题，还要识别执行者因上下文不足导致的系统性失误。

**触发条件：**
- 执行者反复遗漏同类约束、边界条件或已有项目模式
- 方案/实现明显违背项目既有事实，但不是单次粗心，而是上下文没加载全
- 某类问题已经不适合只靠本轮修复解决，应该沉淀为长期规则

**处理顺序：**
1. **共享知识优先**：项目事实、术语、架构约束、通用工作约定，优先补到 `.ai/`
2. **Claude 运行时其次**：仅影响 Claude 工作方式的规则，补到 `.claude/commands/`、`.claude/skills/`、`.claude/rules/`
3. **本轮闭环必须完成**：发现上下文缺口后，不只写报告，还要在流程内补文档，再让 Claude 基于新上下文继续修复

**审查者在 review 时必须额外判断：**
- 这是代码缺陷，还是上下文缺陷？
- 如果是上下文缺陷，最合适的沉淀位置是 `.ai/constitution.md`、`.ai/context/project.md`、`.ai/skills/README.md`、`.claude/skills/*` 还是 `.claude/rules/*`

**目标：**
- 同类错误在后续 auto-work 中不再重复出现
- 让 Claude 的执行能力随着工作流迭代持续变强，而不是每次从头踩坑

### 2. 文档是唯一的跨执行单元通信方式
- 每个执行单元（CLI 进程或 Agent）的输入必须来自文件系统中的文档（需求文档、plan、task 定义等）
- 每个执行单元的输出必须持久化为文档（调研报告、plan、review 结果、代码 + commit 等）
- 禁止依赖"上一轮对话的记忆"来传递信息，所有必要信息必须写入文件
- **文档契约**：每个阶段必须明确定义输入文档和输出文档的结构

### 3. 最小化单个执行单元的职责（但不过度拆分）
- 一个执行单元只做一件事：调研、写 plan、review plan、写代码、review 代码……
- **拆分判断标准**：当一个执行单元的输入上下文 + 预期工作量可能超过上下文窗口的 60% 时才拆分
- **反面原则**：不要为了拆而拆

### 4. 编排层只做调度，不做业务
- 外层编排（Bash 脚本或主对话）只负责：阶段判断、启动执行单元、检查产出物、决定下一步
- 编排层通过检查**完成标记**来判断阶段是否完成，实现断点续跑

### 5. 质量优先的上下文管理
- **质量优先于成本**：多启动一个 CLI 进程的 token 开销远小于上下文污染导致的返工成本
- 设计每个 CLI 进程的输入时，只注入**该阶段必需的最小上下文**
- 先判定命中模块，再读取对应文档和代码；未命中的模块（如纯 Backend 任务中的 MCP / Godot）禁止预读

### 6. 容错与断点续跑
- 每个阶段完成后，必须写入明确的**完成标记**
- 检测到不完整的产出物时，编排层应删除半成品并重新执行该阶段

### 7. 原子化开发（核心原则）

源自"原子化开发环境"思想：**每次变更是最小可独立评估的单位。**

AI 的输出能力是无限的，但人的观测能力是有限的。如果不能观测一个改动的效果，就不能判断它是好是坏；如果不能自动化这个判断，就无法释放 AI 的产出能力。原子化是解决这两个问题的共同前提。

**三个前提条件：**

| 条件 | 说明 | auto-work 中的落地 |
|------|------|-------------------|
| 固定的评估基准 | 评估方法不变，变的只有被测对象 | 编译+测试作为不变的机械门禁 |
| 单一变量 | 每次只改一个东西 | 修复轮只聚焦一类问题（CRITICAL → HIGH） |
| 机械的判定标准 | 好坏有明确的数值门槛 | 编译 pass/fail + 测试通过数 + review counts |

**具体机制：**

- **Git Checkpoint**：每次修复前打 tag 快照，测试指标退步则 `git reset` 回滚（autoresearch 模式）
- **Test-as-Baseline**：编译+测试是主门禁（机械判定），AI review 是辅助（发现测试覆盖不到的设计问题）
- **Fail-Fast**：编译不过不进 review，省掉无意义的 AI 轮次（廉价检查先跑，贵的后跑）
- **Keep/Discard**：修复后测试指标不退步才保留，否则丢弃并尝试不同修复策略
- **Single-Fix**：每轮修复只聚焦一类问题，变更可归因——如果测试 break，知道是哪个修复导致的

**反模式（禁止）：**

| 别这么干 | 应该这么干 |
|---------|-----------|
| 一次修复所有 review 问题 | 一轮只修一类（CRITICAL → HIGH） |
| 修复后不跑测试直接进 review | 修复后立即编译+测试，fail-fast |
| 测试退步了继续往前走 | 回滚到 checkpoint，换策略重试 |
| AI review 作为唯一门禁 | 测试（机械）为主，review（AI）为辅 |

---

## 三级通道

auto-work 根据需求复杂度自动路由到不同通道，每个通道的流程深度和 CLI 进程预算不同。

| 维度 | S 级（Fast Track） | M 级（Standard Track） | L 级（Full Track） |
|------|-------------------|------------------------|-------------------|
| 适用场景 | 单文件改动、1-2 个函数 | 2-5 个文件、逻辑清晰 | 5+ 文件或多模块联动 |
| Plan 阶段 | 跳过，直接开发 | 单次生成 plan + Codex 单轮审查 | feature-plan-loop 迭代（最多 10 轮） |
| 任务粒度 | 单任务（≤3 文件） | 细粒度拆分（每任务 ≤3 文件、≤100 行） | 细粒度拆分（每任务 ≤3 文件、≤100 行） |
| 开发阶段 | 单次 cli_call 完成 | feature-develop-loop（最多 10 轮/任务） | feature-develop-loop（最多 15 轮/任务） |
| CLI 进程预算 | 1-3 个 | 5-14 个 | 15+ 个 |
| 提交方式 | 单次 git:commit | 逐任务 git:commit，最终 git:push | 逐任务 git:commit，最终 git:push |

补充约定：
- `M` 级虽然不做多轮 plan 迭代，但 plan 生成后仍必须经过至少一轮 Codex 审查，不能绕过 `plan-review-report.md`
- `plan/develop/acceptance` 三类 review 允许用多个 Codex 分片并发执行，再由 Claude 汇总成正式报告

### 升级机制

当低复杂度通道无法收敛时，自动升级到更高通道：

- **S → M**：S 级调研不充分、编译门禁失败（重试 1 次后）、或测试门禁失败（重试 1 次后）
- **M → L**：M 级开发达到迭代上限（10 轮）仍有失败任务，且 develop-iteration-log 中记录"达到上限"

每次升级调用 `record_upgrade` 写入日志，并更新 classification.txt（追加 `complexity=` 和 `upgraded_from=`）。一次运行最多升级 1 次（`MAX_UPGRADE_CHAIN=1`），防止无限循环。

### Task Guardian（任务完成度守卫）

在逐任务开发（阶段四）完成后，M/L 级通道会自动执行 Task Guardian 审计：

1. 读取所有 task-*.md 的状态和 `verify_commands`
2. 比对 git log 确认 commit 是否真实产生
3. 运行每个任务的 verify_commands（每条限时 60s）
4. 输出完成率报告到 `task-guardian-report.md`
5. 若未完成任务 ≤2，自动补救（重新调用 feature-develop-loop）；>2 则记录告警

---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则：**

参数格式：`<version_id> <feature_name> [需求描述（剩余部分，可选）]`

1. **第一个词**：`version_id`（版本号，如 `v0.0.3`）
2. **第二个词**：`feature_name`（功能名称，如 `asset-search`，用于创建目录）
3. **剩余部分**（可选）：补充需求描述（自然语言）

**需求来源（按优先级合并）：**
1. 自动读取 `Docs/Version/{version_id}/{feature_name}/idea.md`（如果存在）
2. 用户传入的需求描述
3. 两者都存在时，idea.md 为基础需求，用户输入为补充说明
4. 两者都不存在时，使用 AskUserQuestion 让用户提供需求

**验证：**
- 如果参数不足 2 部分，使用 AskUserQuestion 让用户补充
- 确认 `Docs/Version/{version_id}/` 目录存在（不存在则创建）

解析完成后，设定以下变量：
- `VERSION_ID` = 版本 ID
- `FEATURE_NAME` = 功能名称
- `REQUIREMENT` = 合并后的需求描述文本
- `FEATURE_DIR` = `Docs/Version/{VERSION_ID}/{FEATURE_NAME}`

---

## 执行

### 步骤零：环境预检与模式选择

参数解析完成后，**先执行预检确定执行模式**。

模式A（Bash 编排）需要 `claude -p` 和 `codex` 同时可用。使用 Bash 工具依次检测：

```bash
# 前置：幂等注入代理（主会话未设 HTTPS_PROXY 时，若本机 Clash 在跑则自动挂上）
# 这一步保证 claude -p 子进程能访问 Anthropic API，否则受限网络会直接 403 导致无头模式不可用
source .claude/scripts/ensure-proxy.sh

# 检测 1：claude -p 子进程可用性
CLAUDE_OK=0
claude -p "reply OK" --permission-mode bypassPermissions > /dev/null 2>&1 && CLAUDE_OK=1

# 检测 2：codex CLI 可用性（仅 claude 通过时才检测）
CODEX_OK=0
if [ "$CLAUDE_OK" = "1" ] && command -v codex > /dev/null 2>&1; then
    codex --help > /dev/null 2>&1 && CODEX_OK=1
fi

# 输出路由决策
if [ "$CLAUDE_OK" = "1" ] && [ "$CODEX_OK" = "1" ]; then
    echo "ROUTE_MODE_A"
else
    echo "ROUTE_MODE_B"
    [ "$CLAUDE_OK" = "0" ] && echo "REASON: claude -p unavailable"
    [ "$CLAUDE_OK" = "1" ] && [ "$CODEX_OK" = "0" ] && echo "REASON: codex unavailable (review will use Agent)"
fi
```

根据结果选择执行模式：
- **ROUTE_MODE_A**（claude + codex 均可用）→ 模式A（Bash 编排，完整能力，双模型对抗审查）
- **ROUTE_MODE_B**（claude 或 codex 不可用）→ 模式B（Agent 编排，保持上下文隔离，review 由 Agent 执行）

---

### 模式A：Bash 编排（ROUTE_MODE_A — claude + codex 均可用）

使用 Bash 工具执行以下命令启动全自动流程：

```bash
# 有用户补充需求时
bash .claude/scripts/auto-work-loop.sh "{VERSION_ID}" "{FEATURE_NAME}" "{用户输入的补充需求}"

# 无补充需求时（纯 idea.md 驱动）
bash .claude/scripts/auto-work-loop.sh "{VERSION_ID}" "{FEATURE_NAME}"
```

**注意**：idea.md 的读取和合并由脚本内部处理，command 只传用户输入的补充部分。

脚本会自动完成以下阶段：

#### 阶段零：需求分类
- **research**（需要调研）：全新系统设计、需要技术选型、涉及不熟悉领域
- **direct**（直接开发）：Bug 修复、已有系统优化/扩展、需求明确且有参考实现

#### 阶段零-B：技术调研（仅 research 类型）
- 复用 `research-loop.sh` 进行自动调研 + Review 迭代（最多 6 轮）

#### 阶段一：生成 feature.md
- 根据需求描述自动生成结构化的 `feature.md`（Markdown 格式）
- 生成后检查 `## 备注` 章节：若有 `[待确认]` 项，暂停流程，向用户展示并等待确认后再继续
- 用户答复保存至 `{FEATURE_DIR}/pending-items-response.md`（断点续跑时跳过）

#### 阶段二：Plan 迭代循环（输出 plan.md）
- 复用 `feature-plan-loop.sh` 的完整流程
- 自动创建方案 → Review → 修复 → 直到收敛

#### 阶段三：任务拆分（细粒度，一任务一功能一commit）
- 将 plan.md 拆分为**细粒度**的独立任务，每个任务 = 一个独立功能点 = 一个 git commit
- **单一职责**：每个任务只做一件事（一个接口、一个组件、一层数据模型、一组配置）
- 粒度约束：每任务 ≤3 个实现文件、≤100 行代码改动（宪法 2.4 伴生测试 router_test.go/.hurl 不计入文件数）
- 拆分检验：如果一个任务的 commit message 需要用"和"连接两个动作，说明应继续拆分
- **宁可多拆不要少拆**：粒度越细 git 历史越清晰，每个任务的 name 应能直接作为 commit message 描述
- 每个任务输出为 `tasks/task-NN.md`

#### 阶段四：逐任务开发 + 逐任务 commit
- 复用 `feature-develop-loop.sh` 进行迭代开发
- 自动编码 → **编译验证 + 单元测试** → Review → 修复 → 直到收敛
- **HTTP 端点测试铁律（宪法 2.4）：** 新增任何 HTTP 端点必须同步添加 `router_test.go` 路由注册测试 + `Backend/tests/smoke/` Hurl 冒烟测试
- **每完成一个任务就执行 git:commit**（遵循 `<type>(<scope>): <描述>` 规范），确保每个任务对应一个独立的 commit
- 如果 Codex 在 review 中判断存在"上下文缺口"，流程必须先补齐 `.ai/` 或 `.claude/` 文档，再继续开发收敛

#### 阶段四-C：验收门禁（Acceptance Gate） — 不可跳过
- 回读 `feature.md` 的每条 REQ 及其验收条件
- 逐条验证 4 个维度：代码实现、配置完整性、测试覆盖、冒烟可达性
- 输出 `acceptance-report.md`，标记每条 REQ 为 PASS/FAIL
- **P0 需求必须全部 PASS**，P1 允许最多 1 条 FAIL，P2 不阻塞
- 验收失败时触发 1 轮自动补救 → 重新验收
- **只有验收通过才进入阶段五和六**，否则阻断并告警"需人工介入"

#### 阶段五：生成模块文档（仅验收通过时执行）
- 基于实际代码生成架构总览、核心流程、关键文件索引等文档
- 归档到 `Docs/Engine/` 对应目录

#### 阶段六：git:push 推送到远程仓库（仅验收通过时执行）
- 所有任务完成且验收通过后，执行 git:push 将全部 commit 推送到远程仓库
- 仅推送有新 commit 时，无新 commit 则跳过
- 禁止 force push

**只有从配置、代码到测试全流程跑通（验收门禁 ALL_REQ_ACCEPTED），才算功能正式完成。**

---

### 模式B：Agent 编排（ROUTE_MODE_B — claude 或 codex 不可用）

当 `claude -p` 子进程或 `codex` CLI 不可用时（沙箱环境、IDE 插件、权限限制、未安装等），使用 Agent tool 编排替代。

**读取 `.claude/contracts/auto-work-agent-orchestration.md` 并严格按照其中的流程执行。**

核心差异：
- 每个原本由 `cli_call`（`claude -p`）执行的阶段改为 `Agent(mode: "bypassPermissions")` 调用，确保上下文隔离
- 每个原本由 `codex_review_exec` 执行的 review 改为独立 `Agent(...)` 以"严苛架构审查者"角色执行
- 编译/测试门禁仍由当前对话的 Bash 工具直接执行（机械判定不需要隔离）
- 三级通道（S/M/L）、升级机制、断点续跑逻辑保持一致
- 所有文件产物（classification.txt、feature.md、plan.md、tasks/、acceptance-report.md 等）格式完全相同，两种模式可互操作

**Agent 模式的上下文隔离保证：**
- 每个 Agent 拥有独立上下文窗口，不继承主对话的历史
- Agent 之间不共享运行时上下文，只通过文件系统通信
- 主对话（编排者）只做调度、门禁检查和文件验证，不堆积业务逻辑上下文

---

## 注意事项

- **模式A**：需要 `claude` CLI 和 `codex` CLI 可用（Review 由 Codex 执行）
- **模式B**：仅需 Agent tool 可用（Review 由独立 Agent 执行，质量略低于跨模型对抗但保持上下文隔离）
- 全程无人工干预，所有决策自主完成
- 总进度日志：`{FEATURE_DIR}/auto-work-log.md`
- 任务清单：`{FEATURE_DIR}/tasks/README.md`
- 中断恢复：重新运行时会跳过已完成的阶段和任务（基于文件/状态检测，两种模式通用）
