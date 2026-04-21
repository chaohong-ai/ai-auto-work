---
description: 修复Bug并固化经验为skill/rule
argument-hint: <bug描述> — 直接描述问题现象，如"创建游戏出现500错误"
---

## 参数解析

用户传入的参数：`$ARGUMENTS`

参数是对 Bug 现象的自由文本描述。如果为空，使用 AskUserQuestion 询问用户要修复什么问题。

---

## 执行流程

### 阶段一：问题定位

**目标：** 找到 Bug 的根因，不要急于修复。

1. **收集线索**（并行执行）：
   - 阅读最近的后端日志：`Backend/log/backend.log`、`Backend/log/backend-error.log`
   - 阅读最近的 MCP 日志：`GameServer/log/mcp-*.log`（MCP 进程日志落盘位置）
   - 根据 bug 描述搜索相关代码（用 Grep/Glob 定位）
   - 如果是 HTTP 接口问题，用 `curl` 复现并获取完整错误响应

2. **形成假设**：基于日志和代码，列出最可能的 1-3 个根因假设

3. **验证假设**：阅读嫌疑代码，确认真正的根因。追踪调用链直到找到问题源头

4. **输出根因摘要**（打印给用户看）：
   ```
   ## 根因分析
   - 现象：<用户描述的问题>
   - 根因：<具体原因，含文件路径和行号>
   - 影响范围：<哪些功能/接口受影响>
   - 修复方案：<最小化修复策略>
   ```

### 阶段二：实施修复

**原则：最小化修改，只改必须改的。**

1. **编写修复代码**：直接修改问题文件
2. **编译验证**：
   - Go: `cd Backend && go build ./... && go vet ./...`
   - TS: `cd Frontend && npx tsc --noEmit` 或 `cd MCP && npx tsc --noEmit`
   - 编译失败则立即修复，不进入下一步
3. **运行相关测试**：
   - Go: `go test -short ./相关包/...`
   - TS: `npx jest 相关文件`
   - 测试失败则修复测试或代码，确保全部通过
4. **手动验证**（如果是 HTTP 接口问题）：
   - 用 `curl` 发送请求验证修复效果
   - 确认返回正确的状态码和响应

### 阶段三：Codex 对抗审查

修复完成后，必须调用 `.claude/commands/bug/fix-review.md` 的审查契约，由 Codex 独立完成 review。

**执行方式：**
使用 Codex CLI：`codex exec --full-auto`

**给 Codex 的输入必须包含：**
1. 当前 bug 描述
2. 根因分析摘要
3. `git diff HEAD` 的变更范围
4. `.claude/commands/bug/fix-review.md`
5. `.ai/constitution.md`（项目宪法）和 `.claude/constitution.md`（运行时规则）

**输出要求：**
- 审查结果必须遵循 `bug/fix-review.md` 中的报告结构
- 必须包含 `## Context Repairs`；如果无则写 `- 无`
- 最后一行必须输出 `<!-- counts: critical=X high=Y medium=Z -->`

**处理审查结果：**
- `critical > 0`：必须修复后重新提交审查，最多 3 轮
- `critical = 0`：修复完成

### 阶段四：提交 + 经验固化

1. **提交代码**：使用 `/git:commit` 提交修复，commit message 格式 `fix(<模块>): <修复描述>`

2. **经验固化**（判断是否需要）：
   - 如果 Bug 暴露了项目通用规则缺失 → 更新 `.ai/constitution.md` 或 `.ai/context/project.md`
   - 如果 Bug 暴露了 Claude 执行流程问题 → 更新 `.claude/rules/` 或 `.claude/skills/`
   - 如果是一次性问题（配置错误、笔误等）→ 不需要固化，跳过

---

## 注意事项

- 全程由 Claude 负责决策和编码，Codex 只负责 review
- 修复前先理解问题，不要盲目改代码
- 保持修改最小化：一个 Bug 一个修复，不顺手重构
- 如果问题涉及多个模块，按依赖顺序逐个修复
- 如果无法复现或定位根因，向用户请求更多信息
