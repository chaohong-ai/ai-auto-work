#!/bin/bash
# research-loop.sh
# 自动迭代调研 + Review 循环，每轮启动新 Claude 实例防止上下文污染
#
# 用法: bash .claude/scripts/research-loop.sh <topic> [max_rounds]
# 示例: bash .claude/scripts/research-loop.sh ecs-architecture
#
# 前置条件:
#   - claude CLI 可用
#   - 从项目根目录运行

set -euo pipefail

# CLI trace：统一 cli_call / codex_review_exec 定义（含 JSONL trace 落盘）
source "$(dirname "$0")/cli-trace-helpers.sh"

# 模型选择：继承环境变量 CLAUDE_MODEL
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
CLAUDE_MODEL_FLAG=""
if [ -n "$CLAUDE_MODEL" ]; then
    CLAUDE_MODEL_FLAG="--model $CLAUDE_MODEL"
fi

# Review 使用 Codex CLI：继承环境变量 CODEX_MODEL
CODEX_MODEL="${CODEX_MODEL:-}"
CODEX_MODEL_FLAG=""
if [ -n "$CODEX_MODEL" ]; then
    CODEX_MODEL_FLAG="-m $CODEX_MODEL"
fi

# codex_review_exec 由 cli-trace-helpers.sh 提供

# 运行时前置检查（独立调用时生效；从 auto-work-loop 调用时已通过）
preflight_check --require-codex || exit 1

# 加载 contract 文件并替换模板变量 {VAR} → 当前 shell 变量值
load_contract() {
    local file="$1"
    sed -e "s|{RESEARCH_DIR}|${RESEARCH_DIR:-}|g" \
        -e "s|{RESULT_FILE}|${RESULT_FILE:-}|g" \
        -e "s|{REVIEW_FILE}|${REVIEW_FILE:-}|g" \
        -e "s|{TOPIC}|${TOPIC:-}|g" \
        "$file"
}

DEFERRED_REPAIRS_FILE=$(mktemp 2>/dev/null || mktemp -t deferred-repairs)

defer_context_repairs() {
    local review_file="$1"
    if [ ! -f "$review_file" ]; then
        return 0
    fi
    if ! grep -q "^## Context Repairs" "$review_file" 2>/dev/null; then
        return 0
    fi
    echo "--- source: ${review_file} ---" >> "$DEFERRED_REPAIRS_FILE"
    sed -n '/^## Context Repairs/,/^## [^C]/p' "$review_file" | head -n -1 >> "$DEFERRED_REPAIRS_FILE"
    echo "" >> "$DEFERRED_REPAIRS_FILE"
}

flush_deferred_repairs() {
    if [ ! -s "$DEFERRED_REPAIRS_FILE" ]; then
        rm -f "$DEFERRED_REPAIRS_FILE"
        return 0
    fi

    echo "[Context Repair] 批量落盘收集到的上下文修复建议..."

    local repair_content
    repair_content=$(cat "$DEFERRED_REPAIRS_FILE")

    local repair_prompt
    repair_prompt="你是一名负责知识沉淀的工程师。以下是调研迭代中收集到的 Context Repairs 建议，请去重合并后落实到仓库文档。

收集到的建议：
${repair_content}

优先更新：
1. .ai/context/project.md
2. .ai/constitution.md
3. .claude/rules/ 下相关文件

规则：
1. 去重合并同类建议
2. 项目事实与通用约束写入 .ai/
3. Claude 专属流程约束写入 .claude/
4. 在 Docs/Research/${TOPIC}/context-repair-log.md 追加记录
5. 不向用户提问，直接完成"

    cli_call "$repair_prompt" --permission-mode bypassPermissions 2>&1 | tail -20 || true
    rm -f "$DEFERRED_REPAIRS_FILE"
}

# ══════════════════════════════════════
# 参数解析
# ══════════════════════════════════════

TOPIC="${1:?用法: $0 <topic> [max_rounds]}"
MAX_ROUNDS="${2:-10}"

RESEARCH_DIR="Docs/Research/${TOPIC}"
RESULT_FILE="${RESEARCH_DIR}/research-result.md"
REVIEW_FILE="${RESEARCH_DIR}/research-review-report.md"
LOG_FILE="${RESEARCH_DIR}/research-iteration-log.md"

# 确保目录存在
mkdir -p "$RESEARCH_DIR"

echo "══════════════════════════════════════"
echo "  Research 迭代循环"
echo "  主题: ${TOPIC}"
echo "  最大轮次: ${MAX_ROUNDS}"
echo "══════════════════════════════════════"

# ══════════════════════════════════════
# 初始化日志
# ══════════════════════════════════════

cat > "$LOG_FILE" << 'EOF'
# 调研迭代日志

| 轮次 | 操作 | Critical | Important | Nice-to-have | 可靠度 | 状态 |
|------|------|----------|-----------|--------------|--------|------|
EOF

PREV_TOTAL=-1
CRITICAL=0
IMPORTANT=0
NICE=0
RELIABILITY=0
REASON=""

# ══════════════════════════════════════
# 主循环
# ══════════════════════════════════════

for ROUND in $(seq 1 "$MAX_ROUNDS"); do
    echo ""
    echo "══════════════════════════════════════"
    echo "  轮次 ${ROUND} / ${MAX_ROUNDS}"
    echo "══════════════════════════════════════"

    if [ $((ROUND % 2)) -eq 1 ]; then
        # ── 奇数轮: 调研 ──

        if [ "$ROUND" -eq 1 ]; then
            echo "[Round $ROUND] 执行调研..."

            PROMPT="你是一名资深技术架构师。对以下主题进行技术调研，输出调研报告。

【必读】
$(load_contract .claude/contracts/research-do/inputs.md)

【调研主题】
topic: ${TOPIC}

【按需展开】
$(load_contract .claude/contracts/research-do/expand.md)

【输出】
$(load_contract .claude/contracts/research-do/outputs.md)

【硬性 gate】
$(load_contract .claude/contracts/research-do/gates.md)

自动化模式规则：
1. 如果 idea.md 存在则以其为需求，否则以 topic 为主题，调研深度'深入对比'
2. 不向用户提问，不等待讨论
3. 完成后直接结束"

        else
            echo "[Round $ROUND] 修复调研报告（基于上轮 Review）..."

            PROMPT="你的任务是根据 Codex（另一个 AI 模型）的 Review 报告修复调研报告。

【重要：跨模型协作规则】
Review 报告来自 Codex，它作为独立审查者检查了你的调研报告。
- 认真对待每一条发现，不要因为"这是另一个 AI 说的"而轻视
- 如果某条发现标注了 [RECURRING]，说明你在上轮修复中没有真正补充到位，本轮必须换策略
- 修复后确保报告整体逻辑自洽，新增内容与原内容不矛盾

请读取以下文件：
1. ${REVIEW_FILE} — Codex 的 Review 报告
2. ${RESULT_FILE} — 当前调研报告
3. 如果 ${RESEARCH_DIR}/research-result/ 子目录存在，也读取其中的所有子文件
4. 如果 ${RESEARCH_DIR}/idea.md 存在，读取以了解原始需求

修复规则：
- 逐个修复 Review 报告中的 Critical 和 Important 问题
- 对于需要补充信息的问题，使用 WebSearch/WebFetch 搜索后补充
- 在修改处添加 <!-- [迭代${ROUND}修复] 原因 --> 注释
- 只修复报告中列出的问题，不要添加额外内容
- Nice-to-have 问题可以顺手修复，但不强制"
        fi

        mark_stage "research-iteration" "" "$ROUND"
        cli_call "$PROMPT" --permission-mode bypassPermissions 2>&1 | tail -20
        echo "| $ROUND | 调研/修复 | - | - | - | - | done |" >> "$LOG_FILE"

    else
        # ── 偶数轮: Review 调研报告 ──

        echo "[Round $ROUND] Review 调研报告 (via Codex — 对抗审查)..."

        PREV_RESEARCH_CONTEXT=""
        if [ "$ROUND" -gt 2 ] && [ -f "$REVIEW_FILE" ]; then
            PREV_RESEARCH_CONTEXT="
【上轮 Review 遗留问题摘要】
上轮 Review (Round $((ROUND - 2))) 发现: Critical=${CRITICAL}, Important=${IMPORTANT}, Nice=${NICE}, 可靠度=${RELIABILITY}/5
请重点验证这些问题是否已被有效补充。如果发现同一问题反复出现，在报告中标注 [RECURRING] 标签。"
        fi

        PROMPT="你是一名严苛的技术调研审查专家，正在审查另一个 AI（Claude）编写的调研报告。你的目标是找出调研中的信息盲区和逻辑漏洞。

【必读】
$(load_contract .claude/contracts/research-review/inputs.md)
${PREV_RESEARCH_CONTEXT}

【按需展开】
$(load_contract .claude/contracts/research-review/expand.md)

$(load_contract .claude/contracts/research-review/gates.md)

【输出】
$(load_contract .claude/contracts/research-review/outputs.md)
- 不要询问用户，直接结束"

        codex_review_exec "$PROMPT" 2>&1 | tail -20
        defer_context_repairs "$REVIEW_FILE"

        # 分级落盘：Critical/Recurring 的上下文缺口立即修复，确保下轮修复可读到新规则
        if [ -f "$REVIEW_FILE" ]; then
            HAS_RECURRING=$(grep -c '\[RECURRING\]' "$REVIEW_FILE" 2>/dev/null || echo "0")
        else
            HAS_RECURRING=0
        fi

        # 解析 Review 结果
        if [ -f "$REVIEW_FILE" ]; then
            COUNTS_LINE=$(grep -o 'counts: critical=[0-9]* important=[0-9]* nice=[0-9]* reliability=[0-9]*' "$REVIEW_FILE" 2>/dev/null | tail -1 || echo "")
            if [ -n "$COUNTS_LINE" ]; then
                CRITICAL=$(echo "$COUNTS_LINE" | sed 's/.*critical=\([0-9]*\).*/\1/')
                IMPORTANT=$(echo "$COUNTS_LINE" | sed 's/.*important=\([0-9]*\).*/\1/')
                NICE=$(echo "$COUNTS_LINE" | sed 's/.*nice=\([0-9]*\).*/\1/')
                RELIABILITY=$(echo "$COUNTS_LINE" | sed 's/.*reliability=\([0-9]*\).*/\1/')
            else
                echo "WARNING: 无法解析 Review 报告中的 counts 元数据"
                echo "报告文件末尾内容:"
                tail -5 "$REVIEW_FILE"
                CRITICAL=999
                IMPORTANT=999
                NICE=0
                RELIABILITY=0
            fi
        else
            echo "WARNING: Review 报告文件未生成: ${REVIEW_FILE}"
            CRITICAL=999
            IMPORTANT=999
            NICE=0
            RELIABILITY=0
        fi

        CURRENT_TOTAL=$((CRITICAL + IMPORTANT))
        echo "| $ROUND | Review | $CRITICAL | $IMPORTANT | $NICE | $RELIABILITY | done |" >> "$LOG_FILE"
        echo "Review 结果: Critical=$CRITICAL, Important=$IMPORTANT, Nice=$NICE, 可靠度=$RELIABILITY/5"

        # ── 收敛判断 ──

        # 条件1: 质量达标
        if [ "$CRITICAL" -eq 0 ] && [ "$IMPORTANT" -le 1 ]; then
            REASON="质量达标"
            echo "PASS: $REASON (Critical=0, Important<=1)"
            break
        fi

        # 条件2: 可靠度达标
        if [ "$RELIABILITY" -ge 4 ]; then
            REASON="可靠度达标"
            echo "PASS: $REASON (可靠度=${RELIABILITY}/5 >= 4)"
            break
        fi

        # 条件3: 稳定不变（陷入循环）
        if [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -eq "$PREV_TOTAL" ]; then
            REASON="稳定不变"
            echo "WARN: $REASON (问题总数未减少: $CURRENT_TOTAL)"
            break
        fi

        # 分级落盘决策（在解析 counts 之后执行）
        if [ "$CRITICAL" -gt 0 ] || [ "$HAS_RECURRING" -gt 0 ]; then
            echo "[Context Repair] Critical=${CRITICAL}/RECURRING=${HAS_RECURRING}，立即落盘上下文修复..."
            flush_deferred_repairs
        fi

        PREV_TOTAL=$CURRENT_TOTAL
    fi
done

# 如果循环自然结束
if [ -z "$REASON" ]; then
    REASON="达到上限"
fi

# ── 批量落盘上下文修复 ──
flush_deferred_repairs

# ══════════════════════════════════════
# 写入总结
# ══════════════════════════════════════

cat >> "$LOG_FILE" << EOF

## 总结
- 总轮次：$ROUND
- 终止原因：$REASON
- 最终状态：Critical=$CRITICAL, Important=$IMPORTANT, Nice-to-have=$NICE
- 决策可靠度：$RELIABILITY/5
EOF

echo ""
echo "══════════════════════════════════════"
echo "  调研迭代完成"
echo "══════════════════════════════════════"
echo "  轮次: $ROUND"
echo "  终止原因: $REASON"
echo "  最终质量: Critical=$CRITICAL, Important=$IMPORTANT"
echo "  决策可靠度: $RELIABILITY/5"
echo "  调研报告: $RESULT_FILE"
echo "  迭代日志: $LOG_FILE"
echo "══════════════════════════════════════"
