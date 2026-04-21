# AI Auto-Work

> English version: [README.md](./README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude](https://img.shields.io/badge/驱动引擎-Claude%20Code-blueviolet)](https://claude.ai/code)
[![Codex](https://img.shields.io/badge/审查引擎-Codex-blue)](https://openai.com/codex)
[![Workflow](https://img.shields.io/badge/模式-全自动%20%7C%20人工检查-green)](#工作流体系)

**AI 驱动的全链路软件开发工作流** — 从需求调研到代码提交，基于 Claude Code + Codex 双模型协作。

自动完成完整流水线：**需求调研 → 调研 Review → 方案设计 → 方案 Review → 功能开发 → 开发 Review**，可自主完成中大型工程开发。

---

## 什么是 AI Auto-Work？

AI Auto-Work 是一套**智能体编码工作流系统**，通过编排大语言模型（LLM）端到端完成真实软件工程任务。以 Claude 作为执行者、Codex 作为对抗审查者，构成 **Triple-Check 收敛循环**，以最少人工干预交付生产级代码。

### 核心能力

- **全链路自主开发** — S/M/L 复杂度分级，自动任务拆解
- **跨模型对抗审查** — Claude 构建，Codex 审计；不同模型发现不同盲区
- **零上下文污染** — 每个阶段在独立进程中运行，仅通过持久化文件交接
- **机械质量门禁** — 编译 + 测试必须通过，才能进入任何审查循环
- **自修复上下文** — 系统性错误写入共享知识库（`.ai/`），而不只是修代码
- **原子提交** — 一个任务一个提交（≤3 文件 / ≤100 行），始终可 bisect

---

## 快速开始

```bash
# 全自动：调研 → 方案 → 编码 → 审查 → 提交
/auto-work 实现用户头像上传功能

# 带人工检查点
/manual-work 重构用户认证模块

# 仅生成实现方案
/feature:plan 添加 WebSocket 实时推送

# 技术选型调研
/research:do 评估 Redis Streams vs Kafka 用于任务队列

# 根因分析 + Bug 修复
/bug:fix 修复并发场景下的内存泄漏
```

---

## 工作原理

```
用户需求
   │
   ▼
Claude（执行者）         ← 编码、修复、测试
   │
   ▼
质量门禁                 ← 编译 + 单元测试 + Smoke 测试（强制）
   │
   ▼
Codex（审查者）          ← 对抗审查：并发、泄漏、边界情况
   │
   ▼
收敛？                   ← Critical = 0，High ≤ 2
├── 否 → Claude 修复 → 循环
└── 是 → Git 提交
```

---

## 工作流体系

### `/auto-work` — 全自动工作流

无需人工干预，从原始需求到提交代码全自动完成。

**阶段：**

| # | 阶段 | 说明 |
|---|------|------|
| 1 | 需求分级 | S / M / L 复杂度；L 级自动拆分为多个 M 级任务 |
| 2 | 技术调研 | 按需调用 `/research:loop` 完成技术选型 |
| 3 | 方案生成 | 通过 `/feature:plan` 迭代生成 `plan.md` |
| 4 | 任务拆解 | 原子粒度 `tasks/task-N.md`（≤3 文件 / ≤100 行） |
| 5 | 开发循环 | `/feature:develop` 编码 + 审查迭代 |
| 6 | 验收门禁 | 编译 + 测试 + HTTP 端点三件套 |
| 7 | 文档更新 | 架构文档 / 版本文档同步更新 |
| 8 | 提交推送 | `/git:commit` + `/git:push` |

**收敛标准：** Critical = 0，High ≤ 2，或达最大迭代轮次后自动升级复杂度档次。

---

### `/manual-work` — 人工检查点工作流

与 auto-work 产出相同，在关键节点暂停等待确认。

| 检查点 | 审查内容 |
|--------|----------|
| Stage 0 | 需求分级确认 |
| Stage 0-B | 调研结果确认（如有） |
| Stage 1 | feature.md 需求文档确认 |
| **Stage 2** | **方案 / 架构确认（最重要）** |
| Stage 4-C | 验收结果确认 |
| Stage 6 | 推送确认 |

在任意检查点输入 `AUTOPILOT=true` 可切换为全自动模式。

---

### `/feature:plan` — 方案创建工作流

迭代生成 `plan.md` 直到质量收敛（最多 20 轮）。

- 奇数轮：生成 / 修复方案
- 偶数轮：Codex 审查
- **收敛条件：** Critical = 0，Important ≤ 2

产出包含：数据模型设计、API 接口规格、实现流程、测试策略、风险评估。

---

### `/feature:develop` — 功能开发工作流

按任务列表逐个实现，每个任务独立编码 + 审查循环。

**每个任务循环：**
1. 代码实现
2. 编译验证（快速失败门禁）
3. Codex 审查（最多 2 轮）
4. 自动修复失败（最多 2 轮）
5. 门禁：单元测试 + 集成测试 + Smoke 测试
6. 上下文修复（如发现系统性缺口）
7. 原子 Git 提交

---

### `/research:do` — 技术调研工作流

并行 Web 搜索（3 个 Agent 分片）+ 项目代码库扫描 → 结构化 `research-result.md`。

**报告结构：** 问题定义 → 业界方案概览 → 对比表格 → 实战经验 → 项目适配分析 → 推荐结论

---

### `/bug:fix` — Bug 修复工作流

根因分析 → 最小化修复 → Codex 审查 → 经验沉淀到 `.ai/`。

---

### `/git:commit` + `/git:push` — 安全 Git 操作

- 规范提交格式：`<type>(<scope>): <description>`
- 自动跳过敏感文件
- 禁止强推 main 分支
- 推送前安全扫描

---

## 为什么需要双模型？

单模型自审因共同的认知偏差而遗漏系统性问题。Claude 和 Codex 训练分布不同——Claude 的盲区往往正是 Codex 擅长发现的：

| 问题类型 | Claude（执行者） | Codex（审查者） |
|---------|----------------|----------------|
| 并发竞态 | 可能遗漏 | 主动标记 |
| Goroutine 泄漏 | 可能遗漏 | 主动标记 |
| 资源耗尽 | 可能遗漏 | 主动标记 |
| 边界条件 | 可能遗漏 | 主动标记 |
| 宪法合规性 | 自我盲区 | 独立检查 |

---

## 执行模式

| 模式 | 触发条件 | 执行方式 | 审查质量 |
|------|----------|----------|----------|
| **ROUTE_MODE_A** | claude CLI + codex CLI 均可用 | Bash 子进程编排 | 最高（真正的跨模型） |
| **ROUTE_MODE_B** | 仅 Agent 工具可用 | Agent 委托编排 | 良好（代理审查） |

---

## 目录结构

| 目录 | 职责 |
|------|------|
| `.ai/` | 跨 Agent 共享知识层（事实源） |
| `.ai/constitution.md` | 核心工程原则 |
| `.ai/constitution/` | 模块详细规则（并发、测试、跨模块通信） |
| `.ai/context/project.md` | 项目技术栈与约束 |
| `.claude/` | Claude Code 专用运行时层 |
| `.claude/commands/` | 工作流定义 |
| `.claude/skills/` | Claude skill 定义 |
| `.claude/guides/` | 专题规则与指南 |

---

## 核心原则

| 原则 | 规则 |
|------|------|
| **简单优先** | 只实现需求明确要求的内容，不做预支设计 |
| **测试先行** | 新功能和缺陷修复从失败测试开始 |
| **原子提交** | 一个任务一个提交（≤3 文件 / ≤100 行） |
| **机械门禁** | 编译 + 测试在 Review 前强制通过 |
| **文档驱动交接** | 仅通过持久化文件交接：`feature.md → plan.md → task-N.md` |
| **上下文修复** | 系统性错误更新 `.ai/`，而不只修代码 |

---

## 常见问题

**Q：这与 GitHub Copilot 或 Cursor 有什么区别？**
A：那些工具为开发者提供行内建议辅助。AI Auto-Work 编排完整的端到端开发周期——从需求分析、架构规划、实现、多轮对抗审查到提交——自主完成，面向中大型功能。

**Q：能处理大型代码库吗？**
A：可以。每个任务在独立进程中以全新上下文窗口运行，上下文积累不是瓶颈。L 级任务自动拆分为串行 M 级任务，可处理任意规模。

**Q：支持哪些语言和框架？**
A：工作流系统本身与语言无关。内置宪法和上下文文件针对 Go、TypeScript、Python 和 GDScript 配置，但工作流命令可适配任何技术栈。

**Q：必须同时有 Claude 和 Codex 吗？**
A：不必须。ROUTE_MODE_B 仅用 Claude（Agent 工具）即可运行，提供良好审查质量。ROUTE_MODE_A 需要 Claude CLI + Codex CLI，实现最高质量的跨模型对抗审查。

**Q：上下文修复机制是怎么工作的？**
A：当 Codex 识别出某类反复出现的问题（而非一次性失误）时，工作流将约束写入 `.ai/`——每次运行开始时都会加载的共享知识库。同类错误在后续工作流中不会再出现。

---

## 相关项目

- [Claude Code](https://claude.ai/code) — Anthropic 的 AI 编码 CLI
- [OpenAI Codex](https://openai.com/codex) — OpenAI 的代码专用模型
- [Anthropic](https://anthropic.com) — Claude 模型提供商

---

## License

MIT License — 详见 [LICENSE](LICENSE)。
