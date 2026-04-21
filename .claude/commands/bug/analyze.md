---
description: 分析 auto-work 产出中遗漏/缺陷的根因，定位流程断点并输出修复方案+工作流优化建议
argument-hint: <version_id> <feature_name> <bug描述>
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则：**

参数格式：`<version_id> <feature_name> <bug描述（剩余部分）>`

1. **第一个词**：`version_id`（版本号）
2. **第二个词**：`feature_name`（功能名称，对应 `Docs/Version/{version_id}/{feature_name}/` 目录）
3. **剩余部分**：bug 描述

**验证：**
- 如果参数不足 3 部分，使用 AskUserQuestion 让用户补充
- 确认 `Docs/Version/{version_id}/{feature_name}/` 目录存在

解析后变量：
- `VERSION_ID`、`FEATURE_NAME`、`FEATURE_DIR`、`BUG_DESC`

---

## 分析流程

这是一个**单次分析任务**，在当前会话中完成。

### 第一步：收集证据（全量阅读 auto-work 产出物）

按顺序读取 `{FEATURE_DIR}/` 下的所有产出文件：

1. **`idea.md`** — 原始需求输入
2. **`feature.md` / `feature.json`** — 结构化需求文档
3. **`plan.md` / `plan.json`** — 技术方案
4. **`plan/`** 子目录下的所有文件
5. **`tasks/README.md`** + 所有 `tasks/task-*.md` — 任务拆分
6. **`auto-work-log.md`** — 全流程日志
7. **`plan-iteration-log.md`** + **`plan-review-report.md`** — Plan 迭代过程
8. **`develop-iteration-log.md`** + **`develop-review-report.md`** — 开发迭代过程
9. **`develop-log.md`** — 开发详细记录

> 文件可能不全，读取时跳过不存在的文件。

### 第二步：定位 bug 在代码中的位置

根据 bug 描述，搜索相关代码：
- 使用 Grep/Glob 搜索相关函数名、配置键、路由路径
- 阅读涉及的代码文件，确认 bug 的具体表现
- 确定 bug 影响的范围（哪些文件、哪些流程）

### 第三步：全链路断点分析

逐层对比，定位 bug 是在 auto-work 哪个环节丢失或出错的：

| 检查项 | 问题 |
|--------|------|
| **idea → feature** | feature 文档是否完整覆盖了 idea 中的需求点？ |
| **feature → plan** | plan 是否为这个需求点设计了技术方案？ |
| **plan → tasks** | 任务拆分是否包含了实现这个功能的任务？ |
| **tasks → code** | 对应任务的代码是否被正确实现？ |
| **review** | review 报告是否发现了这个问题？发现了为什么没修好？ |
| **收敛** | 迭代是否因为"稳定不变"或"达到上限"而终止？ |

### 第四步：归因分类

| 归因类别 | 说明 |
|----------|------|
| **需求遗漏** | feature 文档没有覆盖 idea 中的需求点 |
| **方案遗漏** | plan 没有为 feature 中的需求设计方案 |
| **任务遗漏** | 任务拆分时遗漏了 plan 中的模块 |
| **实现缺陷** | 任务正确拆分但代码有 bug |
| **Review 盲区** | Review 没有发现已存在的问题 |
| **收敛失败** | Review 发现了但修不好，迭代终止 |
| **编译驱动偏移** | 为了通过编译而删除/注释了功能代码 |
| **上下文丢失** | 跨进程传递时关键信息丢失 |

### 第五步：输出分析报告

写入 `Docs/Bug/{VERSION_ID}/{FEATURE_NAME}/` 目录（不存在则创建）。

报告格式：

```markdown
# Bug 分析：{bug 简短标题}

## Bug 描述
## 代码定位
- **涉及文件**、**当前行为**、**预期行为**

## 全链路断点分析
### idea → feature / feature → plan / plan → tasks / tasks → 代码 / Review 检出

## 归因结论
**主要原因**：{类别} — 解释
**根因链**：完整因果链

## 修复方案
### 代码修复
### 工作流优化建议
```

### 第六步：追加到版本 bug 清单

检查 `Docs/Bug/{VERSION_ID}/{FEATURE_NAME}.md` 是否存在，追加 bug 条目。

---

## 注意事项

- 这是**分析任务**，不修改代码
- 分析必须基于实际文件内容，不要推测
- 对比时要引用原文
- 工作流优化建议要具体可执行
