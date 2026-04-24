---
description: 面向小改动的快速开发流程，跳过调研/方案/验收文档，只做实现+编译+相关测试
argument-hint: <version_id> <feature_name> [需求描述]
---

## 适用范围

`/fast-auto-work` 只用于**快速开发**：

- 已有系统上的直接修改、Bug 修复、小范围扩展
- 预期改动不大，通常在 `<= 3` 个实现文件内
- 项目中已有可复用模式，不需要前置调研或方案设计

**不适用：**

- 新系统设计、跨模块联动、契约变更
- 需要 research / feature / plan / task 拆分的需求
- 需要正式验收、模块文档归档、自动推送的场景

命中以上情况时，不要继续快流程，改用 `/auto-work` 或 `/manual-work`。

---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

参数格式：`<version_id> <feature_name> [需求描述（剩余部分，可选）]`

1. 第一个词：`version_id`
2. 第二个词：`feature_name`
3. 剩余部分：补充需求描述

需求来源按以下顺序合并：

1. `Docs/Version/{version_id}/{feature_name}/idea.md`
2. 用户传入的补充需求

若两者都不存在，则要求用户先补需求。

---

## 执行

使用 Bash 工具执行：

```bash
bash .claude/scripts/fast-auto-work.sh "{VERSION_ID}" "{FEATURE_NAME}" "{用户输入的补充需求}"
```

若没有补充需求，则执行：

```bash
bash .claude/scripts/fast-auto-work.sh "{VERSION_ID}" "{FEATURE_NAME}"
```

---

## 行为约束

该命令的固定策略：

- 强制按 `direct + S` 快路径启动
- 不生成 `feature.md`、`plan.md`、`tasks/task-*.md`
- 不做调研循环、方案 review、验收报告、模块文档、git push
- 保留编译门禁和相关测试门禁；命中高风险改动但未找到可运行测试时直接失败
- 默认**不自动 commit**
- 默认要求**干净工作区**；若启动前工作区已脏，脚本会中止并要求先清理
- 若实际 diff 超出快路径范围（跨模块、实现文件 >3、路由/契约/核心工作流文件变更等），脚本会自动升级并生成 escalation 文件
- GDScript / Godot 小改仍可走快路径；若能自动探测到现有 headless/GUT 测试则会执行，否则只作为普通小改处理，不再一刀切升级
- 模型若要升级流程，必须单独输出一行 `UPGRADE_TO_AUTO_WORK: <reason>`
- 失败输出、模型输出和构建/测试摘要会落到运行时产物目录，便于排障

可选环境变量：

- `CLAUDE_MODEL_CODE`：指定快速开发阶段使用的模型
- `CLAUDE_MODEL`：未设置 `CLAUDE_MODEL_CODE` 时的兜底模型
- `FAST_AUTO_WORK_COMMIT=1`：开发和门禁通过后，自动创建本地 commit
- `FAST_AUTO_WORK_ALLOW_DIRTY=1`：显式允许在脏工作区中运行；仅用于排障，且会禁用自动 commit
- `FAST_AUTO_WORK_CLI_TIMEOUT=<seconds>`：限制单次 Claude 实现/修复调用的最长时间，默认 `1800`
- `FAST_AUTO_WORK_PREFLIGHT_TTL=<seconds>`：预检缓存 TTL，默认 `300`

---

## 产物

快流程的产物落在：

- `Docs/Version/{version_id}/{feature_name}/classification.txt`
- `Docs/Version/{version_id}/{feature_name}/fast-auto-work-log.md`
- `Docs/Version/{version_id}/{feature_name}/fast-auto-work-escalation.md`（仅失败或超出快路径范围时生成）
- `Docs/Version/{version_id}/{feature_name}/fast-auto-work-artifacts/`（实现输出、构建输出、测试输出）

这条命令的目标是**尽快把代码改出来并做最小但可靠的机械验证**，不是替代正式交付流程。
