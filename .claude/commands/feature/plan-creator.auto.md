---
description: "[auto-work] 自动模式创建 plan.md，无用户交互"
argument-hint: [version_id feature_name]
---

## 参数

参数已预解析，直接使用：`$ARGUMENTS`

验证 `Docs/Version/{version_id}/{feature_name}/feature.md` 存在。

## 任务

基于 `feature.md` 生成技术规格 `plan.md`。

## 工作流程

### 第一步：建立上下文

先判定本次 feature 命中的模块（Backend / MCP / Frontend / Engine / Tools / 跨模块）。

**并行 Agent：**
- **Agent 1**：阅读需求文档 + `.ai/constitution.md`；只有遇到代码级细则不明确时再补读 `.claude/constitution.md`
- **Agent 2**：仅阅读与命中模块直接相关的 `Docs/Architecture/modules/*.md`、`Docs/Research/`、`Docs/Engine/` 文档
- **Agent 3**：仅调研命中模块目录中的现有实现；未命中的目录不要预读

模块选择规则：
- 只涉及单模块时，禁止默认加载其他模块背景
- 只有 plan 明确包含跨模块接口、调用链或数据流变更时，才升级为跨模块上下文

### 第二步：自主决策需求

基于 feature.md、宪法、现有代码上下文自行判断所有需求细节。不确定的决策标注 [自主决策]。

覆盖维度：功能边界、数据模型、API 设计、错误与异常、并发与时序、边界条件。

### 第三步：评估复杂度并输出 plan.md

**简单方案**（模块 ≤ 3、API/工具 ≤ 5）→ 单文件
**复杂方案**（模块 > 3 或 API > 5）→ 主文件 + plan/ 子文件

**目录结构：**
```
Docs/Version/{version_id}/{feature_name}/
├── feature.md
├── plan.md
└── plan/  (仅复杂方案)
```

plan.md 只需要覆盖本次命中模块的设计；未命中的模块写 `N/A` 或省略，不要为了模板完整性硬写 Server/MCP/Client/Engine 全套。

### 第四步：合宪性自检

对照 `.ai/constitution.md`（项目宪法）和 `.claude/constitution.md`（运行时规则）自检：简单性、测试先行、明确性、单一职责、并发安全、跨模块通信。

---

完成所有步骤后直接结束，不要中途停下来。
