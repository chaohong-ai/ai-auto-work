---
description: 通过需求和AI共创实现方案
argument-hint: [version_id feature_name]
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 工具搜索 `Docs/Version/*/` 下的子目录，将参数中的空格分隔词与目录结构匹配
2. **斜杠分隔**：如果参数包含 `/`，按 `/` 拆分为 version_id 和 feature_name
3. **验证路径**：确认 `Docs/Version/{version_id}/{feature_name}/feature.md`（或兼容旧版 `feature.json`）存在
4. **无法自动匹配时**：使用 AskUserQuestion 向用户确认

获得完整参数后再继续。

## 任务

基于需求文档 `Docs/Version/{version_id}/{feature_name}/feature.md`（或 `feature.json`）进行业务需求共创，输出 Markdown 格式的技术规格 `plan.md`。

## 你的角色

1. 精通 AI 游戏创作平台架构的技术专家
2. 熟悉 Godot 4 引擎、MCP 协议、Docker 容器编排
3. 熟悉当前项目架构（Go+Gin 服务端、Next.js 客户端、TypeScript MCP、GDScript 引擎模板）

## 工作流程

### 第一步：建立上下文

**使用并行 Agent：**

- **Agent 1（文档）**：阅读需求文档 + `.ai/constitution.md`（项目宪法）和 `.claude/constitution.md`（运行时规则）
- **Agent 2（设计）**：阅读 `Docs/Engine/` 和 `Docs/Research/` 下相关文档
- **Agent 3（代码）**：调研 `Backend/`、`MCP/`、`Frontend/`、`Engine/` 中相关的现有实现

### 第二步：结构化需求澄清

通过提问澄清需求，覆盖以下维度：

**通用：** 功能边界、数据模型、API 设计、错误与异常、并发与时序、边界条件

**Server：** Handler 职责、Redis Streams 设计、MongoDB/Redis 选型

**MCP：** 语义化工具设计、Godot 通信格式、Session 管理

**Client：** UI/UX 交互、状态管理、SSE 推送

**Engine：** Godot 场景、GDScript 脚本、模板设计

每次问不超过 8 个问题，等回答后再继续。

### 第三步：方案摘要确认

输出简短摘要（不超过一屏）：
- 核心设计思路
- Server / MCP / Client / Engine 各模块职责
- 关键数据流
- 主要技术决策点

等确认后进入下一步。

### 第四步：评估复杂度并输出 plan.md

**简单方案**（模块 ≤ 3、API/工具 ≤ 5）→ 单文件
**复杂方案**（模块 > 3 或 API > 5）→ 主文件 + plan/ 子文件

**目录结构：**
```
Docs/Version/{version_id}/{feature_name}/
├── feature.md
├── plan.md             # 主文件：概述 + 索引 + 关键决策
└── plan/               # 详情（仅复杂方案）
    ├── api.md
    ├── flow.md
    ├── server.md
    ├── client.md
    ├── engine.md
    └── testing.md
```

**plan.md 格式模板：**

```markdown
# {feature_name} 技术规格

## 概述
功能目标和范围描述。

- **复杂度**: simple|complex
- **子文件**: （仅复杂方案时列出 plan/ 下的子文件）

## API 设计

| 名称 | 类型 | 模块 | 描述 | 关键字段 |
|------|------|------|------|----------|
| xxx  | rest/mcp_tool/sse | server/mcp/client | 用途 | field1, field2 |

## 核心流程

### 主流程: {流程名}
1. 步骤1
2. 步骤2

### 异常流程: {异常名}
- **触发条件**: xxx
- **处理方式**: xxx

## Server 设计

### 数据模型
| 名称 | 存储 | 关键字段 |
|------|------|----------|
| xxx  | mongodb/redis/memory | field1, field2 |

### Handler
| 名称 | 方法 | 路径 |
|------|------|------|
| xxx  | GET/POST | /v1/xxx |

### 队列消费者
| 名称 | Stream | 描述 |
|------|--------|------|
| xxx  | stream_name | 描述 |

## MCP 设计

### 工具
| 名称 | Level | 描述 | 输入参数 |
|------|-------|------|----------|
| xxx  | 2/3   | 描述 | param1, param2 |

### Godot 通信
通信方式描述。

## Client 设计

### 页面
| 名称 | 路由 | 描述 |
|------|------|------|
| xxx  | /path | 描述 |

### 组件
| 名称 | 描述 |
|------|------|
| xxx  | 描述 |

### SSE 事件
- event_name: 描述

## Engine 设计
- **模板**: xxx
- **场景**: xxx
- **脚本**: xxx

## 测试计划
- **Server**: 测试项列表
- **MCP**: 测试项列表
- **Client**: 测试项列表
- **Engine**: 测试项列表

## 文件清单

| 路径 | 操作 | 模块 | 描述 |
|------|------|------|------|
| path/to/file | create/modify | server/mcp/client/engine/tools | 描述 |

## 合宪性自检
- 自检备注
```

### 第五步：合宪性自检

对照 `.ai/constitution.md`（项目宪法）和 `.claude/constitution.md`（运行时规则）六条原则自检：

- **第一条**：不必要的复杂性或依赖？
- **第二条**：测试计划覆盖关键路径？
- **第三条**：错误处理和日志充分？
- **第四条**：模块职责清晰？MCP 语义化？
- **第五条**：Redis Streams 幂等？容器安全？
- **第六条**：数据流清晰？Schema 校验到位？

---

## 自动化调用契约

脚本通过 `claude -p` 调用时使用 `.claude/contracts/feature-plan/` 下的契约片段，避免读取上方完整工作流。

契约文件（loop 脚本与本文档共用同一份）：
- `inputs.md` — 必读输入
- `expand.md` — 按需展开
- `outputs.md` — 输出要求
- `gates.md` — 硬性 gate（含合宪性 6 条自检）

---

请先完成参数解析，然后执行第一步。
