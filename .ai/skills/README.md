# Shared Skills Index

## 目的

这里不复制 Claude 的 skill 实现，而是定义共享兼容约定，避免重复维护两套 skill 文档。

## 当前策略

- Claude 原生 skills 仍保存在 `.claude/skills/`
- 对所有 agent 而言，`.claude/skills/*/SKILL.md` 都可以视为权威 skill 文档
- Codex 不把这些文件当作“原生已安装 skill”，但在需要复用工作流时应主动阅读并遵循其说明

## 使用约定

- 需要 Claude skill 设计时，优先读取对应 `SKILL.md`
- 如果某个 skill 的内容已经演变成跨 agent 共享知识，应将稳定部分抽到 `.ai/`，把 Claude 专属执行细节保留在 `.claude/skills/`
- 新增共享 skill 索引时，在这里登记入口，不直接复制整份 skill 内容

## 已有 Claude skills

- `.claude/skills/skill-creator/SKILL.md`

