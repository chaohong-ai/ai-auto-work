# Develop Review 统一审查规则

Version: 1.1  
Scope: 所有对本仓库执行 develop-review / plan-review 的 agent（Claude / Codex / 其他）

本文件是 develop-review 的执行标准。审查者在读取 review prompt 之前必须先读本文件，所有报告必须遵循以下结构与判级规则。

---

## 零、Review 问题处置状态定义与门禁

> 源自 `.ai/constitution.md` §8「Review 闭环」，状态细则在此展开。

- **状态定义与门禁计数规则**：
  - `FIXED`：已修复并通过验证。**不计入**门禁。
  - `SPLIT(任务号, 责任人)`：拆分到独立任务。出池条件——必须同时满足：(1) 绑定任务 ID 或文件路径；(2) 指定责任归属。任一缺失仍按 OPEN 计数。**满足出池条件时不计入**门禁。
  - `ACCEPTED_RISK(审批人, 日期, 理由, 复查条件)`：明确接受风险。必须由**人类负责人**批准，AI 不得自行审批。必须同时记录四项：审批人、日期、理由、复查条件。缺任一字段视为 OPEN。**满足时不计入**门禁。
  - `POSTPONED(截止轮次, 理由)`：延后处理。**仍计入**门禁——POSTPONED 是"欠债"，不是"解决"。
  - `OPEN`：未处置。**计入**门禁。
- **门禁**：计入门禁的 HIGH+ 问题累积 ≥ 2 条 → 禁止进入下一轮迭代。

---

## 零-B、Review 入口校验（必须在执行审查前完成）

在读取 `review-input-*.md` 后、开始实质审查前，必须执行以下校验：

1. **Scope 一致性**：将 `review-input-*.md` 中声明的 `round` / `mode` / `task scope` / `version_id` / `feature_name` 与调用参数（调用方 prompt 或 review-input 文件名）进行比对。
2. **不一致处理**：若两者不一致，**必须在报告开头显式标注**，例如：
   > ⚠️ 入口校验异常：调用参数为 task-07 round-3，但 review-input 文件描述的是 task-06 round-2。以下审查基于 review-input 实际内容执行，调用方请确认输入正确性。
3. **跨 round 审查保护**：增量审查（round > 1）必须核对上一轮报告中的 `[RECURRING]` 问题列表，确认本轮结论已对这些问题给出明确的 FIXED / STILL-PRESENT 状态，不得静默跳过。
4. **diff 摘要与工作区一致性（task-10 RECURRING 触发，禁止静默跳过）**：核对 `review-input-*.md` 中 `## Git Diff --stat` / `## Changed Files` 段落所列举的核心改动文件，是否与当前工作区真实改动（`git diff --stat`）一致。若存在以下任一情形，必须在报告开头标注 `⚠️ diff stale`，并以工作区实际代码为准执行审查，**不得**依据 review-input 的 diff 段落判断本轮代码质量或自动标记 `status: done`：
   - review-input 列举的主要改动文件与工作区真实改动文件严重不符
   - diff 内容属于上一任务的遗留（例如 scope 已更新为 task-N，但 `Changed Files` 内容仍为 task-(N-1) 的代码）
   - `## Changed Files` 内列出的文件与 `## Git Diff --stat` 显示的统计不一致

5. **review-input diff 段落完整性（task-11 RECURRING 触发，阻断 review 流程）**：在执行第 4 条一致性校验前，先检查 `review-input-develop.md` 是否同时包含 `## Git Diff --stat` 和 `## Changed Files` 两个段落。若这两个段落**完全缺失**（而非内容过时），**必须立即阻断审查流程**：
   - 在报告开头标注 `⚠️ REVIEW_BLOCKED: INPUT_INCOMPLETE`，不得继续执行任何审查维度
   - **auto-work 上下文**：禁止以自行获取 `git diff` 的方式绕过生成侧门禁继续审查——这等价于在生成失败后人工补做，是对流程门禁的绕过；须向 auto-work 脚本返回"输入不完整"信号，要求重新生成包含必填段落的 `review-input-develop.md` 后再启动审查
   - **人工 review 上下文**：若调用方在 review prompt 中明确注明"已确认 diff 来自 `git diff --stat` 且内容正确"，reviewer 可以自行获取并在报告开头显式注明"已自行获取 diff"；否则同样阻断，不得推进
   - 在无法访问工作区时，一律标注 `⚠️ REVIEW_BLOCKED: INPUT_INCOMPLETE`，不得以 INPUT_MISSING 降级为"可继续"
   - **根因**：允许 reviewer 自行补 diff 会持续掩盖生成侧缺口，导致同类问题在后续轮次循环触发；正确修复应在 auto-work 生成阶段强制校验这两个段落（参见 auto-work.md §阶段四"develop-review 输入必填段落"）

6. **验收入口 Fail-Fast（acceptance review 专用，不可协商）**：当执行 acceptance review（即处理 `review-input-acceptance.md`）时，**必须优先**执行 `git diff --name-only <base>..HEAD`，将结果与 `review-input-acceptance.md` 中声明的实现路径集合（`Backend/`、`MCP/`、`Frontend/`、`Engine/` 等功能代码目录）交叉比对。若目标 diff 未命中 feature/plan 所声明的**任何**实现文件，则必须：
   - 在报告**总览区**顶部标注 `DIFF STALE` / `CANNOT_ACCEPT_SCOPE_MISMATCH`，并说明目标 diff 实际包含的路径
   - 将所有 REQ 的"代码实现验证"维度一律标为 FAIL，**禁止**使用工作区历史实现（本次 diff 范围之外的文件）替代本次交付证据
   - 整份验收报告结论直接判定为 `REMEDIATION_NEEDED`，禁止任何 REQ 继续推进为 `PASS`
   - 在报告末尾注明：需开发方修复输入摘要或实际提交代码后再重新提交验收
   - **根因**：历史实现文件已存在于工作区，不等于本次提交交付了这些文件；允许用历史状态代替本次 diff 会导致"永远验收通过"的假阳性，且下游部署/回滚无法以本次提交为基准

---

## 一、分片边界与维度

三路并发分片共同覆盖以下维度，每路至少覆盖其中一个主维度：

| 分片 | 主要维度 |
|------|---------|
| A | 架构实现偏差、依赖方向、接口一致性、数据流、宪法违规 |
| B | 并发竞态、资源泄漏、异常路径、超时、容器/进程生命周期、安全 |
| C | 测试覆盖、边界条件、回归风险、Context Repairs 识别 |

汇总时去重规则：同类问题只保留一条，取更高严重级别。

---

## 二、严重级别判定标准

### Critical（阻塞合入）

满足以下任一条件即判 Critical：

- 违反 `.ai/constitution.md` 及 `.ai/constitution/*.md` 中标注"（不可协商）"的约束
- 违反 `.ai/context/project.md` 及 `.ai/context/backend-lifecycle.md` 中标注"（不可协商）"的约束
- 安全漏洞：越权访问、token 泄露、租户隔离缺失
- 资源泄漏：容器 / 锁 / 并发槽 / capability token 在失败路径未释放
- 持久化数据不一致：幽灵 session、字段残留、状态机被覆盖
- plan 声明的文件在工作区不存在（Develop 收尾产物存在性核验）
- mock mode / real mode 行为严重分叉

### High（强烈建议修复，不阻塞合入但须在下轮前修复）

- 功能正确性缺陷（非极端条件下可触发）
- 测试覆盖严重不足（核心路径无回归保护）
- 验收标准与 plan 约定存在可测量偏差
- 错误分类混淆（取消被误判为失败）
- 索引缺失、启动路径遗漏等运维风险

### Medium（建议修复，可在后续迭代处理）

- 代码可读性、可维护性问题
- 测试覆盖不完整但已有基本验收
- 接口语义模糊（魔法参数、隐式约定）
- 日志 / 指标上报不准确

---

## 三、问题格式要求

每条问题必须包含以下四要素：

```
### [Severity][RECURRING?] 编号 — 简短标题
- **Files**: 文件路径:行号（多处用逗号分隔）
- **Impact**: 具体影响描述，包含触发条件和可观测后果
- **Minimal fix**: 最小可行修复建议，不超过 3 步
```

- 缺少 Files / Impact / Minimal fix 任一字段，该条目视为格式不合规
- Impact 必须描述具体后果，禁止使用"可能有问题"等模糊表述

---

## 四、`[RECURRING]` 标记规则

满足以下条件之一即在标题中追加 `[RECURRING]` 标记：

1. **同类问题在同一 task 的前一轮 review 中已出现**
2. **同类问题在跨 task 的历史报告中出现两次以上**（参考当前 feature track 的 `context-repair-log.md`，如 `Docs/Version/v0.0.3/snapshot/context-repair-log.md` 或 `Docs/Version/v0.0.3/docker-env/context-repair-log.md`）
3. **违反宪法中标注"RECURRING 升级"的约束**

RECURRING 标记的含义：

- 不仅要修代码，还要判断是否需要新增 Context Repair
- 若同类问题已有对应的宪法条目或规则文件，发现 reviewer 仍然漏检，应升级为 Context Repair 并指向"应更新哪个文件"

---

## 五、`## Context Repairs` 段要求

以下情况必须在报告末尾追加 `## Context Repairs` 段：

1. 发现三次以上同类遗漏（跨 task 或跨 round）
2. 违反的规则在现有宪法 / 规则文件中不存在或描述不足
3. 当前规则的适用范围未覆盖导致遗漏的场景

Context Repairs 每条必须包含：

- **目标文件**：应更新哪个文档（`.ai/constitution.md` / `.ai/context/project.md` / `.claude/rules/*.md` 等）
- **问题**：为什么这是系统性缺口，而非单次遗漏
- **建议补充**：具体应在目标文件中新增或强化的规则内容

---

## 六、报告结构模板

```markdown
# Develop Review Report — <task-id>

**来源**：三路 Codex 并发分片审查合并报告
- 分片 A：...
- 分片 B：...
- 分片 C：...

去重规则：同类问题只保留一条，取更高严重级别。

---

## Critical

### [Critical] C1 — ...
...

---

## High

### [High] H1 — ...
...

---

## Medium

### [Medium] M1 — ...
...

---

## Context Repairs

1. **目标文件**: ...
   - **问题**: ...
   - **建议补充**: ...

<!-- counts: critical=N high=N medium=N -->
```

---

## 七、与宪法的关系

本文件规则不得与 `.ai/constitution.md` 冲突。如有抵触，以 constitution.md 为准。  
本文件规则补充 constitution.md 中未覆盖的审查执行细节（格式、分片、RECURRING 判定、入口校验）。

---

## 附录：宪法硬约束速查（Codex 压缩上下文）

### 错误处理 (CRITICAL)
- Go: 禁止 `_` 丢弃 error；必须 `fmt.Errorf("context: %w", err)` 包装
- Go: 错误按语义分级记录（见宪法 §9）：系统故障 → `logger.Error`；可恢复异常 → `logger.Warn`；预期业务条件（如 not found、token 过期） → `logger.Info/Debug`。所有日志必须带操作名 + 实体标识 + 失败原因上下文
- TS: 禁止空 `catch {}`；Promise 必须有错误处理；MCP 用 Winston 记录
- Python: 禁止裸 `except:` 或 `except Exception: pass`

### 依赖方向 (CRITICAL)
- `Handler → Service → Repository`，同层禁止直接依赖
- Service 层禁止 import `mongo`/`redis`/`cos` 等基础设施包
- 接口定义在消费方，不在提供方；禁止循环依赖

### 并发安全 (CRITICAL)
- Mutex 必须 `defer` 释放；阻塞操作必须传播 `context.Context`
- Goroutine 必须有退出机制（context cancellation / done channel）
- `context.Canceled` / `context.DeadlineExceeded` 必须单独分类，不得落入通用失败路径
- Redis Streams 消费必须幂等，成功后 ACK，失败记日志+重试/死信

### HTTP 端点铁律 (CRITICAL)
新增任何 HTTP 端点必须同步完成：
1. `Backend/internal/router/router_test.go` 路由注册测试
2. `Backend/tests/smoke/*.hurl` 冒烟测试

### 高频审查盲区
1. **并发竞态**: goroutine 共享状态是否有锁保护？channel 是否可能阻塞？
2. **资源泄漏**: 文件句柄/DB连接/HTTP Body 是否正确关闭？defer 位置正确？
3. **异常路径盲区**: 错误分支是否真正处理？是否 happy-path-only？
4. **边界输入**: 空切片/nil map/零值 struct/超长字符串/并发写 map
5. **安全漏洞**: 注入风险/硬编码凭证/未校验外部输入/租户隔离缺失
6. **测试质量**: 只覆盖 happy path？缺少表格驱动测试？崩溃窗口测试是否用真实进程终止？

### 元数据尾行（必须追加）
- **Develop review:** `<!-- counts: critical=X high=Y medium=Z -->`
- **Plan review:** `<!-- counts: critical=X important=Y nice=Z -->`
- **Research review:** `<!-- counts: critical=X important=Y nice=Z reliability=R -->`（R 为 1-5 决策可靠度）
- **Acceptance review:** `ALL_REQ_ACCEPTED` / `REMEDIATION_NEEDED: REQ-NNN` / `CANNOT_VERIFY`
