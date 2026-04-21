---
description: Review生成的plan，检查边界情况、场景覆盖、架构合理性
argument-hint: [version_id feature_name]
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 工具搜索 `Docs/Version/*/` 下的子目录
2. **斜杠分隔**：如果参数包含 `/`，按 `/` 拆分
3. **验证路径**：确认 `Docs/Version/{version_id}/{feature_name}/plan.md`（或 `plan.json`）存在
4. **无法匹配时**：AskUserQuestion

获得完整参数后再继续。

## 任务

对 plan.md（及 plan/*.md 子文件；兼容旧版 .json）进行深度 Review。

## 你的角色

1. **资深 Code Reviewer**：实现可行性
2. **QA 工程师**：测试和边界场景
3. **安全工程师**：安全和容器隔离
4. **运维工程师**：部署、监控、可观测性

## 工作流程

### 第一步：加载上下文

**并行 Agent：**
- **Agent 1**：读取 plan.md；`plan/` 子文件仅当审查命中对应模块时读取
- **Agent 2**：读取 feature.md（或 feature.json）
- **Agent 3**：读取 `.ai/constitution.md`；只有遇到代码级细则不明确时再补读 `.claude/constitution.md`

加载规则：
- 先判断该 plan 实际命中的模块；未命中的模块维度不展开
- 只有 plan 明确涉及 MCP/Godot/Engine 时，才审查对应维度
- 纯 Backend / Frontend / Tools 方案，不要默认代入 Godot/MCP 约束

### 第二步：多维度 Review（7 个维度）

#### 维度 1：需求覆盖度
- [ ] 每个功能点有对应设计？遗漏？隐含需求？

#### 维度 2：边界条件与异常场景

**数据边界：** 空数据、容器上限、并发修改、恶意输入
**时序边界：** AI 超时、Godot 崩溃、重复请求、SSE 断开
**状态边界：** 容器生命周期、Redis Streams 失败重试、并发会话隔离

#### 维度 3：API 与工具设计
- [ ] REST API 字段完整？MCP 工具语义化（Level 2/3）？
- [ ] 错误码覆盖？SSE 事件覆盖？分页？幂等性？

#### 维度 4：服务端设计
- [ ] Handler/Service 职责清晰？Redis Streams 幂等？
- [ ] MongoDB/Redis 模型合理？Docker 资源限制？健康检查？

#### 维度 5：MCP 与引擎设计（仅当命中 MCP / Engine 时）
- [ ] MCP 工具语义化？Godot 通信超时？工具失败回滚？
- [ ] GDScript 模板扩展性？资源管理统一？

#### 维度 6：安全与容器隔离（仅当命中容器 / session / 外部执行环境时）
- [ ] Docker 资源限制？用户输入过滤？容器隔离（gVisor）？
- [ ] API 频率限制？资源大小限制？数据流 Client→Server→MCP→Godot？

#### 维度 7：可测试性与可观测性
- [ ] 关键操作有日志？测试覆盖主要流程？容器监控？AI 生成链路可追溯？

### 第三步：生成 Review 报告

```markdown
# Plan Review 报告

## 总评
| 维度 | 评级 | 问题数 |
|------|------|--------|
| 需求覆盖度 | ✅/⚠️/❌ | N |
| ... | ... | N |

## 必须修复（Critical）
### C1: [标题]
- **位置/问题/影响/建议**

## 建议修复（Important）
### I1: [标题]

## 可选优化（Nice to have）
### N1: [标题]

## Context Repairs
- **类型**: shared-context | constitution | command | skill | rule
- **目标文件**: `.ai/context/project.md` / `.ai/constitution.md` / `.claude/commands/...` / `.claude/skills/...` / `.claude/rules/...`
- **问题**: Claude 缺了什么上下文，导致本次方案出现系统性偏差
- **建议补充**: 应沉淀的规则、术语、架构约束或工作约定
- **触发条件**: 为什么这不是单次失误，而是应该长期固化的知识

## 遗漏场景清单
## 做得好的地方
```

追加元数据：`<!-- counts: critical=X important=Y nice=Z -->`

写入 `Docs/Version/{version_id}/{feature_name}/plan-review-report.md`。

### 第四步：交互式修复

> 1. 全部修复  2. 只修 Critical  3. 选择性修复  4. 仅参考

---

## Context Repairs 判定规则

如果你发现以下任一情况，必须输出 `## Context Repairs` 段：

1. 方案错误源于 Claude 没读到现有项目事实，而不是单次推理失误
2. 同类问题预计会在后续 feature/bug 中反复出现
3. 该问题更适合沉淀为共享知识、命令约束、skill 或 rule，而不是只在本轮修 plan

输出要求：

- 没有上下文缺口时，也保留 `## Context Repairs` 标题，并写 `- 无`
- 有上下文缺口时，明确指出**应该更新哪个文件**
- 优先落到 `.ai/`；只有 Claude 专属运行方式问题才落到 `.claude/`

---

## 自动化调用契约

脚本通过 `codex exec` 调用时使用 `.claude/contracts/feature-plan-review/` 下的契约片段。

契约文件（loop 脚本与本文档共用同一份）：
- `inputs.md` — 必读输入
- `expand.md` — 按需展开
- `outputs.md` — 输出要求
- `gates.md` — 审查维度（7 维度 + 对抗审查重点）

---

请先完成参数解析，然后执行。
