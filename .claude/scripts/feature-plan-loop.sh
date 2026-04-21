#!/bin/bash
# feature-plan-loop.sh
# 自动迭代 Plan 创建 + Review 循环，每轮启动新 Claude 实例防止上下文污染
#
# 用法: bash .claude/scripts/feature-plan-loop.sh <version_id> <feature_name> [max_rounds]
# 示例: bash .claude/scripts/feature-plan-loop.sh v0.0.2-mvp login-system
#
# 前置条件:
#   - claude CLI 可用
#   - 从项目根目录运行

set -euo pipefail

# 共享 review 调度逻辑
source "$(dirname "$0")/review-helpers.sh"

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

run_parallel_plan_reviews() {
    local base_prompt="$1"
    local merged_file="$2"
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t codex-plan-review)

    local p1="${tmp_dir}/arch.md"
    local p2="${tmp_dir}/runtime.md"
    local p3="${tmp_dir}/test.md"

    codex_review_exec "${base_prompt}

【审查分片】
你只负责：架构、依赖方向、模块边界、数据流、可行性。" > "$p1" 2>&1 &
    local pid1=$!

    codex_review_exec "${base_prompt}

【审查分片】
你只负责：并发状态、容器生命周期、故障模式、性能瓶颈、资源限制。" > "$p2" 2>&1 &
    local pid2=$!

    codex_review_exec "${base_prompt}

【审查分片】
你只负责：测试策略、边界条件、验收完备性、Context Repairs 识别。" > "$p3" 2>&1 &
    local pid3=$!

    wait "$pid1" || true
    wait "$pid2" || true
    wait "$pid3" || true

    local merge_prompt
    merge_prompt="你是一名审查报告汇总者。请读取以下 3 份 Codex 分片审查结果，合并成一份正式的 plan review 报告并写入 ${merged_file}。

输入文件：
1. ${p1}
2. ${p2}
3. ${p3}

规则：
1. 去重，同类问题只保留一条，取更严重级别
2. 保留 Critical / Important / Nice to have 结构
3. 必须保留或生成 ## Context Repairs 段；如果无则写 - 无
4. 最后一行追加 <!-- counts: critical=X important=Y nice=Z -->
5. 直接写文件，不要提问"

    cli_call "$merge_prompt" --permission-mode bypassPermissions 2>&1 | tail -20 || true
    rm -rf "$tmp_dir"
}

run_single_plan_review() {
    local prompt="$1"
    local output_file="$2"
    codex_review_exec "$prompt" > "$output_file" 2>&1
}

generate_plan_review_input() {
    local output_file="${FEATURE_DIR}/review-input-plan.md"

    {
        echo "# Plan Review Input (auto-generated)"
        echo ""
        echo "## Feature Summary"
        if [ -f "${FEATURE_DIR}/feature.md" ]; then
            head -50 "${FEATURE_DIR}/feature.md"
        elif [ -f "${FEATURE_DIR}/feature.json" ]; then
            head -50 "${FEATURE_DIR}/feature.json"
        fi
        echo ""
        echo "## Plan Summary"
        if [ -f "$PLAN_FILE" ]; then
            head -80 "$PLAN_FILE"
        fi
        echo ""
        echo "## Plan Sub-files"
        if [ -d "${FEATURE_DIR}/plan" ]; then
            for f in "${FEATURE_DIR}"/plan/*.md; do
                [ -f "$f" ] || continue
                echo "### $(basename "$f")"
                head -30 "$f"
                echo ""
            done
        fi
    } > "$output_file"
    echo "$output_file"
}

apply_context_repairs() {
    local review_file="$1"

    # cheap gate: 使用共享函数检查是否有实质内容
    if ! context_repair_cheap_gate "$review_file"; then
        echo "  [Context Repair] 跳过（无实质 repair 内容）"
        return 0
    fi

    local repair_prompt
    repair_prompt="你是一名负责知识沉淀的工程师。请读取 ${review_file} 中的“## Context Repairs”段，并将需要长期固化的内容落实到最合适的仓库文档。

优先更新：
1. .ai/README.md
2. .ai/context/project.md
3. .ai/constitution.md
4. .claude/commands/auto-work.md
5. .claude/rules/context-repair.md

规则：
1. 项目事实与通用约束优先写入 .ai/
2. Claude 专属流程约束写入 .claude/
3. 不重复已有内容，必要时增强现有条目
4. 在 ${FEATURE_DIR}/context-repair-log.md 追加记录本次补充了什么"

    cli_call "$repair_prompt" --permission-mode bypassPermissions 2>&1 | tail -20 || true
}

# ══════════════════════════════════════
# 参数解析
# ══════════════════════════════════════

VERSION_ID="${1:?用法: $0 <version_id> <feature_name> [max_rounds]}"
FEATURE_NAME="${2:?用法: $0 <version_id> <feature_name> [max_rounds]}"
MAX_ROUNDS="${3:-20}"

FEATURE_DIR="Docs/Version/${VERSION_ID}/${FEATURE_NAME}"
PLAN_FILE="${FEATURE_DIR}/plan.md"
LOG_FILE="${FEATURE_DIR}/plan-iteration-log.md"
REVIEW_FILE="${FEATURE_DIR}/plan-review-report.md"

# 校验：优先 feature.md，兼容旧的 feature.json
if [ ! -f "${FEATURE_DIR}/feature.md" ] && [ ! -f "${FEATURE_DIR}/feature.json" ]; then
    echo "ERROR: ${FEATURE_DIR}/feature.md (or feature.json) not found"
    exit 1
fi

echo "══════════════════════════════════════"
echo "  Feature Plan 迭代循环"
echo "  功能: ${VERSION_ID}/${FEATURE_NAME}"
echo "  最大轮次: ${MAX_ROUNDS}"
echo "══════════════════════════════════════"

# ══════════════════════════════════════
# 初始化日志
# ══════════════════════════════════════

cat > "$LOG_FILE" << 'EOF'
# Plan 迭代日志

| 轮次 | 操作 | Critical | Important | Nice-to-have | 状态 |
|------|------|----------|-----------|--------------|------|
EOF

PREV_TOTAL=-1
CRITICAL=0
IMPORTANT=0
NICE=0
REASON=""

# 跨模型争论检测
PREV_CRITICAL_COUNT=-1
SAME_CRITICAL_STREAK=0
MAX_SAME_CRITICAL_STREAK=3

# ══════════════════════════════════════
# 主循环
# ══════════════════════════════════════

for ROUND in $(seq 1 "$MAX_ROUNDS"); do
    echo ""
    echo "══════════════════════════════════════"
    echo "  轮次 ${ROUND} / ${MAX_ROUNDS}"
    echo "══════════════════════════════════════"

    if [ $((ROUND % 2)) -eq 1 ]; then
        # ── 奇数轮: 创建/修复 Plan ──

        if [ "$ROUND" -eq 1 ]; then
            echo "[Round $ROUND] 创建 Plan..."

            PROMPT="读取 .claude/commands/feature/plan-creator.auto.md 中的工作流程并执行。

上下文最小化要求：
- 先判定本次 feature 命中的模块，再决定读取哪些文档和代码
- 默认只读 feature.md + .ai/constitution.md + 命中模块的架构/代码
- 未命中的模块（例如纯 Backend 任务中的 MCP / Engine / Godot）禁止预读
- 只有规则不明确时才补读 .claude/constitution.md 或专题 guide

参数（已解析，直接使用）：
- version_id: ${VERSION_ID}
- feature_name: ${FEATURE_NAME}
- FEATURE_DIR: ${FEATURE_DIR}"

        else
            echo "[Round $ROUND] 修复 Plan（基于上轮 Review）..."

            PROMPT="你的任务是根据 Codex（另一个 AI 模型）的 Review 报告修复 Plan。

【重要：跨模型协作规则】
Review 报告来自 Codex，它作为独立审查者检查了你的方案。
- 认真对待每一条发现，不要因为「这是另一个 AI 说的」而轻视
- 如果某条发现标注了 [RECURRING]，说明你在上轮修复中没有真正解决它，本轮必须换策略
- 修复后重新审视整体方案一致性，确保修复不引入新的矛盾

请读取以下文件：
1. ${REVIEW_FILE} — Codex 的 Review 报告
2. ${PLAN_FILE} — 当前 Plan
3. 如果 ${FEATURE_DIR}/plan/ 子目录存在，只读取与本轮修复问题命中模块对应的子文件

上下文最小化要求：
- 仅针对 Review 涉及的模块和问题补充上下文
- 未命中的模块文档、代码和子计划文件不要预读

修复规则：
- 逐个修复 Review 报告中的 Critical 和 Important 问题
- 在修改处添加 <!-- [迭代${ROUND}修复] 原因 --> 注释
- 只修复报告中列出的问题，不要添加额外功能或重构
- Nice-to-have 问题可以顺手修复，但不强制
- 修复后读取 .ai/constitution.md 和 .claude/constitution.md 做快速合宪性自检"
        fi

        mark_stage "plan-iteration" "" "$ROUND"
        cli_call "$PROMPT" --permission-mode bypassPermissions 2>&1 | tail -20
        echo "| $ROUND | 创建/修复 | - | - | - | done |" >> "$LOG_FILE"

    else
        # ── 偶数轮: Review Plan ──

        echo "[Round $ROUND] Review Plan (via Codex — 对抗审查)..."

        # 生成压缩审查输入
        REVIEW_INPUT=$(generate_plan_review_input)

        PREV_PLAN_CONTEXT=""
        if [ "$ROUND" -gt 2 ] && [ -f "$REVIEW_FILE" ]; then
            PREV_PLAN_CONTEXT="
【上轮 Review 遗留问题摘要】
上轮 Review (Round $((ROUND - 2))) 发现: Critical=${CRITICAL}, Important=${IMPORTANT}, Nice=${NICE}
请重点验证这些问题是否已被有效修复。如果发现同一问题反复出现，在报告中标注 [RECURRING] 标签。"
        fi

PROMPT="你是一名严苛的资深架构师，正在审查另一个 AI（Claude）编写的技术方案。你的目标是找出方案中的逻辑漏洞和设计盲区。

读取 .ai/context/reviewer-brief.md 作为审查规则。
读取 ${REVIEW_INPUT} 了解本轮审查输入（feature 摘要、plan 摘要）。

参数（已解析，直接使用）：
- version_id: ${VERSION_ID}
- feature_name: ${FEATURE_NAME}
- FEATURE_DIR: ${FEATURE_DIR}
${PREV_PLAN_CONTEXT}

自动化模式特殊规则：
1. 完成 Review 后，将完整的 Review 报告写入文件 ${REVIEW_FILE}（覆盖之前的报告）
2. 在报告文件的最后一行，必须追加以下格式的元数据（用于脚本自动解析，不要遗漏）：
   <!-- counts: critical=X important=Y nice=Z -->
   其中 X/Y/Z 替换为实际问题数量
3. 如果你判断某个问题属于“上下文缺口”，在报告中新增“## Context Repairs”段，列出建议更新的文件和应补充的规则
4. 跳过第四步（交互式修复），不要询问用户如何处理，直接结束"

        # 根据风险信号选择单路或并行 review
        PLAN_FILE_COUNT=$(find "${FEATURE_DIR}" -name "*.md" -not -name "*log*" -not -name "*report*" -not -name "*review-input*" 2>/dev/null | wc -l | tr -d ' ')
        REVIEW_MODE=$(should_use_parallel "${COMPLEXITY:-L}" "$PLAN_FILE_COUNT" "$PLAN_FILE_COUNT" "$CRITICAL" "$IMPORTANT")
        echo "  Review mode: ${REVIEW_MODE} (plan_files=${PLAN_FILE_COUNT})"

        if [ "$REVIEW_MODE" = "parallel" ]; then
            run_parallel_plan_reviews "$PROMPT" "$REVIEW_FILE"
        else
            run_single_plan_review "$PROMPT" "$REVIEW_FILE"
        fi

        # Context Repairs: 仅在发现 RECURRING 问题时触发
        if grep -q '\[RECURRING\]' "$REVIEW_FILE" 2>/dev/null; then
            apply_context_repairs "$REVIEW_FILE"
        else
            echo "  [Context Repair] 跳过（无 RECURRING 标记）"
        fi

        # 解析 Review 结果
        if [ -f "$REVIEW_FILE" ]; then
            COUNTS_LINE=$(grep -o 'counts: critical=[0-9]* important=[0-9]* nice=[0-9]*' "$REVIEW_FILE" 2>/dev/null | tail -1 || echo "")
            if [ -n "$COUNTS_LINE" ]; then
                CRITICAL=$(echo "$COUNTS_LINE" | sed 's/.*critical=\([0-9]*\).*/\1/')
                IMPORTANT=$(echo "$COUNTS_LINE" | sed 's/.*important=\([0-9]*\).*/\1/')
                NICE=$(echo "$COUNTS_LINE" | sed 's/.*nice=\([0-9]*\).*/\1/')
            else
                echo "WARNING: 无法解析 Review 报告中的 counts 元数据"
                echo "报告文件末尾内容:"
                tail -5 "$REVIEW_FILE"
                CRITICAL=999
                IMPORTANT=999
                NICE=0
            fi
        else
            echo "WARNING: Review 报告文件未生成: ${REVIEW_FILE}"
            CRITICAL=999
            IMPORTANT=999
            NICE=0
        fi

        CURRENT_TOTAL=$((CRITICAL + IMPORTANT))
        echo "| $ROUND | Review | $CRITICAL | $IMPORTANT | $NICE | done |" >> "$LOG_FILE"
        echo "Review 结果: Critical=$CRITICAL, Important=$IMPORTANT, Nice=$NICE"

        # ── 收敛判断 ──

        if [ "$CRITICAL" -eq 0 ] && [ "$IMPORTANT" -le 2 ]; then
            REASON="质量达标"
            echo "PASS: $REASON (Critical=0, Important<=2)"
            break
        fi

        if [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -eq "$PREV_TOTAL" ]; then
            REASON="未收敛(稳定不变)"
            echo "WARN: $REASON (问题总数未减少: $CURRENT_TOTAL)"
            break
        fi

        # 跨模型争论停机准则
        if [ "$PREV_CRITICAL_COUNT" -ge 0 ] && [ "$CRITICAL" -eq "$PREV_CRITICAL_COUNT" ] && [ "$CRITICAL" -gt 0 ]; then
            SAME_CRITICAL_STREAK=$((SAME_CRITICAL_STREAK + 1))
            echo "  争论检测: CRITICAL 连续 ${SAME_CRITICAL_STREAK}/${MAX_SAME_CRITICAL_STREAK} 轮不变 (=${CRITICAL})"
            if [ "$SAME_CRITICAL_STREAK" -ge "$MAX_SAME_CRITICAL_STREAK" ]; then
                REASON="跨模型争论停机(CRITICAL=${CRITICAL}连续${MAX_SAME_CRITICAL_STREAK}轮未收敛)"
                echo "STOP: $REASON — 需人工介入定义业务规则"
                break
            fi
        else
            SAME_CRITICAL_STREAK=0
        fi
        PREV_CRITICAL_COUNT=$CRITICAL

        PREV_TOTAL=$CURRENT_TOTAL
    fi
done

# 如果循环自然结束
if [ -z "$REASON" ]; then
    REASON="达到上限"
fi

# ══════════════════════════════════════
# 写入总结
# ══════════════════════════════════════

cat >> "$LOG_FILE" << EOF

## 总结
- 总轮次：$ROUND
- 终止原因：$REASON
- 最终状态：Critical=$CRITICAL, Important=$IMPORTANT, Nice-to-have=$NICE
EOF

echo ""
echo "══════════════════════════════════════"
echo "  Plan 迭代完成"
echo "══════════════════════════════════════"
echo "  轮次: $ROUND"
echo "  终止原因: $REASON"
echo "  最终质量: Critical=$CRITICAL, Important=$IMPORTANT"
echo "  Plan 文件: $PLAN_FILE"
echo "  迭代日志: $LOG_FILE"
echo "══════════════════════════════════════"

if [ "$CRITICAL" -gt 0 ]; then
    echo "EXIT 2: Plan 仍有 ${CRITICAL} 个 Critical 问题未收敛"
    exit 2
fi

if [ "$IMPORTANT" -gt 2 ]; then
    echo "EXIT 3: Plan 仍有 ${IMPORTANT} 个 Important 问题，未达到收敛阈值"
    exit 3
fi
