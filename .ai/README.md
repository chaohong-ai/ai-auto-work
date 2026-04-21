# Shared AI Workspace

这里是 GameMaker 的共享 AI 上下文层，目标是让不同 agent 在同一仓库内读取一致的项目事实、工程原则和工作约定。

## 目录说明

- `context/project.md`: 项目背景、架构、技术栈、目录语义（精简版，始终加载）
- `context/backend-lifecycle.md`: Backend Session / Container / Shutdown 生命周期约束（按需加载）
- `context/reviewer-brief.md`: Develop/Plan Review 统一审查规则 — **所有 reviewer 在执行 review 前必须读取**
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

## 上下文修复策略

如果某个 agent 在工作中反复犯同类错误，优先判断是否为"上下文缺口"。

- 项目事实和通用约束缺失：更新 `.ai/`
- Claude 专属工作流或技能缺失：更新 `.claude/`
- 不要只在单次 review 报告里指出问题而不沉淀规则

## auto-work 共享约定

- `auto-work` 里的执行者默认是 Claude，reviewer 默认是 Codex
- `M` 级需求的 plan 虽然是单次生成，但仍必须经过至少一轮 Codex plan review
- `plan`、`develop`、`acceptance` review 可以拆成多个并发审查分片，再汇总为正式报告
