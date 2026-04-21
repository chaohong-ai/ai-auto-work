---
description: 推送当前分支到远程仓库
argument-hint: [remote branch (可选)]
---

## 任务

将当前分支的 commit 推送到远程仓库。Claude Code 负责安全检查和决策，具体 git 操作交由 Codex 执行。

## 工作流程

### 第一步：Claude Code 收集状态

并行执行以下只读命令：
- `git status`：确认工作区状态
- `git log --oneline origin/$(git branch --show-current)..HEAD 2>/dev/null`：查看将要推送的 commit
- `git branch -vv`：确认远程追踪关系
- `git branch --show-current`：获取当前分支名

### 第二步：Claude Code 安全检查与决策

1. **未提交变更**：如有未提交的变更，提醒用户是否需要先 `/commit`
2. **主分支保护**：如果是 `main`/`master`，允许正常 push，但禁止 force push
3. **无 commit 可推**：如果没有新 commit，告知用户并结束
4. **敏感信息扫描**：检查最近 commit 是否包含 `.env`、密钥等，如有则警告

根据参数决定 push 命令：

用户传入的参数：`$ARGUMENTS`

- **有参数**：按 `remote branch` 解析 → `git push <remote> <branch>`
- **无参数 + 有追踪分支** → `git push`
- **无参数 + 无追踪分支** → `git push -u origin <当前分支名>`

### 第三步：委派 Codex 执行

使用 Codex CLI 执行 git 操作：`codex exec --full-auto`

```
向 Codex 发出指令：

请执行以下 git 操作：

1. 执行：git push <确定的命令参数>
2. 如果成功，执行 git log --oneline -3 确认远程同步状态
3. 返回执行结果
```

Codex CLI 调用：
`codex exec --full-auto "<上述指令>"`

### 第四步：Claude Code 确认结果

根据 Codex 返回的结果：
- **成功**：向用户展示推送的 commit 数量和范围
- **rejected（非 fast-forward）**：提示用户需要先 pull，**不自动 force push**
- **认证失败**：提示用户检查 git 凭证（建议 `! git credential-manager ...`）
- **其他错误**：展示错误信息，分析原因

---

## 角色分工

| 角色 | 职责 |
|------|------|
| Claude Code | 状态检查、安全审查、决定 push 参数、审核结果 |
| Codex | 执行 `git push` 及结果确认命令 |

## 禁止事项

1. **禁止 `git push --force` 或 `-f`**：除非用户明确要求
2. **禁止 force push 到 main/master**：即使用户要求也要警告
3. **禁止推送敏感信息**：发现则中止并警告
4. **Claude Code 禁止直接执行 git push**：push 操作必须委派给 Codex
