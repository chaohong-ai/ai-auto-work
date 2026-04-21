# Context Repair Rule

适用场景：auto-work / manual-work / bug-fix / feature-plan / feature-develop review

## 目标

当 AI 在同类问题上反复犯错时，不要只修当前代码，还要修“导致错误重复发生的上下文”。

## 判断标准

以下情况应判定为“上下文缺口”而不是单次实现失误：

- 同类遗漏连续出现两次以上
- 明明仓库里已有成熟模式，但执行者仍然重复偏离
- 需求边界、架构约束或验收标准没有被稳定加载
- review 报告中的问题更像“项目规则没被记住”，而不是“代码不会写”

## 修复顺序

1. 项目事实、术语、架构、工程约束：更新 `.ai/`
2. Claude 专属流程、技能、命令约束：更新 `.claude/commands/`、`.claude/skills/`、`.claude/rules/`
3. 然后再继续代码修复或重新验收

## 最小落点原则

- 能写进 `.ai/context/project.md` 的，不写成零散说明
- 能写进 `.ai/constitution.md` 的，不只留在 review 报告
- 能写进具体 workflow command 的，不泛化进宪法
- 能写成 skill/rule 的重复操作，不在每次 prompt 里重新解释

## 审查输出要求

当发现上下文缺口时，review 报告必须说明：

1. 缺的是什么上下文
2. 为什么这是系统性问题
3. 应该更新哪个文件
4. 更新后 Claude 需要重新执行哪个阶段

