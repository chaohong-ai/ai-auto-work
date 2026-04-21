# Auto-Work Agent 编排协议

> 本协议在 `claude -p` 子进程不可用时被 `auto-work.md` 引用，作为降级执行方案。
> 每个阶段使用独立 Agent 执行，确保上下文窗口隔离。

## 编排总则

1. **上下文隔离**：每个可独立完成的阶段使用 `Agent(mode: "bypassPermissions")` 执行，Agent 之间零上下文共享
2. **文件通信**：Agent 的输入和输出通过 `FEATURE_DIR` 下的文件交换，编排者（当前对话）负责验证产出物
3. **门禁直控**：编译/测试等机械门禁由编排者直接用 Bash 执行，不委托给 Agent
4. **Review 降级**：由于 Codex CLI 不可用，review 由独立 Agent 以"严苛架构师审查者"角色执行。单模型 review 质量低于双模型对抗，但远优于无 review 或上下文污染
5. **模型选择**：轻量阶段（分类/调研/plan/文档/验收）用 `model: "sonnet"`，编码阶段（开发/修复/补救）用 `model: "opus"`
6. **串行编排**：阶段之间严格串行（上一阶段的输出是下一阶段的输入），同一阶段内的独立 Agent 可并行
7. **断点续跑**：每个阶段执行前检查产出物是否已存在，已存在则跳过

## 前置准备

编排者在开始阶段编排之前：

1. 确认以下变量已解析（由 auto-work.md 参数解析完成）：
   - `VERSION_ID`, `FEATURE_NAME`, `REQUIREMENT`, `FEATURE_DIR`
2. 创建工作目录：`mkdir -p {FEATURE_DIR}`
3. 合并需求来源：读取 `{FEATURE_DIR}/idea.md`（如存在）与用户输入合并
4. 初始化日志文件 `{FEATURE_DIR}/auto-work-log.md`（格式同 Bash 模式）
5. **记录功能级基线**：在任何开发工作开始前，用 Bash 执行 `git rev-parse HEAD` 并保存为 `PRE_DEV_HEAD_ALL`。此基线用于验收门禁和 Task Guardian，确保审查范围覆盖整个功能的所有变更，而非仅最后一个任务

---

## 阶段零：需求分类

**断点检查**：`{FEATURE_DIR}/classification.txt` 存在则跳过，直接读取 type 和 complexity。

**执行**：

```
Agent({
  description: "需求分类",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名资深全栈开发工程师。请分析以下需求，判断它的工作类型和复杂度。

需求内容：
{REQUIREMENT}

请搜索项目中相关代码，然后判断：

**type**:
- research（需要调研）：全新系统设计、需要技术选型、不熟悉领域
- direct（直接开发）：Bug修复、已有系统优化/扩展、需求明确

**complexity**:
- S（小型）：单文件修改，1-2个函数
- M（中型）：2-5个文件，模式清晰
- L（大型）：5+文件或多模块联动

偏向 direct + 较低复杂度。

将结果写入 {FEATURE_DIR}/classification.txt，严格两行格式：
type=research 或 type=direct
complexity=S 或 complexity=M 或 complexity=L

不要输出其他内容。"
})
```

**验证**：读取 classification.txt，解析 `WORK_TYPE` 和 `COMPLEXITY`。无效值默认 `direct` + `L`。

**路由参数**：

| 复杂度 | PLAN_MAX_ROUNDS | DEV_MAX_ROUNDS |
|--------|----------------|----------------|
| S | 0 (跳过 plan) | 1 (单次开发) |
| M | 2 (生成+单轮review) | 10 |
| L | 10 | 15 |

---

## 阶段零-B：技术调研（仅 type=research 时执行）

**断点检查**：`Docs/Research/{FEATURE_NAME}/research-result.md` 存在则跳过。

### S 级调研：单次 Agent

```
Agent({
  description: "S级快速调研",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "请对以下需求进行快速技术调研，将结论写入 Docs/Research/{FEATURE_NAME}/research-result.md。

需求：{REQUIREMENT}

规则：
1. 搜索项目代码了解现有实现
2. 快速判断可行性和实现路径
3. 将调研结论写入文件
4. 不需要多轮迭代，一次输出即可"
})
```

### M/L 级调研：迭代循环（最多 6 轮）

编排者循环执行以下步骤，`round` 从 1 开始：

**奇数轮（执行）**：

```
Agent({
  description: "调研执行 R{round}",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名技术调研工程师。{round==1 ? '请对以下需求进行技术调研' : '请根据 review 反馈改进调研报告'}。

需求：{REQUIREMENT}
{round > 1 ? '上轮 review 反馈：读取 Docs/Research/{FEATURE_NAME}/research-review.md' : ''}

输出写入 Docs/Research/{FEATURE_NAME}/research-result.md。
搜索项目代码和相关技术方案，给出推荐方案、排除方案及理由。"
})
```

**偶数轮（审查）**：

```
Agent({
  description: "调研审查 R{round}",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名严苛的技术审查者。请审查调研报告，找出信息不足、方案遗漏、结论不合理之处。

读取 Docs/Research/{FEATURE_NAME}/research-result.md

输出写入 Docs/Research/{FEATURE_NAME}/research-review.md，格式：
## 审查结论
（逐点评估）

## Context Repairs
- 无（或具体建议）

最后一行输出：<!-- counts: critical=X important=Y nice=Z -->

收敛标准：critical=0 且 important≤1"
})
```

**收敛判断**：编排者读取 review 文件末尾的 counts 行，如果 `critical=0 && important<=1` 则终止循环。

**调研完成后**：将调研结论追加到 REQUIREMENT 变量中供后续阶段使用。

---

## 阶段一：生成 feature.md

**断点检查**：`{FEATURE_DIR}/feature.md` 存在则跳过。

```
Agent({
  description: "生成 feature.md",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "请根据以下需求生成功能需求文档，写入 {FEATURE_DIR}/feature.md。

需求输入：
{REQUIREMENT}

如果需求涉及已有系统，搜索相关代码了解现有实现。

输出格式：
# {功能名称}
## 概述 — 一段话描述功能目标
## 需求列表 — 每条 REQ-NNN: {标题} [P0/P1/P2]，含分类、模块、描述、验收条件
## 交互设计 — 用户使用流程
## 技术约束 — 表格列出
## 依赖关系
## 备注 — 不确定项标注 [待确认]

规则：
- 不凭空捏造用户没提到的大功能
- 每条 requirement 必须带验收条件
- P0=核心必做, P1=重要, P2=可选"
})
```

**验证**：确认 `{FEATURE_DIR}/feature.md` 存在且非空。不存在则报错终止。

**待确认项检查**（验证通过后立即执行）：
- 断点检查：`{FEATURE_DIR}/pending-items-response.md` 存在则跳过
- 编排者读取 `{FEATURE_DIR}/feature.md` 的 `## 备注` 章节，提取所有含 `[待确认]` 的行
- 若无 `[待确认]` 项 → 继续
- 若有 → 使用 `AskUserQuestion` 工具将待确认项展示给用户，等待回答（题目：feature.md 中有以下待确认项，请确认后继续）
- 将用户答复写入 `{FEATURE_DIR}/pending-items-response.md`（格式：# 待确认项用户答复 / ## 待确认项 / ... / ## 用户答复 / ...）
- 若用户提供了实质性答复（非空/非"跳过"）→ 启动 Agent 将答复更新到 feature.md：
  ```
  Agent({
    description: "更新 feature.md 待确认项",
    mode: "bypassPermissions",
    model: "sonnet",
    prompt: "读取 {FEATURE_DIR}/feature.md 和 {FEATURE_DIR}/pending-items-response.md。
  将 ## 备注 章节中标注为 [待确认] 的条目，根据用户答复更新为具体决策（把 [待确认] 替换为 [已确认: 具体内容]）。
  保持文件其余内容不变，直接写文件。"
  })
  ```

---

## 阶段二：Plan 迭代

**断点检查**：`{FEATURE_DIR}/plan.md` 存在则跳过。

### S 级：跳过

S 级不生成 plan，直接进入阶段四 S-Track。

### M 级：单次生成 + 单轮审查

**生成 plan**：

```
Agent({
  description: "生成 plan.md (M级)",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "读取 .claude/contracts/feature-plan/expand.md 了解 plan 生成的详细规范。

读取以下文件建立上下文：
1. {FEATURE_DIR}/feature.md — 功能需求
2. .ai/constitution.md — 项目宪法

先判定命中模块，再搜索对应模块目录的现有实现。
未命中的模块不要预读。

基于 feature.md 生成技术方案，写入 {FEATURE_DIR}/plan.md。
plan 只覆盖命中模块，未命中模块写 N/A。"
})
```

**审查 plan**：

```
Agent({
  description: "审查 plan.md (M级)",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名严苛的架构审查者。请审查技术方案。

读取 .ai/context/reviewer-brief.md 了解审查硬约束。
读取 {FEATURE_DIR}/plan.md 和 {FEATURE_DIR}/feature.md。
搜索项目代码验证方案可行性。

输出写入 {FEATURE_DIR}/plan-review-report.md，格式：
## Critical
## Important
## Nice to have
## Context Repairs
- 无（或具体建议）

最后一行：<!-- counts: critical=X important=Y nice=Z -->"
})
```

**如果 critical > 0**：启动一轮修复 Agent 修改 plan.md，然后继续。

### L 级：迭代循环（最多 PLAN_MAX_ROUNDS 轮）

编排者循环执行：

**奇数轮（生成/修复 plan）**：

```
Agent({
  description: "Plan 创建/修复 R{round}",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "读取 .claude/contracts/feature-plan/expand.md 了解规范。

{round==1 ? '基于以下文件创建技术方案' : '基于 review 反馈修复技术方案'}：
1. {FEATURE_DIR}/feature.md
2. .ai/constitution.md
{round > 1 ? '3. {FEATURE_DIR}/plan-review-report.md — 上轮审查反馈，聚焦 Critical 和 Important 问题' : ''}

输出写入 {FEATURE_DIR}/plan.md。
先判定命中模块再搜索代码。未命中模块不预读。"
})
```

**偶数轮（审查 plan）**：同 M 级审查 Agent。

**收敛判断**：`critical=0 && important<=2` 则终止。连续 3 轮 critical 不变则停机。

**Context Repair**：如果 review 中包含 `## Context Repairs` 且有实质内容，启动一个 Agent 执行上下文修复（同 Bash 模式的 `apply_context_repairs`）。

---

## 阶段三：任务拆分

**断点检查**：`{FEATURE_DIR}/tasks/task-01.md` 存在则跳过。

```
Agent({
  description: "任务拆分",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名资深全栈开发工程师。请将技术方案拆分为可独立开发、验证、提交的任务。

核心原则：一个任务 = 一个独立功能点 = 一个 git commit。

读取以下文件：
1. {FEATURE_DIR}/plan.md — 技术方案
2. {FEATURE_DIR}/feature.md — 功能需求
3. 如果 {FEATURE_DIR}/plan/ 子目录存在，也读取子文件

拆分规则：
- 单一职责：每个任务只做一件事
- 每任务 ≤3 个实现文件、≤100 行代码改动
- 按依赖顺序排列（被依赖的在前）
- 宁可多拆不要少拆

每个任务输出为 {FEATURE_DIR}/tasks/task-NN.md（NN 从 01），格式：

---
name: 简短任务名
status: pending
estimated_files: N
estimated_lines: N
verify_commands:
  - \"go build ./...\"
depends_on: []
---

## 范围
- 新增/修改: path — 职责

## 验证标准
- 编译通过
- 具体验证点

## 依赖
- 无 / 依赖 task-NN

同时生成 {FEATURE_DIR}/tasks/README.md 索引文件。"
})
```

**验证**：确认至少存在一个 `task-*.md` 文件。

---

## 阶段四：逐任务开发 + 提交

编排者按顺序遍历 `{FEATURE_DIR}/tasks/task-*.md`（已 completed 的跳过）。

### S 级 Fast Track

S 级不做任务拆分，直接单次开发：

```
Agent({
  description: "S-Track 直接开发",
  mode: "bypassPermissions",
  model: "opus",
  prompt: "请直接实现以下需求。

需求内容：
{REQUIREMENT}

规则：
1. 搜索项目中相似的实现作为参考模板
2. 直接编写代码实现需求
3. 完成后确保编译通过：
   - Go: cd Backend && go build ./...
   - TS: cd MCP && npx tsc --noEmit（如涉及）
   - TS: cd Frontend && npx tsc --noEmit（如涉及）
4. 为新增代码编写测试
5. 不要生成 plan.md 或 feature.md"
})
```

**然后**：编排者执行编译门禁（Bash），失败则启动修复 Agent（最多 1 轮），仍失败则升级到 M 级。

**S 级提交**：编排者使用 Bash 执行 `git add` + `git commit`。

### M/L 级逐任务开发

对每个 pending 的 task-NN.md，执行开发迭代循环：

**步骤 0：记录任务级基线**

每个任务开发前，编排者用 Bash 执行 `git rev-parse HEAD` 并保存为 `PRE_TASK_HEAD`。此基线用于：
- 步骤 4 的代码审查（审查仅本任务的变更，不混入其他任务）
- 步骤 6 的提交验证

#### 步骤 1：开发实现

```
Agent({
  description: "实现 {TASK_BASENAME}",
  mode: "bypassPermissions",
  model: "opus",
  prompt: "你是一名资深全栈工程师。请实现以下任务。

任务文件：读取 {TASK_FILE}
技术方案：读取 {FEATURE_DIR}/plan.md
需求文档：读取 {FEATURE_DIR}/feature.md
项目宪法：读取 .ai/constitution.md

{round > 1 ? '上轮 review 反馈：读取 {FEATURE_DIR}/develop-review-report-{TASK_BASENAME}.md，只修复 Critical 问题' : ''}

规则：
1. 先搜索相似实现作为参考
2. 只做任务要求的事，不超范围
3. 编码风格与同目录已有代码一致
4. 新增 HTTP 端点必须同步添加 router_test.go + smoke/*.hurl 测试
5. 完成后运行编译验证"
})
```

#### 步骤 2：编译门禁（编排者直接 Bash）

```bash
# 按变更模块选择性编译
cd Backend && go build ./... 2>&1 | tail -20    # Go 模块
cd MCP && npx tsc --noEmit 2>&1 | tail -20      # MCP 模块（如涉及）
cd Frontend && npx tsc --noEmit 2>&1 | tail -20  # 前端（如涉及）
```

编译失败 → 启动修复 Agent（同步骤 1 但 prompt 聚焦编译错误），最多 2 次重试。

#### 步骤 3：测试门禁（编排者直接 Bash）

```bash
# 检测变更的 Go 包并运行测试
cd Backend && go test -short -count=1 ./affected_pkg/... 2>&1 | tail -30
# TS/Python 类似
```

测试失败 → 启动修复 Agent，最多 3 次重试。

#### 步骤 4：代码审查

```
Agent({
  description: "审查 {TASK_BASENAME}",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名严苛的架构审查者，负责找出开发者的盲区。

读取 .ai/context/reviewer-brief.md 了解审查硬约束。

审查范围：
1. 任务定义：{TASK_FILE}
2. 代码变更：运行 git diff {PRE_TASK_HEAD}..HEAD 查看本任务的全部变更（{PRE_TASK_HEAD} 是任务开发前的基线）
3. 技术方案：{FEATURE_DIR}/plan.md

重点关注：
- 架构偏差、依赖方向、接口一致性
- 并发竞态、资源泄漏、异常路径
- 测试覆盖、边界条件、回归风险
- [RECURRING] 标记：如果是之前 review 已提过的问题

输出写入 {FEATURE_DIR}/develop-review-report-{TASK_BASENAME}.md

格式：
## Critical
## High
## Medium
## Context Repairs
- 无（或具体建议）

最后一行：<!-- counts: critical=X high=Y medium=Z -->"
})
```

#### 步骤 5：收敛判断

编排者读取 review report 末尾 counts：
- `critical=0 && high<=2` → 收敛，进入提交
- 否则 → 回到步骤 1 继续修复（round++）
- 连续 3 轮 critical 不变 → 停机，标记任务 failed
- 达到 DEV_MAX_ROUNDS → 停止

#### 步骤 6：Git 提交

编排者直接用 Bash 提交：

```bash
git add <相关文件>
git commit -m "$(cat <<'EOF'
<type>({FEATURE_NAME}): {TASK_NAME}

{TASK_BASENAME} · {VERSION_ID}

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

验证 HEAD 是否变化，确认 commit 成功。

#### Context Repair

如果 review 包含实质性 Context Repairs，启动 Agent 执行上下文文档修复：

```
Agent({
  description: "上下文修复",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "读取 {REVIEW_FILE} 的 ## Context Repairs 段，将需要长期固化的内容落实到仓库文档。
优先更新 .ai/（项目事实），其次 .claude/（Claude 专属规则）。
在 {FEATURE_DIR}/context-repair-log.md 追加记录。"
})
```

---

## 阶段四-B：Task Guardian（M/L 级）

**条件**：非 S 级且有已完成任务。

```
Agent({
  description: "Task Guardian 审计",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名严格的质量审计员。请审计任务完成情况。

1. 读取 {FEATURE_DIR}/tasks/ 下所有 task-*.md
2. 执行 git log --oneline {PRE_DEV_HEAD_ALL}..HEAD 查看本功能全部提交
3. 执行 git diff {PRE_DEV_HEAD_ALL}..HEAD --stat 查看本功能全部变更文件
4. 对每个任务检查：status、git commit 是否存在、文件是否变更
5. 执行每个任务的 verify_commands（每条 timeout 60s）

输出 {FEATURE_DIR}/task-guardian-report.md，包含完成率和详情。
最后一行输出：ALL_TASKS_COMPLETE / REMEDIATION_NEEDED: task-NN / MANUAL_INTERVENTION_NEEDED"
})
```

**补救**：如果 REMEDIATION_NEEDED 且未完成任务 ≤2，对未完成任务重新执行开发迭代。

---

## 阶段四-C：验收门禁（不可跳过）

**条件**：有已完成任务。

```
Agent({
  description: "验收门禁",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名独立验收审查者。请逐条验证需求实现。

读取 .ai/context/reviewer-brief.md 了解审查硬约束。

输入：
1. {FEATURE_DIR}/feature.md — 需求文档
2. {FEATURE_DIR}/plan.md — 技术方案（如存在）
3. git diff {PRE_DEV_HEAD_ALL}..HEAD — 整个功能的全部代码变更（PRE_DEV_HEAD_ALL 是功能开发前的基线，确保审查覆盖所有任务的变更）

对每条 REQ，验证 4 个维度：
- 代码实现：grep 验证关键函数/路由是否存在
- 配置完整：config/env/docker 是否更新
- 测试覆盖：核心函数是否有测试，新端点是否有 router_test + hurl
- 冒烟验证：如有 hurl 文件，尝试运行（不可运行标 SKIP）

输出写入 {FEATURE_DIR}/acceptance-report.md。

P0 需求必须全部 PASS。
最后一行输出：ALL_REQ_ACCEPTED / REMEDIATION_NEEDED: REQ-NNN / CANNOT_VERIFY

必须输出 ## Context Repairs 段。"
})
```

**验收补救**：如果 REMEDIATION_NEEDED，启动一轮修复 Agent（model: opus）修复失败的 REQ，然后重新验收。

**仅验收通过才进入阶段五和六。**

---

## 阶段五：生成模块文档（仅验收通过）

```
Agent({
  description: "生成模块文档",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "请为刚完成的功能生成模块文档，归档到 Docs/Engine/ 目录。

读取：
1. {FEATURE_DIR}/feature.md
2. {FEATURE_DIR}/plan.md
3. {FEATURE_DIR}/tasks/ 下的任务文件
4. 实际修改的代码文件

确定归属模块，生成/更新文档：概述、架构设计、核心流程、关键文件索引、注意事项。
文档内容基于实际代码，不编造文件路径。"
})
```

编排者用 Bash 提交文档变更到 Git。

---

## 阶段六：推送到远程仓库（仅验收通过）

编排者直接用 Bash 执行：

```bash
# 检查是否有新 commit
NEW_COMMITS=$(git log --oneline origin/$(git branch --show-current)..HEAD 2>/dev/null | wc -l)
if [ "$NEW_COMMITS" -gt 0 ]; then
    git push  # 或 git push -u origin <branch> 如无追踪分支
fi
```

禁止 force push。

---

## 升级机制

与 Bash 模式一致：

- **S → M**：S 级调研不充分 / 编译门禁重试后仍失败 / 测试门禁重试后仍失败
- **M → L**：M 级开发达到迭代上限仍有失败任务

升级后更新 `classification.txt`，调整迭代参数，重新执行相应阶段。
一次运行最多升级 1 次。

---

## 日志记录

编排者在每个阶段结束后向 `{FEATURE_DIR}/auto-work-log.md` 追加日志行（与 Bash 模式格式一致）：

```
| 阶段名 | 状态 | 开始时间 | 结束时间 | 耗时 | Agent调用数 | 备注 |
```

流程结束后追加总结段。

---

## 与 Bash 模式的关键差异

| 维度 | Bash 模式 | Agent 模式 |
|------|-----------|------------|
| 执行隔离 | `claude -p` 独立进程 | `Agent(...)` 独立上下文 |
| Review 角色 | Codex CLI（跨模型对抗） | Agent 严苛审查者（同模型，质量略低） |
| Trace 落盘 | JSONL 自动记录 | 无（依赖 auto-work-log.md） |
| 并行 Review 分片 | 3 个 Codex 并行进程 | 单个 Agent 审查（简化） |
| 编排层 | Bash 脚本 | Claude 主对话（按本协议指令编排） |
| 适用场景 | 正常终端环境 | 沙箱/IDE/受限环境 |
