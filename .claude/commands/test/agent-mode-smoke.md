---
description: "ROUTE_MODE_B e2e smoke：真实 Agent 调用验证 S 级和 M 级路径"
argument-hint: [s|m|all]
---

## 概述

本命令是 auto-work Agent 编排模式（ROUTE_MODE_B）的端到端冒烟测试。
使用**真实 Agent 调用**走完 S 级和 M 级的核心路径，验证文件产物、收敛逻辑和阶段衔接。

所有产出物在隔离目录 `Docs/Version/_test_smoke/` 中，测试结束后清理。

## 参数

- `s` — 仅跑 S 级路径
- `m` — 仅跑 M 级路径
- `all`（默认）— 两条路径都跑

## 执行

解析参数：`$ARGUMENTS` 取第一个词，默认 `all`。

---

### 准备阶段

```bash
rm -rf Docs/Version/_test_smoke
mkdir -p Docs/Version/_test_smoke/s-track
mkdir -p Docs/Version/_test_smoke/m-track
```

记录基线：
```bash
git rev-parse HEAD
```
保存为 `SMOKE_BASELINE`，结束时用于 `git checkout` 恢复。

初始化结果计数器 `SMOKE_PASS=0, SMOKE_FAIL=0`。

验证检查函数逻辑：文件存在且非空算 PASS，否则 FAIL。

---

### PATH-S：S 级路径（type=direct, complexity=S）

> 需求：在 `_test_smoke_workspace/` 下创建 `hello.py`，内容为 `print("hello from agent mode")`，并创建 `test_hello.py` 验证其输出。

#### S-1: 需求分类

启动 Agent：

```
Agent({
  description: "Smoke-S 分类",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名全栈工程师。请判断以下需求的工作类型和复杂度。

需求：在 _test_smoke_workspace/ 下创建 hello.py（内容 print('hello from agent mode')）和 test_hello.py（验证输出）。

将结果写入 Docs/Version/_test_smoke/s-track/classification.txt，严格两行格式：
type=direct 或 type=research
complexity=S 或 complexity=M 或 complexity=L

不要做其他任何事。"
})
```

**验证**：
1. `Docs/Version/_test_smoke/s-track/classification.txt` 存在且非空 → PASS/FAIL
2. 内容包含 `type=direct` → PASS/FAIL（S 级需求应判定为 direct）
3. 内容包含 `complexity=S` → PASS/FAIL（单文件应判定为 S）

#### S-2: 直接开发（S-Track 不经过 feature/plan/task 拆分）

```
Agent({
  description: "Smoke-S 直接开发",
  mode: "bypassPermissions",
  model: "opus",
  prompt: "请直接实现以下需求：

在项目根目录下创建 _test_smoke_workspace/hello.py，内容：
print('hello from agent mode')

在项目根目录下创建 _test_smoke_workspace/test_hello.py，内容：
import subprocess, sys
result = subprocess.run([sys.executable, '_test_smoke_workspace/hello.py'], capture_output=True, text=True)
assert 'hello from agent mode' in result.stdout, f'Unexpected: {result.stdout}'
print('test passed')

确保两个文件都创建成功。不要修改项目中的任何其他文件。"
})
```

**验证**（编排者用 Bash 直接检查）：
1. `_test_smoke_workspace/hello.py` 存在 → PASS/FAIL
2. `_test_smoke_workspace/test_hello.py` 存在 → PASS/FAIL
3. 运行 `python _test_smoke_workspace/test_hello.py`，退出码 0 → PASS/FAIL

#### S 路径总结

汇总 S 路径的 PASS/FAIL 数。期望：5 PASS / 0 FAIL。

---

### PATH-M：M 级路径（type=direct, complexity=M）

> 需求：在 `_test_smoke_workspace/calc/` 下创建一个简单的计算器 Python 模块 — `calc.py`（add, subtract, multiply 三个函数）+ `test_calc.py`（每个函数至少 2 个测试用例）+ `__init__.py`。

#### M-1: 需求分类

```
Agent({
  description: "Smoke-M 分类",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名全栈工程师。请判断以下需求的工作类型和复杂度。

需求：在 _test_smoke_workspace/calc/ 下创建计算器 Python 模块 — calc.py（add, subtract, multiply 三个函数）+ test_calc.py（每个函数至少 2 个测试用例）+ __init__.py。共 3 个文件，逻辑清晰。

将结果写入 Docs/Version/_test_smoke/m-track/classification.txt，严格两行格式：
type=direct 或 type=research
complexity=S 或 complexity=M 或 complexity=L

不要做其他任何事。"
})
```

**验证**：
1. classification.txt 存在且非空 → PASS/FAIL
2. 内容包含 `type=direct` → PASS/FAIL
3. 内容包含 `complexity=M` 或 `complexity=S` → PASS/FAIL（M 或 S 均可接受）

#### M-2: 生成 feature.md

```
Agent({
  description: "Smoke-M feature.md",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "请为以下需求生成功能需求文档，写入 Docs/Version/_test_smoke/m-track/feature.md。

需求：在 _test_smoke_workspace/calc/ 下创建计算器 Python 模块 — calc.py（add, subtract, multiply 函数）+ test_calc.py + __init__.py。

格式：
# Calculator Module
## 概述
## 需求列表（REQ-001 到 REQ-003，每个函数一条，P0）
## 验收条件

保持简洁。不要做其他任何事。"
})
```

**验证**：
1. `Docs/Version/_test_smoke/m-track/feature.md` 存在且非空 → PASS/FAIL
2. 包含 `REQ-` → PASS/FAIL

#### M-3: 生成 plan.md

```
Agent({
  description: "Smoke-M plan.md",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "读取 Docs/Version/_test_smoke/m-track/feature.md，生成技术方案写入 Docs/Version/_test_smoke/m-track/plan.md。

这是一个简单的 Python 模块，plan 应包含：
1. 文件清单（calc.py, test_calc.py, __init__.py）
2. 每个文件的职责
3. 实现顺序

保持简洁。不要做其他任何事。"
})
```

**验证**：
1. `Docs/Version/_test_smoke/m-track/plan.md` 存在且非空 → PASS/FAIL

#### M-4: Plan Review（Agent 审查者角色）

```
Agent({
  description: "Smoke-M plan review",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名严苛的架构审查者。请审查以下 plan。

读取 Docs/Version/_test_smoke/m-track/plan.md 和 Docs/Version/_test_smoke/m-track/feature.md。

输出写入 Docs/Version/_test_smoke/m-track/plan-review-report.md，格式：
## Critical
## Important
## Nice to have
## Context Repairs
- 无

最后一行：<!-- counts: critical=0 important=0 nice=0 -->

注意：这是一个简单 smoke 测试用例，不需要过于严苛。"
})
```

**验证**：
1. plan-review-report.md 存在 → PASS/FAIL
2. 包含 `<!-- counts:` → PASS/FAIL（收敛判断所需格式）

#### M-5: 任务拆分

```
Agent({
  description: "Smoke-M 任务拆分",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "读取 Docs/Version/_test_smoke/m-track/plan.md，将方案拆分为任务。

输出到 Docs/Version/_test_smoke/m-track/tasks/ 目录：
- task-01.md（创建 __init__.py + calc.py）
- task-02.md（创建 test_calc.py）
- README.md（索引）

每个 task 文件格式：
---
name: 任务名
status: pending
estimated_files: N
estimated_lines: N
verify_commands: []
depends_on: []
---

## 范围
...

不要做其他任何事。"
})
```

**验证**：
1. `Docs/Version/_test_smoke/m-track/tasks/task-01.md` 存在 → PASS/FAIL
2. `Docs/Version/_test_smoke/m-track/tasks/task-02.md` 存在 → PASS/FAIL

#### M-6: 开发实现（单次 Agent，不做完整迭代）

```
Agent({
  description: "Smoke-M 开发实现",
  mode: "bypassPermissions",
  model: "opus",
  prompt: "请实现以下两个任务。

读取：
1. Docs/Version/_test_smoke/m-track/tasks/task-01.md
2. Docs/Version/_test_smoke/m-track/tasks/task-02.md
3. Docs/Version/_test_smoke/m-track/plan.md

实现规则：
1. 创建 _test_smoke_workspace/calc/__init__.py（空文件）
2. 创建 _test_smoke_workspace/calc/calc.py（add, subtract, multiply 函数）
3. 创建 _test_smoke_workspace/calc/test_calc.py（每个函数 2 个测试用例，用 pytest 格式）
4. 不要修改项目中的任何其他文件"
})
```

**验证**（编排者直接 Bash）：
1. `_test_smoke_workspace/calc/__init__.py` 存在 → PASS/FAIL
2. `_test_smoke_workspace/calc/calc.py` 存在 → PASS/FAIL
3. `_test_smoke_workspace/calc/test_calc.py` 存在 → PASS/FAIL
4. 运行 `python -m pytest _test_smoke_workspace/calc/test_calc.py -v`，退出码 0 → PASS/FAIL

#### M-7: 代码审查（验证审查者 Agent 能产出带 counts 的报告）

```
Agent({
  description: "Smoke-M 代码审查",
  mode: "bypassPermissions",
  model: "sonnet",
  prompt: "你是一名严苛的架构审查者。请审查刚实现的代码。

检查 _test_smoke_workspace/calc/ 下的所有文件。

输出写入 Docs/Version/_test_smoke/m-track/develop-review-report.md，格式：
## Critical
## High
## Medium
## Context Repairs
- 无

最后一行：<!-- counts: critical=0 high=0 medium=0 -->

注意：这是 smoke 测试，保持合理即可。"
})
```

**验证**：
1. develop-review-report.md 存在 → PASS/FAIL
2. 包含 `<!-- counts:` → PASS/FAIL

**收敛判断验证**（编排者解析 counts）：
```bash
LAST_LINE=$(tail -1 Docs/Version/_test_smoke/m-track/develop-review-report.md)
CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
CRIT=${CRIT:-999}
```
3. counts 可解析（CRIT 不等于 999）→ PASS/FAIL

#### M 路径总结

汇总 M 路径的 PASS/FAIL 数。期望：13 PASS / 0 FAIL。

---

### 清理阶段

无论结果如何，必须执行清理：

```bash
rm -rf _test_smoke_workspace
rm -rf Docs/Version/_test_smoke
# 恢复 git 状态（如有意外变更）
git checkout -- . 2>/dev/null || true
```

---

### 最终报告

输出格式：

```
══════════════════════════════════════
  Agent Mode E2E Smoke 结果
══════════════════════════════════════
  S 路径: {S_PASS}/{S_TOTAL} PASS
  M 路径: {M_PASS}/{M_TOTAL} PASS
  总计:   {TOTAL_PASS}/{GRAND_TOTAL} PASS
  结论:   {全部通过 ? "SMOKE_PASS — ROUTE_MODE_B 核心路径可用" : "SMOKE_FAIL — 详见上方失败项"}
══════════════════════════════════════
```

---

## 限制说明

本 smoke 测试验证的是 Agent 编排的关键路径可走通，不验证：
- 完整的迭代收敛循环（需要多轮 Agent 来回）
- 升级机制（S→M, M→L）
- 验收门禁的完整 REQ 验证
- Context Repair 落盘
- Git commit/push 流程

这些场景需要更重的集成测试或真实 feature 开发来覆盖。
