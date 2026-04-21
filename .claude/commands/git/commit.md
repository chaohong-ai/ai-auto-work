---
description: 暂存变更并生成规范的commit
argument-hint: [commit message (可选)]
---

## 任务

暂存当前变更并创建一个规范的 git commit。Claude Code 负责指挥决策，具体 git 操作交由 Codex 执行。

## 工作流程

### 第一步：Claude Code 收集上下文

并行执行以下命令，了解当前仓库状态：
- `git status`：查看所有未暂存和未追踪的文件
- `git diff --stat`：查看变更文件摘要
- `git log --oneline -5`：查看最近 commit 风格

### 第二步：Claude Code 决策

根据上下文判断：
1. 哪些文件应该暂存（排除 `.env`、密钥、日志、构建产物等敏感/无关文件）
2. 如果没有任何变更可提交，告知用户并结束
3. 生成 commit message（规则见下方）

用户传入的参数：`$ARGUMENTS`

**如果用户提供了 commit message**：直接使用，可适当润色但保留原意。
**如果用户没有提供**：根据变更内容自动生成。

**消息格式：**
```
<type>(<scope>): <简洁描述>

<详细说明（可选，当变更复杂时添加）>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**type 枚举：** `feat` | `fix` | `refactor` | `docs` | `test` | `chore` | `style`

**消息规范：**
- 第一行不超过 70 字符
- 用中文描述（与项目风格一致）
- 聚焦"为什么"而不是"是什么"

### 第三步：委派 Codex 执行

使用 Codex CLI 执行 git 操作：`codex exec --full-auto`

向 Codex 发出明确指令，包含：
1. **需要暂存的文件列表**（逐个列出完整路径）
2. **完整的 commit message**（含 Co-Authored-By）
3. **执行步骤**：`git add <files>` → `git commit -m "<message>"` → `git status`

Codex 调用示例：
```
请执行以下 git 操作：

1. 暂存以下文件：
   - path/to/file1
   - path/to/file2

2. 执行 commit：
   git add path/to/file1
   git add path/to/file2
   git commit -m "<第一行>" -m "<正文和 Co-Authored-By>"

3. 执行 git status 确认结果
```

Codex CLI 调用：
`codex exec --full-auto "<上述指令>"`

### 第四步：Claude Code 确认结果

根据 Codex 返回的结果：
- 成功：向用户展示 commit hash 和摘要
- 失败（pre-commit hook 等）：分析原因，生成修复指令，再次委派 Codex 执行
  - 修复后创建**新的** commit（不用 `--amend`）
  - 仍由 Codex 执行 git 写操作，Claude 只负责决定修复方案

---

## 角色分工

| 角色 | 职责 |
|------|------|
| Claude Code | 分析变更、决定暂存范围、生成 commit message、审核结果 |
| Codex | 执行 `git add`、`git commit`、`git status` 等具体命令 |

## 禁止事项

1. **禁止 `git add .` 或 `git add -A`**：必须逐个文件暂存
2. **禁止 `--no-verify`**：不跳过 pre-commit hooks
3. **禁止 `--amend`**：除非用户明确要求
4. **禁止 `git push`**：只 commit 不 push
5. **禁止提交敏感文件**：`.env`、密钥、证书等
6. **Claude Code 禁止直接执行 git 写操作**：所有 git add/commit 操作必须委派给 Codex
