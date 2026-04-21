---
description: Review feature-developing 生成的代码，检查遗漏和宪法违规
argument-hint: [version_id feature_name]
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 工具搜索 `Docs/Version/*/` 下的子目录，将参数中的空格分隔词与目录结构匹配
2. **斜杠分隔**：如果参数包含 `/`，按 `/` 拆分为 version_id 和 feature_name
3. **验证路径**：确认 `Docs/Version/{version_id}/{feature_name}/` 目录存在
4. **无参数时**：使用 `git diff --name-only HEAD` 获取最近变更文件，自动推断功能范围
5. **无法自动匹配时**：使用 AskUserQuestion 向用户确认

获得完整参数后再继续。

---

## 你的角色

你是一名资深代码审查专家，精通：
1. Go 服务端开发（Gin、Zap、MongoDB、Redis Streams）
2. TypeScript 开发（Next.js 14、Express MCP 服务）
3. GDScript 开发（Godot 4 游戏模板）
4. 本项目架构（Docker 容器编排、MCP 语义化工具、Redis Streams 任务队列）

你的核心原则：**以宪法为准绳，以 plan 为基线，找出实现中的遗漏和偏差**。

---

## 工作流程

### 第一步：建立审查上下文

**使用并行 Agent 加速上下文建立：**

- **Agent 1（plan + feature）**：阅读 `Docs/Version/{version_id}/{feature_name}/plan.md` 和 `feature.md`；`plan/` 子文件仅当审查命中对应模块时读取。返回：需求摘要、预期文件清单、关键设计决策
- **Agent 2（开发日志）**：阅读 `develop-log.md`（如果存在）。返回：已实现文件清单、关键决策、待办事项
- **Agent 3（宪法）**：阅读 `.ai/constitution.md`；只有遇到代码级细则不明确时再补读 `.claude/constitution.md` 或专题 guide。返回：检查项清单

加载规则：
- 先根据变更文件列表判定命中模块，再展开对应检查项
- 未命中的语言和模块不审查、不预读
- fake/mock 链路才读取 `.claude/guides/fake-env-closure.md`
- Go 取消/超时/Shutdown/后台任务状态机才读取 `.claude/guides/go-cancellation-semantics.md`

### 第一步半：计划产物清单 vs 文件系统 diff

在收集代码变更之前，先从 `feature.md` + `plan/*.md` 提取所有声明为"新建"、"create"、"新增"的目标文件路径，然后用 Glob 与实际工作区交叉检查：

- 计划声明但工作区不存在的文件 → 直接记为 **CRITICAL**（产物缺失）
- 此步骤的缺失清单独立于代码质量问题，属于交付完整性审查

### 第二步：收集代码变更

1. **有 develop-log.md**：从日志中提取变更文件列表
2. **无 develop-log.md**：`git diff --name-only` 对比 main 基线
3. **用户指定文件**：直接使用

**阅读所有变更文件的完整代码**。不跳过任何文件。

### 第三步：合宪性审查（最高优先级）

**使用并行 Agent 分模块审查：**

**Agent A（Go 代码）** — 检查 `.go` 文件：

| 条款 | 检查项 | 严重级 |
|------|--------|--------|
| 编译正确性 | import 完整？包名正确？API 存在？ | CRITICAL |
| 3.1 错误处理 | error 显式处理？`fmt.Errorf` 包装？禁止 `_` 丢弃 | CRITICAL |
| 3.2 错误日志 | 产生错误处有 `logger.Error(..., zap.Error(err))`？ | CRITICAL |
| 3.3 无全局状态 | 新增全局变量？ | HIGH |
| 3.4 注释 | 导出类型/函数有 GoDoc？ | MEDIUM |
| 1.1 YAGNI | plan 未要求的额外功能？ | HIGH |
| 2.1 TDD | 有表格驱动测试？ | HIGH |
| 5.1 Redis Streams | 消费幂等？ACK 正确？ | CRITICAL |
| 5.2.1 defer 锁 | Mutex 用 defer 释放？ | CRITICAL |
| 5.2.2 Context | 阻塞操作接受 context.Context？ | HIGH |
| 5.2.3 Goroutine | 有退出机制？ | HIGH |
| 5.3 容器 | Docker 资源限制？健康检查？ | HIGH |
| 6.2 Schema | Gin binding 校验？ | HIGH |

**Agent B（TypeScript 代码）** — 仅当变更包含 `.ts` / `.tsx` 文件时检查：

| 条款 | 检查项 | 严重级 |
|------|--------|--------|
| 编译正确性 | import 完整？类型正确？ | CRITICAL |
| 3.1 错误处理 | 空 catch？Promise 无错误处理？ | CRITICAL |
| 3.2 错误日志 | MCP 用 Winston 记录？ | CRITICAL |
| 3.3 无全局状态 | 全局变量传递状态？ | HIGH |
| 5.4.1 async/await | 有回调地狱？ | HIGH |
| 5.4.2 错误边界 | Express 路由有 try/catch？ | CRITICAL |
| 5.4.3 超时 | Godot TCP/WS 通信有超时？ | HIGH |
| 6.2 Schema | 外部输入用 Zod 校验？ | CRITICAL |
| 6.3 MCP 语义化 | 工具保持 Level 2/3？ | HIGH |

**Agent C（GDScript）** — 仅当变更包含 `.gd` 文件时检查：

| 检查项 | 严重级 |
|--------|--------|
| 信号连接/断开正确？ | HIGH |
| 节点引用安全（null 检查）？ | HIGH |
| 资源路径正确？ | HIGH |
| 生命周期管理完整？ | MEDIUM |

**Agent D（Python）** — 仅当变更包含 `.py` 文件时检查：

| 条款 | 检查项 | 严重级 |
|------|--------|--------|
| 3.1 错误处理 | 裸 except 或 pass？ | CRITICAL |
| 6.2 Schema | Pydantic/FastAPI 校验？ | HIGH |

### 第四步：Plan 完整性审查

1. **遗漏**：plan 列出但未实现的文件/功能
2. **偏差**：实现与 plan 设计不一致
3. **接口一致性**：Server API 和 MCP 工具接口匹配？
4. **流程完整性**：正常路径 + 异常路径覆盖？
5. **数据流向**：Client → Server → MCP → Godot 是否遵循？

### 第五步：边界情况与健壮性审查

**通用：** null 检查、并发/时序、异常路径、资源泄漏
**Go：** error 未检查、goroutine 泄漏、context 超时、MongoDB/Redis 失败处理
**Go 异步终态：** `cancel`/`timeout`/`retry` 操作必须验证最终持久化状态（而非仅看首个 HTTP 响应）；`context.Canceled` 与 `context.DeadlineExceeded` 不得被通用失败路径覆盖
**TS MCP：** WebSocket 断开重连、Godot 超时/崩溃、并发请求隔离
**TS Client：** SSE 断开、用户快速操作防抖、组件卸载清理
**Router/JWT：** 受 JWT 保护的 handler 测试必须至少保留一组经由真实 router + middleware 的用例，不能全部绕过中间件直接调用 handler
**GDScript：** 节点生命周期引用、信号泄漏、资源路径不存在

### 第六步：代码质量审查

**安全 (CRITICAL)：** 硬编码密钥、注入风险、容器逃逸、绕过数据流
**质量 (HIGH)：** 函数 >80 行、嵌套 >4 层、魔法数字、重复代码
**可维护性 (MEDIUM)：** 缺文档注释、控制块 >10 行未封装、缺日志

### 第六步半：测试覆盖审查

检查新增/修改的代码是否有充分的测试覆盖：

| 检查项 | 严重级 | 说明 |
|--------|--------|------|
| Handler/Service 实现无对应测试文件 | CRITICAL | 每个 Handler/Service 必须有对应的 `_test.go` / `.test.ts` / `test_*.py` |
| 新增 HTTP 端点缺少路由注册测试或 Hurl 冒烟测试 | CRITICAL | 新增的 HTTP 端点必须同时有：(1) router_test.go 中的路由注册测试 (2) Backend/tests/smoke/ 中的 Hurl 冒烟测试。缺失任一项判定为 CRITICAL。 |
| 测试只覆盖 happy path | Important | 应包含错误输入、边界条件、异常路径的测试用例 |
| 测试/功能代码比例低于 1:2 | Nice-to-have | 新增测试代码行数应至少达到功能代码行数的 50% |

**审查方法：**
1. 列出所有新增/修改的源文件（排除测试文件本身）
2. 对每个源文件，检查同目录或对应测试目录下是否存在测试文件：
   - Go: `*_test.go`（同目录）
   - TypeScript: `*.test.ts` / `*.spec.ts`（同目录或 `__tests__/`）
   - Python: `test_*.py`（同目录或 `tests/`）
3. 对已有测试文件，检查是否覆盖了新增的导出函数/方法
4. 检查测试用例是否包含错误场景和边界条件

### 第七步：输出审查报告

```
═══════════════════════════════════════════════
  Feature Review 报告
  功能：{feature_name}
  版本：{version_id}
  审查文件：{N} 个
═══════════════════════════════════════════════

## 一、合宪性审查

### Go 代码
| 条款 | 状态 | 说明 |
|------|------|------|

### TypeScript 代码
| 条款 | 状态 | 说明 |
|------|------|------|

### GDScript 代码（如涉及）
| 检查项 | 状态 | 说明 |
|--------|------|------|

## 二、Plan 完整性
### 已实现 / 遗漏 / 偏差

## 三、边界情况
[CRITICAL/HIGH/MEDIUM] 文件:行号 - 问题描述

## 四、代码质量

## 五、测试覆盖
| 源文件 | 测试文件 | 状态 | 严重级 |
|--------|----------|------|--------|

## 六、Context Repairs
- **类型**: shared-context | constitution | command | skill | rule
- **目标文件**: `.ai/context/project.md` / `.ai/constitution.md` / `.claude/commands/...` / `.claude/skills/...` / `.claude/rules/...`
- **问题**: Claude 缺了什么上下文，导致本次实现偏差、遗漏或重复犯错
- **建议补充**: 应沉淀的规则、术语、边界条件、测试约束或项目模式
- **触发条件**: 为什么这是系统性问题，而不是一次性编码失误

## 七、总结
  CRITICAL: X  HIGH: Y  MEDIUM: Z
  结论: [通过 / 需修复后再提交]
```

**最后一行追加元数据：**
```
<!-- counts: critical=X high=Y medium=Z -->
```

写入 `Docs/Version/{version_id}/{feature_name}/develop-review-report.md`。

---

## Context Repairs 判定规则

如果你发现以下任一情况，必须输出 `## 六、Context Repairs`：

1. Claude 忽略了仓库里已经存在的实现模式、约束或边界条件
2. review 中的问题更像"上下文没加载全"，而不是"代码不会写"
3. 同类问题后续大概率重复出现，应该沉淀到共享知识或 Claude 运行时文档

输出要求：

- 没有上下文缺口时，也保留该节并写 `- 无`
- 有上下文缺口时，给出明确落点文件，不要只写抽象建议
- 项目事实优先更新 `.ai/`，Claude 专属流程问题再更新 `.claude/`

---

## 审查原则

1. **宪法最高**：宪法违规一律 CRITICAL
2. **实事求是**：只报告确认的问题，不确定先 Grep 确认
3. **关注影响**：说明实际影响
4. **不做额外要求**：不要求 plan 范围外的内容
5. **给出上下文**：引用文件名和行号

---

## 自动化调用契约

脚本通过 `codex exec` 调用时使用 `.claude/contracts/feature-develop-review/` 下的契约片段。

契约文件（loop 脚本与本文档共用同一份）：
- `inputs.md` — 必读输入
- `expand.md` — 按需展开
- `outputs.md` — 输出要求
- `gates.md` — 审查维度（逐语言 + router/JWT + 对抗审查重点）
