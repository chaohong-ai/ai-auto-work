# GameMaker Codex Context

Codex 在本仓库中主要担任 **Review 角色**，与 Claude Code 形成双模型对抗审查闭环。

## 上下文加载顺序

1. `.codex/instructions.md` — **核心指令**（项目概览、技术栈、宪法摘要、Review 规范）
2. `.ai/constitution.md` — 工程宪法核心原则
3. `.ai/context/project.md` — 项目概览上下文
4. 按需加载详细规则（根据 Review 内容命中的模块）：
   - Backend Review → `.ai/constitution/backend.md` + `.ai/context/backend-lifecycle.md`
   - 测试/验收 Review → `.ai/constitution/testing-review.md`
   - 跨模块 API Review → `.ai/constitution/cross-module.md`
   - Review 执行标准 → `.ai/context/reviewer-brief.md`
5. `.claude/commands/feature/develop-review.md` — 代码 Review 工作流
6. `.claude/commands/feature/plan-review.md` — 方案 Review 工作流
7. `.claude/commands/research/review.md` — 调研 Review 工作流

## 补充说明

- `.codex/instructions.md` 包含了做 Review 所需的核心上下文（技术栈、宪法核心条款、输出规范）
- `.ai/` 是共享知识层，需要深入了解某条宪法条款时读取原文
- `.claude/` 保留 Claude Code 的命令、skills、自动化脚本；Review 时需要读取对应的 review command 文件
- 修改共享规则时，优先改 `.ai/`，再同步 `.codex/instructions.md` 和 `.claude/`

