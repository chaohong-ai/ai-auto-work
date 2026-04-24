# Shared AI Workspace

这里是 GameMaker 的共享 AI 上下文层，目标是让不同 agent 在同一仓库内读取一致的项目事实、工程原则和工作约定。

## 目录说明

- `context/project.md`: 项目背景、架构、技术栈、目录语义（精简版，始终加载）
- `context/backend-lifecycle.md`: Backend Session / Container / Shutdown 生命周期约束（按需加载）
- `context/reviewer-brief.md`: Develop/Plan Review 统一审查规则 — **所有 reviewer 在执行 review 前必须读取**
- `context/auto-work-gates.md`: auto-work / manual-work / feature-develop 进入 reviewer 前的**生成侧机械门禁清单**（G1-G6，含 phase-switch 完整性与 stale develop-input 阻断、写盘后再校验 post-write validator），在 `.claude/commands/auto-work.md` 权限受限时作为权威落点 — **所有执行 auto-work 流程的 agent 在生成 review-input 前必须执行；review-input 落盘后、调用 reviewer 前必须再跑 G6 并把 stdout 追加到迭代日志**
- `constitution.md`: 项目级工程宪法核心原则（精简版，始终加载）
- `constitution/backend.md`: Go 并发、锁、连接、ctx 取消、goroutine 信号化详细规则（按需加载）
- `constitution/testing-review.md`: 测试验收、Plan Review 硬检查、Develop 产物核验（按需加载）
- `constitution/cross-module.md`: 跨模块 API 通信规则（按需加载）
- `constitution/engine.md`: Engine 多平台导出规则（按需加载）
- `skills/README.md`: 共享 skill 索引与兼容约定

## 分层约定

- `.ai/`: 跨 agent 共享知识，作为单一事实源
- `.claude/`: Claude Code 专用运行时层
- `CLAUDE.md`: Claude 的入口文件，先指向共享层，再补充 Claude 层
- `AGENTS.md` / `CODEX.md`: Codex 的入口文件，指向共享层

## 按需加载策略

核心原则文件（`constitution.md` + `context/project.md`）始终加载，提供基本工程约束。

详细规则按模块拆分到子目录，仅在涉及对应模块时加载：
- 改 Backend → 加载 `constitution/backend.md` + `context/backend-lifecycle.md`
- 做 Review → 加载 `constitution/testing-review.md` + `context/reviewer-brief.md`
- 改跨模块 API → 加载 `constitution/cross-module.md`
- 改 Engine → 加载 `constitution/engine.md`

## 能共享与不能共享的内容

- 可以共享：项目知识、工程宪法、目录语义、工作流文档、skill 文档、架构文档
- 不能完全仓库内共享：运行时权限、hooks、生效方式、原生 command/skill 装载机制
- 因此本仓库的策略是"共享知识与规则，保留各 agent 的运行时实现差异"

## 维护规则

当项目知识发生变化时：

1. 先更新 `.ai/`
2. 再检查 `.claude/` 中是否有需要同步的运行时说明
3. 避免在多个位置分别维护同一份项目事实
4. **任务文件（`task-*.md`）是局部实现描述，不得单方面覆盖 `.ai/` 中已固化的跨模块合同**（如公开 API 命名、端口、字段名）；若 task 文件与 `.ai/` 冲突，执行者以 `.ai/` 为准；确需修改合同，必须先更新 `.ai/` 后再落地代码（详见 `.claude/rules/context-repair.md`）

## 上下文修复策略

如果某个 agent 在工作中反复犯同类错误，优先判断是否为"上下文缺口"。

- 项目事实和通用约束缺失：更新 `.ai/`
- Claude 专属工作流或技能缺失：更新 `.claude/`
- 不要只在单次 review 报告里指出问题而不沉淀规则

### 生成侧 vs 审查侧双侧门禁

同类错误连续在 reviewer 报告中出现（≥2 次）时，规则不能只加到 reviewer 侧：

- **权威语义**永远先写入 `.ai/constitution/*.md` 或 `.ai/context/reviewer-brief.md`
- **生成侧机械门禁**的权威清单落在 `.ai/context/auto-work-gates.md`（全 agent 可读、允许写入，不受 `.claude/` 权限约束）；`.claude/commands/auto-work.md` 在下次权限窗口开放时仅以"引用 `auto-work-gates.md`"方式接入，不重复语义
- **审查侧兜底**保留在 `.ai/context/reviewer-brief.md` §零-B，作为双保险

只有 reviewer 侧规则而无生成侧门禁 → 错误只能"事后发现"，会持续出现直到 reviewer 兜底。若 `.claude/commands/auto-work.md` 因权限限制暂未引用 `auto-work-gates.md`，**必须在 `context-repair-log.md` 显式记录"权威语义已在 .ai/context/auto-work-gates.md 落地，auto-work 引用延后"**，不得视为 CR 已关闭；同时执行者在读取 `auto-work-gates.md` 时仍须手动执行全部门禁。

**工作流执行缺口识别（write-path enforcement failure）**（task-32 Round 5 `[RECURRING]` 跨 5 轮触发；v0.0.1 animator task-01 round 4 / task-02 round 4 / task-03 round 4 / task-07 CR-1 / **task-08 CR-1** RECURRING 复现）：当同一 CR 的目标文件是 `.claude/commands/*.md` 或编排脚本本身（而非 `.ai/` 权威文档），且上一轮 review 报告已记录"权威规则已存在 / 生成侧未执行"时，CR 性质判定为"**工作流执行缺口（write-path enforcement failure）**"而非"上下文缺失"。此时不得再复制权威语义到 `.ai/`（已覆盖），应直接在工作流入口绑定 **enforcement 语义**（退出码 → 阻断 / 禁止写 `status=PASS` / 删除半成品回退 developing / **写盘后必跑 G6 post-write validator（含 `## Gate Results` 必须位于 `## Changed Files` / `## Git Diff --stat` 之前的位序校验）** / **迭代日志 FIXED 声称 × 落盘 review-input 交叉核对**）；task-01 round 4 实证：即便 `reviewer-brief.md §零-B 第 8 条` 与 G6(a) 同时固化了位序规则，只要 `.claude/commands/auto-work.md §收敛前必跑清单` 不显式引用 G6 执行，生成器仍会产出缺 `## Gate Results` 的 `review-input-develop.md`，同一 Critical 跨轮循环阻塞 —— 根本修补点始终在工作流入口、不在规则文本。若入口文件 Edit 权限仍被拒，每次必须重新在 `context-repair-log.md` 登记 fallback，累计阻塞次数用于支撑后续权限开通证据，不得以"上轮已记录"为由省略本轮 fallback 登记。

**迭代日志可信度约束**（v0.0.1 animator task-03 round 4 C1 / C2 RECURRING）：`develop-iteration-log-task-NN.md` 中"上轮 CR 已 FIXED"声明**不是**本轮合规的证据，只是声称；真正的证据来源仅为写盘后的 `review-input-*.md` 实际内容。G6 post-write validator 必须对 log 声称的每一条 FIXED（Gate Results 已加入 / 三源已重采 / 未跟踪产物已列入 Changed Files / `-race` 已跑）逐条与磁盘内容交叉比对，不一致即 `FIXED_CLAIM_MISMATCH` 阻断；reviewer 侧遇"日志 FIXED 但文件仍不合规"组合，直接计入宪法 §8 门禁。

**reviewer `REVIEW_BLOCKED` 必须以机器证据形式记录到迭代日志**（v0.0.1 animator task-05 CR-2）：reviewer 返回 `REVIEW_BLOCKED: <SIGNAL>` 时，`develop-iteration-log-task-NN.md` 仅有 baseline 行或人工叙述不构成合规；本轮日志必须追加完整的 `[BLOCKED: <SIGNAL>]` 记录（触发的 validator 命令逐字 + 失败 stdout + 重新生成证据 —— 如新的 `git rev-parse --show-toplevel` / `## Gate Results` 字段值 / 落盘文件摘要）。缺记录 → `BLOCKED_NOT_RECORDED_AS_ENFORCEMENT`，reviewer 下一轮判 Critical [RECURRING] 并计入宪法 §8 门禁。

**`.ai/` 自包含 × 多 `.ai/` 树同步**（v0.0.1 animator task-05 CR-1）：本仓库存在多棵独立的 `.ai/` 树（至少 root `.ai/` 与 Template/TP-UGC-3D/.ai/），两者平行独立、互不隐式继承。任何 `.ai/` 文件（`constitution.md` / `README.md` / `context/*.md` / `constitution/*.md`）对 `.ai/` 子路径的引用，**必须**在该文件所在 `.ai/` 树内可达；root 侧新增或改名权威文件（如 `auto-work-gates.md`）时，同一次改动内必须同步到每一棵已存在的 `.ai/` 树（全量复制或指针文件二选一），不得只写 root 留 Template 断引用。下一轮 reviewer 在工作区 `.ai/` 树中找不到引用路径 → 判 `AUTHORITATIVE_REFERENCE_BROKEN` / `GATE_RULES_MISSING_FROM_WORKSPACE` Critical 计入宪法 §8 门禁（task-05 实证：root `.ai/context/auto-work-gates.md` 存在但 Template `.ai/context/auto-work-gates.md` 缺失，导致 reviewer 阻断且缺机械门禁）。

## auto-work 共享约定

- `auto-work` 里的执行者默认是 Claude，reviewer 默认是 Codex
- `M` 级需求的 plan 虽然是单次生成，但仍必须经过至少一轮 Codex plan review
- `plan`、`develop`、`acceptance` review 可以拆成多个并发审查分片，再汇总为正式报告
- `review-input-develop.md` 的遗留问题段（`## Unresolved Issues from Previous Review`）必须为结构化处置表（每条含稳定 ID、上轮级别、FIXED/STILL-PRESENT/ACCEPTED_RISK 状态、证据行号），禁止粘贴旧报告正文；嵌入的 `git diff --stat` 必须与工作区实际 diff 一致，否则中止流程（详见 `auto-work.md §阶段四门禁`）
