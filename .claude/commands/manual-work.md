---
description: 带人工检查点的开发流程：前期需求/方案重点把关，后期自主执行
argument-hint: <version_id> <feature_name> [需求描述]
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
- `AUTOPILOT` = `false`（初始值，用户可在任意检查点触发切换为 `true`）

---

## 与 auto-work 的核心区别

| 维度 | auto-work | manual-work |
|------|-----------|-------------|
| 执行方式 | 独立 `claude -p` 进程 + shell 脚本编排 | 当前对话内执行，用 subagent 并行 |
| 人工干预 | 零干预，全自动 | **前期重点把关**需求和方案，后期自主执行 |
| 决策权 | AI 自主决策 | 需求理解和技术方案由用户拍板，编码执行 AI 自主 |
| 适用场景 | 需求明确、信任 AI 全程处理 | 需求有模糊点、想把控方向和架构 |

**检查点分布原则：前重后轻（支持随时切换自动驾驶）**
- 阶段 0~2（需求分类→调研→需求文档→方案）：**每步确认**，确保方向正确
- 阶段 3~5（任务拆分→开发→文档）：**自主执行**，仅异常时暂停
- 阶段 6（推送）：**确认后推送**
- **自动驾驶模式：** 用户在任意检查点回复"后面你自己完成吧"、"剩下的你搞定"、"自动完成"等类似放权指令时，立即设置 `AUTOPILOT = true`，后续所有检查点（含阶段六推送）自动通过，不再等待用户确认

---

## 执行流程

### 阶段零：需求分类

判断需求类型：`research`（需要调研）或 `direct`（直接开发）。

判断标准：
- **research**：全新系统设计、需要技术选型、涉及不熟悉领域
- **direct**：Bug 修复、已有系统优化/扩展、需求明确且有参考实现

同时写入 `{FEATURE_DIR}/classification.txt`（与 auto-work 格式一致）：
```
type=research|direct
complexity=S|M|L
```
`complexity` 仅供参考，不影响 manual-work 的检查点分布。

**🔲 检查点：** 向用户展示分类结果和判断依据（1-2 句话），等确认或改判。

---

### 阶段零-B：技术调研（仅 research 类型）

使用 `/research:do` 进行调研，产出调研报告，保存至 `{FEATURE_DIR}/research-report.md`。

**🔲 检查点：** 向用户展示调研结论摘要：
- 关键选型决策
- 推荐方案及理由
- 排除方案及理由

等用户确认技术方向后继续。

---

### 阶段一：生成 feature.md

根据需求（+ 调研结论）生成结构化需求文档 `{FEATURE_DIR}/feature.md`。

Markdown 格式同 auto-work（功能名称、概述、需求列表、交互设计、技术约束、依赖关系、备注）。

**🔲 检查点：** 向用户展示：
- P0 需求清单（逐条列出）
- notes 中的 [待确认] 项
- 交互设计概要

等确认需求理解正确，或根据反馈修改后再次确认。

---

### 阶段二：Plan 迭代

使用 `/feature:plan` 生成技术方案。

**🔲 检查点（本流程最重要的检查点）：** 向用户展示方案概要：
- 整体架构思路
- 涉及的模块和关键文件
- 核心技术决策及 trade-off
- 风险点和缓解措施

等用户拍板方案。这是最后一个需要用户深度参与的检查点——方案定了，后面 AI 自主执行。

---

### ⬇️ 以下阶段自主执行，无需逐步确认 ⬇️

---

### 阶段三：任务拆分（自主）

将 plan 拆分为可独立开发、验证、提交的任务单元，输出到 `{FEATURE_DIR}/tasks/task-NN.md`。

拆分规则：
- 每个任务可独立编译验证
- 按依赖顺序排列
- 粒度：每任务 ≤3 文件、≤100 行代码改动（宪法 2.4 伴生测试 router_test.go/.hurl 不计入文件数）
- 拆分检验：如果一个任务的 commit message 需要用"和"连接两个动作，说明应继续拆分

拆分完成后向用户**简要汇报**任务清单（编号+名称，一行一个），但不等待确认，直接进入开发。

---

### 阶段四：逐任务开发 + 提交（自主）

按顺序执行每个任务：

1. **开发**：使用 `/feature:developing` 实现代码
2. **编译验证**：Go `go build ./...`、TS `npx tsc --noEmit`
   - 编译通过 → 继续 step 3
   - 编译失败 → **直接跳至 step 5 修复**，跳过 step 3 review（不对语法错误代码做无效审查）
3. **Review 循环**（仅编译通过后执行）：调用 `/feature:develop-review` 进行对抗审查，基于报告修复 CRITICAL/HIGH 问题；**最多 2 轮**，2 轮后仍有 CRITICAL 则暂停问用户
4. **HTTP 端点测试铁律（宪法 2.4）：** 新增任何 HTTP 端点必须同步添加 `router_test.go` 路由注册测试 + `Backend/tests/smoke/` Hurl 冒烟测试
5. **自动修复**：针对编译错误或 Triple-Check Gate 失败进行修复；**每次进入此步骤独立计算最多 2 轮**（step 2 跳入与 step 6 跳入的轮次互不影响），2 轮后仍失败则暂停问用户
6. **Triple-Check Gate（通过才能提交）：**
   - 受影响 Go 包执行 `go test -short -count=1 ./涉及包/...` 且全绿
   - 涉及 handler 层及以上链路变更时执行 `go test -tags=integration -count=1 ./tests/e2e/...` 且全绿
   - HTTP 端点三件套（router.go 注册 + router_test.go 断言 + `.hurl` 文件）均存在
   - 关键链路 Hurl 禁止通配符状态码（`HTTP *`）、禁止把关键步骤设为可选
   - Fake 依赖必须实际接入测试 setup 并跑通 happy path
   - 以上任一未满足 → 跳回 step 5（本次进入重新计 2 轮上限）；step 5 暂停后需用户介入再继续
7. **Context Repair（任务收尾）：** 若本任务发现反复遗漏的同类约束（非单次粗心），在提交前先补 `.ai/` 或 `.claude/` 文档，不得只修代码
8. **自动提交** Git commit，格式：`feat({FEATURE_NAME}): {TASK_NAME}`（每任务一个 commit，确保粒度与任务一一对应）

每个任务完成后输出一行状态（任务名 + 通过/失败），保持用户知情但不打断节奏。

**仅异常时暂停：**
- 编译修复 2 轮仍失败 → 暂停，展示错误信息问用户
- 测试严重退步 → 暂停

---

### 阶段四-C：验收门禁（自主，不可跳过）

回读 `{FEATURE_DIR}/feature.md` 的每条 REQ 及其验收条件，逐条验证 4 个维度：
- **代码实现**：对应逻辑是否存在且正确
- **配置完整性**：路由注册、配置项、环境变量是否齐全
- **测试覆盖**：单元测试 + 路由测试是否覆盖该 REQ
- **冒烟可达性**：`.hurl` 文件中是否有对应的端到端验证（无 HTTP 端点的功能此维度标记 N/A，不计入 FAIL）

输出 `{FEATURE_DIR}/acceptance-report.md`，每条 REQ 标记 PASS / FAIL。

**通过标准：**
- P0 需求必须全部 PASS
- P1 允许最多 1 条 FAIL
- P2 不阻塞

**验收失败处理：**
- 触发 1 轮自动补救：对每个 FAIL 的 REQ 对应任务，走阶段四完整步骤 1-8（开发 → 编译 → review → HTTP铁律 → 修复 → Triple-Check Gate → Context Repair → commit）→ 重新验收
- 补救后仍有 P0 FAIL → 暂停，展示失败详情问用户

`AUTOPILOT = true` 时验收自动执行，结果仅输出一行摘要（通过/失败数量）。**P0 FAIL 时即使 AUTOPILOT=true 也必须暂停**，这是安全防护不可绕过。

---

### 阶段五：生成模块文档（自主，仅验收通过时执行）

根据本次功能所属模块，更新对应的架构文档（文件不存在则创建），自动提交：

| 改动模块 | 文档路径 |
|---------|---------|
| Backend | `Docs/Architecture/modules/backend.md` |
| MCP | `Docs/Architecture/modules/mcp-server.md` |
| Frontend | `Docs/Architecture/modules/client.md` |
| Engine | `Docs/Architecture/modules/engine.md` |
| GameServer | `GameServer/CLAUDE.md` 及对应子服务文档 |
| 跨模块 | `Docs/Architecture/system-architecture.md` |

---

### 阶段六：推送远程仓库（仅验收通过时执行）

**🔲 检查点：** 展示待推送的 commit 列表及验收摘要，等确认后推送。

若 `AUTOPILOT = true`，自动推送，无需等待确认。

---

## 检查点交互规范

1. **检查 AUTOPILOT：** 如果 `AUTOPILOT = true`，跳过步骤 2-4，仅输出一行简要状态（如"✅ 阶段一完成，自动继续"），直接进入下一阶段
2. **展示**：简洁展示当前阶段产出（markdown 表格或列表，不要长篇大论）
3. **问**：明确的问题，如 "方案 OK 吗？需要调整哪里？"
4. **等待**：使用 AskUserQuestion 等待用户回复
5. **响应**：
   - 用户确认（ok/好/继续/没问题）→ 进入下一阶段
   - 用户提出修改 → 调整后重新展示
   - 用户说跳过 → 跳过当前阶段
   - **用户放权**（"后面你自己完成吧"、"剩下的你搞定"、"自动完成"、"你自己搞"、"不用问我了"等类似表达）→ 设置 `AUTOPILOT = true`，从当前阶段起自主完成所有后续工作

---

## 注意事项

- 全程在当前对话中执行，不启动独立 `claude -p` 进程
- 使用 subagent（Agent tool）并行处理可并行的工作
- 复用现有 skill（/feature:plan、/feature:developing、/research:do 等）
- 产出文件结构与 auto-work 完全一致，确保两种模式的产出可互换
- 总进度日志：`{FEATURE_DIR}/manual-work-log.md`
- 中断恢复：重新运行时按以下完成标记判断跳过哪些阶段：
  - `classification.txt` 存在 → 阶段零已完成
  - `research-report.md` 存在 → 阶段零-B 已完成
  - `feature.md` 存在 → 阶段一已完成
  - `plan.md` 存在 → 阶段二已完成
  - `tasks/` 目录存在且含 task-*.md → 阶段三已完成
  - `acceptance-report.md` 存在且所有 P0 为 PASS → 阶段四-C 已完成
- `classification.txt` 在阶段零写入，`complexity` 仅供参考，不影响检查点分布；`acceptance-report.md` 在阶段四-C写入，两者格式与 auto-work 完全一致，产出可互操作
