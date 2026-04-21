---
description: 自动迭代创建实现方案+Review，直到收敛
argument-hint: [version_id feature_name]
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则（按优先级尝试）：**

1. **自动匹配目录**：用 Glob 工具搜索 `Docs/Version/*/` 下的子目录
2. **斜杠分隔**：如果参数包含 `/`，按 `/` 拆分
3. **验证路径**：确认 `Docs/Version/{version_id}/{feature_name}/feature.md`（或 `feature.json`）存在
4. **无法自动匹配时**：使用 AskUserQuestion 向用户确认

解析完成后，设定以下变量：
- `VERSION_ID` = 版本 ID
- `FEATURE_NAME` = 功能名称
- `FEATURE_DIR` = `Docs/Version/{version_id}/{feature_name}`

---

## 执行

参数解析完成后，使用 Bash 工具执行以下命令启动迭代循环：

```bash
bash .claude/scripts/feature-plan-loop.sh {VERSION_ID} {FEATURE_NAME}
```

脚本会自动完成以下流程，**每轮启动新的 Claude 实例**避免上下文污染：

1. **奇数轮**：创建/修复 Plan（第一轮调用 feature/plan-creator 完整流程，后续轮次根据 Review 报告针对性修复）
2. **偶数轮**：Review Plan（调用 feature/plan-review 流程，报告写入 `{FEATURE_DIR}/plan-review-report.md`）
3. **收敛后**停止循环，输出总结

**收敛条件**（满足任一即停止）：
- 质量达标：Critical = 0 且 Important ≤ 2
- 稳定不变：连续两轮 Review 的问题总数相同
- 达到上限：已执行 20 轮

---

## 注意事项

- 脚本需要 `claude` CLI 可用
- 每个 Claude 实例会自动加载项目的 CLAUDE.md 和 constitution.md
- 循环中不会向用户提问，所有需求澄清通过自主决策解决
- 迭代日志：`{FEATURE_DIR}/plan-iteration-log.md`
- Review 报告：`{FEATURE_DIR}/plan-review-report.md`
