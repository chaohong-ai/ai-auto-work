# GameMaker Agent Context

本仓库已经整理为 `Claude Code` 与 `Codex` 共用的工作目录。

开始任何规划、开发、评审前，先读取以下共享上下文：

1. `.ai/context/project.md` — 项目概览、技术栈、领域隔离声明（精简版，始终加载）
2. `.ai/constitution.md` — 工程宪法核心原则（精简版，始终加载）
3. 按需加载详细规则（根据命中模块，**不同领域的规则互不加载**）：
   - Backend → `.ai/constitution/backend.md` + `.ai/context/backend-lifecycle.md`
   - Review → `.ai/constitution/testing-review.md`（内含 [通用]/[创作平台] 作用域标签）+ `.ai/context/reviewer-brief.md`
   - 跨模块 API → `.ai/constitution/cross-module.md`
   - Engine → `.ai/constitution/engine.md`
   - GameServer → `GameServer/CLAUDE.md`（通用入口）+ 命中子服务的 `servers/<name>/CLAUDE.md`；**不加载**创作平台的 backend/cross-module/engine 宪法
4. `Docs/Architecture/` — 涉及特定模块时读取

## Agent 专用上下文

- **Claude Code**: `CLAUDE.md`（入口，自动加载）→ 引用 `.ai/` + `.claude/constitution.md`
- **Codex**: `.codex/instructions.md`（自动加载）— 内含项目概览、技术栈、宪法摘要、Review 角色定位

## 双模型协作架构

在 `auto-work` 工作流中，Claude 和 Codex 形成对抗审查闭环：

- **Claude**（执行者）：编码实现、修复代码、生成测试
- **Codex**（审查者）：对抗审查、找盲区、验证修复

详见 `.claude/commands/auto-work.md` 中的"Triple-Check 收敛法"。

## 补充约定

- `.ai/` 是共享上下文层，面向所有 AI agent。
- `.claude/` 是 Claude Code 运行时层，保留 commands、skills、plans、logs 等 Claude 专用能力。
- `.codex/` 是 Codex 运行时层，保留 instructions 和项目级配置。
- 如果需要理解既有自动化流程、命令体系或技能设计，再读取 `.claude/` 下对应文件。
- 如共享文档与 agent 专用运行时文档冲突，以 `.ai/constitution.md` 的项目规则为准；agent 专用文件只负责运行方式差异，不改变项目事实和工程约束。
- 修改项目级知识、宪法、术语、目录约定时，优先更新 `.ai/`，再按需同步到 `.claude/` 和 `.codex/`。

