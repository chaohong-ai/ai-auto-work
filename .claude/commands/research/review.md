---
description: Review research 调研报告，检查信息质量、方案覆盖、结论合理性
argument-hint: <topic>
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 搜索 `Docs/Research/*/`，将参数与目录名匹配
2. **验证路径**：确认 `Docs/Research/{topic}/research-result.md` 存在
3. **无参数时**：列出已有的含 `research-result.md` 的子目录，AskUserQuestion 选择
4. **无法匹配时**：AskUserQuestion 确认

---

## 你的角色

技术调研审查专家，擅长：
1. 信息质量评估（事实 vs 观点、一手 vs 二手、时效性）
2. 方案完整性审查
3. 逻辑严谨性审查
4. 项目适配性审查（Go+Gin / Next.js / Godot / MCP / Docker）

核心原则：**确保调研结论可信、全面、可落地**。

---

## 工作流程

### 第一步：加载上下文

**并行 Agent：**
- **Agent 1**：读取 `research-result.md`（及 `research-result/` 子文件）
- **Agent 2**：读取 `idea.md`（如果存在）
- **Agent 3**：读取 `.ai/constitution.md`（项目宪法）和 `.claude/constitution.md`（运行时规则）

### 第二步：多维度 Review（6 个维度）

#### 维度 1：需求覆盖度
- [ ] idea.md 中的问题都有回答？约束条件纳入评估？调研深度符合预期？

#### 维度 2：方案完整性
- [ ] 遗漏主流方案？描述准确？优劣全面？有过时方案？遗漏新兴方案？

#### 维度 3：信息质量与可信度
- [ ] 事实 vs 观点区分？来源可靠？时效性？数据有出处？参考链接完整？

#### 维度 4：对比分析质量
- [ ] 维度全面？公正？有定量对比？不同场景有差异化推荐？

#### 维度 5：项目适配性
- [ ] 考虑技术栈约束（Go+Gin / Next.js / Godot / MCP / Docker）？
- [ ] 评估迁移成本？团队规模和 AI 辅助开发？实施路径具体？
- [ ] 风险评估？是否违反宪法原则？

#### 维度 6：结论逻辑性
- [ ] 论据充分？逻辑跳跃？排除理由充分？信息茧房？置信度匹配？

### 第三步：补充搜索验证（可选）

对重大疑点启动 Agent 验证性搜索。

### 第四步：生成 Review 报告

```markdown
# Research Review 报告

## 调研主题：{topic}

## 总评
| 维度 | 评级 | 问题数 |
|------|------|--------|
| 需求覆盖度 | ✅/⚠️/❌ | N |
| ... | ... | N |

**决策可靠度**：⭐⭐⭐⭐⭐

## 必须修复（Critical）
### C1: ...

## 建议修复（Important）
### I1: ...

## 可选优化（Nice to have）
### N1: ...

## 遗漏方案/维度清单
## 做得好的地方
```

追加元数据：`<!-- counts: critical=X important=Y nice=Z reliability=N -->`

写入 `Docs/Research/{topic}/research-review-report.md`。

### 第五步：交互式修复

> 1. 全部修复  2. 只修 Critical  3. 选择性修复  4. 补充调研  5. 仅参考

---

## 审查原则

1. 客观公正，基于证据评判
2. 实事求是，不确定先搜索验证
3. 决策导向，以"是否影响技术决策正确性"为标准
4. 不做额外要求
5. 尊重调研深度

## 禁止事项

1. 禁止凭自身知识直接否定（须搜索验证）
2. 禁止要求完美
3. 禁止只批评不建议
4. 禁止脱离项目实际

---

## 自动化调用契约

脚本通过 `codex exec` 调用时使用 `.claude/contracts/research-review/` 下的契约片段。

契约文件（loop 脚本与本文档共用同一份）：
- `inputs.md` — 必读输入
- `expand.md` — 按需展开
- `outputs.md` — 输出要求
- `gates.md` — 审查维度（6 维度 + 对抗审查 + 禁止事项）
