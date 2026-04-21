---
description: 循环调用调研+Review直至收敛（最多10轮）
argument-hint: <调研主题>
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则：**

1. **参数不为空时**，将参数作为 `topic`：
   - 尝试确认 `Docs/Research/{topic}/` 目录是否存在（不存在也可以，脚本会自动创建）
2. **参数为空时**：
   - 用 Glob 列出 `Docs/Research/*/idea.md`，展示已有主题
   - 使用 AskUserQuestion 让用户选择已有主题或输入新主题

解析完成后，设定 `TOPIC` 变量。

---

## 执行

参数解析完成后，使用 Bash 工具执行以下命令启动迭代循环：

```bash
bash .claude/scripts/research-loop.sh {TOPIC}
```

脚本会自动完成以下流程，**每轮启动新的 `claude -p` 实例**避免上下文污染：

1. **奇数轮**：执行调研（第一轮调用 research/do 完整流程，后续轮次根据 Review 报告针对性修复）
2. **偶数轮**：Review 调研报告（调用 research/review 流程，报告写入 `research-review-report.md`）
3. **收敛后**停止循环，输出总结

**收敛条件**（满足任一即停止）：
- 质量达标：Critical = 0 且 Important ≤ 1
- 可靠度达标：决策可靠度 ≥ 4 星
- 稳定不变：连续两轮 Review 的问题总数相同
- 达到上限：已执行 10 轮

---

## 注意事项

- 脚本需要 `claude` CLI 可用
- 每个 Claude 实例会自动加载项目的 CLAUDE.md 和 constitution.md
- 循环中不会向用户提问，所有需求澄清通过 idea.md 或自主决策解决
- 迭代日志：`Docs/Research/{topic}/research-iteration-log.md`
- Review 报告：`Docs/Research/{topic}/research-review-report.md`
