#!/bin/bash
# feature-develop-loop.sh
# 原子化开发迭代循环：每轮变更最小可独立评估，测试作为机械判定标准
#
# 核心机制（源自"原子化开发环境"思想）：
#   1. Git Checkpoint — 每次修复前打快照，测试变差则回滚
#   2. Test-as-Baseline — 编译+测试是主门禁，AI review 是辅助
#   3. Fail-Fast — 编译不过不进 review，省掉无意义的 AI 轮次
#   4. Single-Fix — 每轮只修一类问题，变更可归因
#   5. Keep/Discard — 修复后测试指标不退步才保留，否则丢弃
#
# 用法: bash .claude/scripts/feature-develop-loop.sh <version_id> <feature_name> [max_rounds]
#        bash .claude/scripts/feature-develop-loop.sh <version_id> <feature_name> --task <task_file> [max_rounds]
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

run_parallel_develop_reviews() {
    local base_prompt="$1"
    local merged_file="$2"
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t codex-develop-review)

    local p1="${tmp_dir}/arch.md"
    local p2="${tmp_dir}/runtime.md"
    local p3="${tmp_dir}/test.md"

    codex_review_exec "${base_prompt}

【审查分片】
你只负责：架构实现偏差、依赖方向、接口一致性、数据流、宪法违规。" > "$p1" 2>&1 &
    local pid1=$!

    codex_review_exec "${base_prompt}

【审查分片】
你只负责：并发竞态、资源泄漏、异常路径、超时、容器/进程生命周期、安全问题。" > "$p2" 2>&1 &
    local pid2=$!

    codex_review_exec "${base_prompt}

【审查分片】
你只负责：测试覆盖、边界条件、回归风险、Context Repairs 识别。" > "$p3" 2>&1 &
    local pid3=$!

    wait "$pid1" || true
    wait "$pid2" || true
    wait "$pid3" || true

    local merge_prompt
    merge_prompt="你是一名审查报告汇总者。请读取以下 3 份 Codex 分片审查结果，合并成一份正式的 develop review 报告并写入 ${merged_file}。

输入文件：
1. ${p1}
2. ${p2}
3. ${p3}

规则：
1. 去重，同类问题只保留一条，取更严重级别
2. 保留 Critical / High / Medium 结构
3. 必须保留或生成 Context Repairs 段；如果无则写 - 无
4. 最后一行追加 <!-- counts: critical=X high=Y medium=Z -->
5. 直接写文件，不要提问"

    cli_call "$merge_prompt" --permission-mode bypassPermissions 2>&1 | tail -20 || true
    rm -rf "$tmp_dir"
}

run_single_develop_review() {
    local prompt="$1"
    local output_file="$2"
    codex_review_exec "$prompt" > "$output_file" 2>&1
}

generate_develop_review_input() {
    local output_file="${FEATURE_DIR}/review-input-develop.md"
    local round="${1:-2}"
    local base_ref="${2:-HEAD~1}"
    local prev_checkpoint

    cat /dev/null > "$output_file"

    echo "# Develop Review Input - round ${round}" >> "$output_file"
    echo "" >> "$output_file"

    if [ "$round" -gt 2 ]; then
        # Round 4+: 增量模式
        echo "## Mode: Incremental" >> "$output_file"
        echo "" >> "$output_file"
        echo "## Unresolved Issues from Previous Review" >> "$output_file"
        if [ -f "$REVIEW_FILE" ]; then
            grep -iE '^\#\#\# \[(Critical|High|Medium)\]|\[RECURRING\]' "$REVIEW_FILE" 2>/dev/null | head -30 >> "$output_file" || echo "- None" >> "$output_file"
        else
            echo "- None" >> "$output_file"
        fi
        echo "" >> "$output_file"
        echo "## Git Diff --stat" >> "$output_file"
        # 使用最后一次 KEEP 的稳定基线，而非轮次推导的 tag
        # 注意：代码修复在工作区（未 commit），用 `git diff <tag>`（含工作区）
        # 而不是 `git diff <tag>..HEAD`（仅已 commit 变更）
        if [ -n "${LAST_KEEP_TAG:-}" ] && git rev-parse "$LAST_KEEP_TAG" >/dev/null 2>&1; then
            echo "Baseline: ${LAST_KEEP_TAG} (working-tree diff)" >> "$output_file"
            git diff --stat "$LAST_KEEP_TAG" 2>/dev/null | grep -v "^$" >> "$output_file" || echo "no changes" >> "$output_file"
            echo "" >> "$output_file"
            echo "## Changed Files" >> "$output_file"
            git diff "$LAST_KEEP_TAG" 2>/dev/null | head -200 >> "$output_file" || true
        else
            echo "Baseline: ${base_ref} (fallback, working-tree diff)" >> "$output_file"
            git diff --stat "$base_ref" 2>/dev/null | grep -v "^$" >> "$output_file" || echo "no diff available" >> "$output_file"
            echo "" >> "$output_file"
            echo "## Changed Files" >> "$output_file"
            git diff "$base_ref" 2>/dev/null | head -200 >> "$output_file" || true
        fi
    else
        # Round 2: 首次 review，全量上下文
        echo "## Mode: Full" >> "$output_file"
        echo "" >> "$output_file"
        echo "## Task Scope" >> "$output_file"
        if [ -n "${TASK_FILE:-}" ] && [ -f "$TASK_FILE" ]; then
            echo "Task: $(basename "$TASK_FILE")" >> "$output_file"
            head -20 "$TASK_FILE" >> "$output_file"
        else
            echo "Full feature scope" >> "$output_file"
        fi
        echo "" >> "$output_file"
        echo "## Git Diff --stat" >> "$output_file"
        # 注意：用 `git diff <ref>`（含工作区）而非 `git diff <ref>..HEAD`（仅已 commit 变更）
        # 当前任务的修复在工作区（未 commit），必须包含工作区才能让 reviewer 看到本轮变更
        git diff --stat "$base_ref" 2>/dev/null | grep -v "^$" >> "$output_file" || echo "no diff available" >> "$output_file"
        echo "" >> "$output_file"
        echo "## Changed Files" >> "$output_file"
        git diff "$base_ref" 2>/dev/null | head -300 >> "$output_file" || true
    fi

    echo "" >> "$output_file"
    echo "## Test Results Summary" >> "$output_file"
    echo "Compile: ${CURR_COMPILE:-unknown} | Tests: ${CURR_TEST_PASS:-0}/${CURR_TEST_TOTAL:-0} passed" >> "$output_file"

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

VERSION_ID="${1:?用法: $0 <version_id> <feature_name> [--task <task_file>] [max_rounds]}"
FEATURE_NAME="${2:?用法: $0 <version_id> <feature_name> [--task <task_file>] [max_rounds]}"

MAX_ROUNDS=20
TASK_FILE=""

shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --task)
            TASK_FILE="${2:?--task 需要指定任务文件路径}"
            shift 2
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                MAX_ROUNDS="$1"
            fi
            shift
            ;;
    esac
done

FEATURE_DIR="Docs/Version/${VERSION_ID}/${FEATURE_NAME}"
PLAN_FILE="${FEATURE_DIR}/plan.md"

if [ ! -f "$PLAN_FILE" ]; then
    if [ -f "${FEATURE_DIR}/plan.json" ]; then
        PLAN_FILE="${FEATURE_DIR}/plan.json"
    else
        echo "ERROR: ${PLAN_FILE} not found (先运行 feature-plan 生成 plan)"
        exit 1
    fi
fi

# 根据是否有 task 文件区分日志文件名
if [ -n "$TASK_FILE" ]; then
    TASK_BASENAME=$(basename "$TASK_FILE" .md)
    LOG_FILE="${FEATURE_DIR}/develop-iteration-log-${TASK_BASENAME}.md"
    REVIEW_FILE="${FEATURE_DIR}/develop-review-report-${TASK_BASENAME}.md"
else
    TASK_BASENAME=""
    LOG_FILE="${FEATURE_DIR}/develop-iteration-log.md"
    REVIEW_FILE="${FEATURE_DIR}/develop-review-report.md"
fi

if [ -n "$TASK_FILE" ] && [ ! -f "$TASK_FILE" ]; then
    echo "ERROR: 任务文件不存在: ${TASK_FILE}"
    exit 1
fi

# 构建任务约束提示
TASK_SCOPE_PROMPT=""
if [ -n "$TASK_FILE" ]; then
    TASK_CONTENT=$(cat "$TASK_FILE")
    TASK_SCOPE_PROMPT="
【重要：本次只实现以下任务的范围】
任务文件：${TASK_FILE}
任务内容：
${TASK_CONTENT}

你只需要实现上述任务中列出的文件和功能，不要实现 plan 中其他任务的内容。
完成后确保代码能独立编译通过（不会有悬空引用或缺失依赖）。"
fi

echo "══════════════════════════════════════"
echo "  Feature Develop 原子化迭代循环"
echo "  功能: ${VERSION_ID}/${FEATURE_NAME}"
if [ -n "$TASK_FILE" ]; then
    echo "  任务: $(basename "$TASK_FILE")"
fi
echo "  最大轮次: ${MAX_ROUNDS}"
echo "  机制: checkpoint → fix → test → keep/discard"
echo "══════════════════════════════════════"

# ══════════════════════════════════════
# 工具函数
# ══════════════════════════════════════

# 生成唯一的 checkpoint tag 名
checkpoint_tag() {
    local prefix="atomic-dev"
    [ -n "$TASK_BASENAME" ] && prefix="atomic-${TASK_BASENAME}"
    echo "${prefix}-r${1}"
}

# 创建 git checkpoint（轻量 tag）
create_checkpoint() {
    local tag=$(checkpoint_tag "$1")
    if ! git tag -f "$tag" HEAD 2>/dev/null; then
        echo "WARNING: 无法创建 checkpoint tag ${tag}" >&2
    fi
    echo "$tag"
}

# 回滚到 checkpoint（只还原本轮变更的文件，不动其他未跟踪文件）
discard_to_checkpoint() {
    local tag="$1"
    echo "DISCARD: 测试指标退步，回滚到 ${tag}"

    # 只回滚 tag..HEAD 之间有变更的文件，不用 git clean -fd / git reset --hard
    local changed_files
    changed_files=$(git diff --name-only "$tag" HEAD 2>/dev/null || true)
    local new_files
    new_files=$(git diff --diff-filter=A --name-only "$tag" HEAD 2>/dev/null || true)

    if [ -n "$changed_files" ]; then
        # 还原已跟踪文件到 tag 的状态
        echo "$changed_files" | xargs -r git checkout "$tag" -- 2>/dev/null || true
    fi
    if [ -n "$new_files" ]; then
        # 删除本轮新增的文件（tag 中不存在的）
        echo "$new_files" | xargs -r rm -f 2>/dev/null || true
    fi

    # 重置 index 到 tag（不动工作区其他文件）
    git reset "$tag" 2>/dev/null || true

    # 验证关键文件已回滚
    local remaining
    remaining=$(git diff --name-only "$tag" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$remaining" -gt 0 ]; then
        echo "WARNING: 回滚后仍有 ${remaining} 个文件与 ${tag} 不同"
    fi
}

# 清理所有 checkpoint tags（循环结束后）
cleanup_checkpoints() {
    git tag -l "atomic-*" 2>/dev/null | while read tag; do
        git tag -d "$tag" 2>/dev/null || true
    done
}

# 推导受影响模块（从 task files: 字段 + git diff）
# 输出空格分隔的模块列表：Backend MCP Frontend Tools
_detect_affected_modules() {
    local modules=""
    # 从 task 文件的 files: 字段提取
    if [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
        local task_files
        task_files=$(sed -n '/^files:/,/^[^[:space:]-]/p' "$TASK_FILE" | grep '^\s*-' | sed 's/^\s*-\s*//' | tr -d '"' || true)
        if echo "$task_files" | grep -q "^Backend/"; then modules="$modules Backend"; fi
        if echo "$task_files" | grep -q "^MCP/"; then modules="$modules MCP"; fi
        if echo "$task_files" | grep -q "^Frontend/"; then modules="$modules Frontend"; fi
        if echo "$task_files" | grep -q "^Tools/"; then modules="$modules Tools"; fi
    fi
    # 补充：git diff 实际变更（可能超出 task 声明）
    local diff_files
    diff_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only 2>/dev/null || true)
    if [ -n "$diff_files" ]; then
        if echo "$diff_files" | grep -q "^Backend/" && [[ ! "$modules" == *Backend* ]]; then modules="$modules Backend"; fi
        if echo "$diff_files" | grep -q "^MCP/" && [[ ! "$modules" == *MCP* ]]; then modules="$modules MCP"; fi
        if echo "$diff_files" | grep -q "^Frontend/" && [[ ! "$modules" == *Frontend* ]]; then modules="$modules Frontend"; fi
        if echo "$diff_files" | grep -q "^Tools/" && [[ ! "$modules" == *Tools* ]]; then modules="$modules Tools"; fi
    fi
    # 兜底：什么都没检测到时跑全量
    if [ -z "$modules" ]; then
        modules="Backend MCP Frontend Tools"
    fi
    echo "$modules" | xargs  # 去掉前后空格
}

# 从 task files: 字段提取受影响的 Go 包路径（相对于 Backend/）
_detect_go_packages() {
    local go_pkgs=""
    if [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
        go_pkgs=$(sed -n '/^files:/,/^[^[:space:]-]/p' "$TASK_FILE" \
            | grep '^\s*-.*Backend/' \
            | sed 's|^\s*-\s*"*Backend/||; s|"$||; s|/[^/]*$||' \
            | sort -u \
            | sed 's|^|./|' \
            | tr '\n' ' ' || true)
    fi
    # 补充 git diff
    local diff_pkgs
    diff_pkgs=$(git diff --name-only HEAD~1 HEAD 2>/dev/null \
        | grep '^Backend/' \
        | sed 's|^Backend/||; s|/[^/]*$||' \
        | sort -u \
        | sed 's|^|./|' \
        | tr '\n' ' ' || true)
    go_pkgs="$go_pkgs $diff_pkgs"
    # 去重
    go_pkgs=$(echo "$go_pkgs" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    [ -z "$(echo "$go_pkgs" | tr -d ' ')" ] && go_pkgs="./..."
    echo "$go_pkgs"
}

# 运行编译+测试，输出机械指标
# 只对受影响模块执行（基于 task scope + git diff），非涉及模块跳过
# 返回格式: compile_ok:test_pass:test_total
run_compile_test() {
    local compile_ok=1
    local test_pass=0
    local test_total=0
    local affected
    affected=$(_detect_affected_modules)
    echo "  [SCOPE] 受影响模块: ${affected}" >&2

    # Go 服务端
    if [[ "$affected" == *Backend* ]] && [ -d "Backend" ]; then
        local go_pkgs
        go_pkgs=$(_detect_go_packages)
        echo "  [SCOPE] Go 包: ${go_pkgs}" >&2
        # shellcheck disable=SC2086
        if ! (cd Backend && go build $go_pkgs 2>&1) >/dev/null 2>&1; then
            compile_ok=0
            echo "  [COMPILE] Go Server: FAIL" >&2
        else
            echo "  [COMPILE] Go Server: OK" >&2
            local test_output
            # shellcheck disable=SC2086
            test_output=$(cd Backend && go test -short -count=1 $go_pkgs 2>&1) || true
            local passed
            passed=$(echo "$test_output" | grep -c "^ok" 2>/dev/null || true)
            local failed
            failed=$(echo "$test_output" | grep -c "^FAIL" 2>/dev/null || true)
            [ -z "$passed" ] && passed=0
            [ -z "$failed" ] && failed=0
            test_pass=$((test_pass + passed))
            test_total=$((test_total + passed + failed))
            echo "  [TEST] Go Server: ${passed} pass / ${failed} fail" >&2
        fi
    fi

    # TypeScript MCP
    if [[ "$affected" == *MCP* ]] && [ -d "MCP" ] && [ -f "MCP/tsconfig.json" ]; then
        if ! (cd MCP && npx tsc --noEmit 2>&1) >/dev/null 2>&1; then
            compile_ok=0
            echo "  [COMPILE] TS MCP: FAIL" >&2
        else
            echo "  [COMPILE] TS MCP: OK" >&2
            if [ -f "MCP/jest.config.ts" ] || [ -f "MCP/jest.config.js" ] || grep -q '"jest"' "MCP/package.json" 2>/dev/null; then
                local mcp_test_output
                mcp_test_output=$(cd MCP && npx jest --passWithNoTests 2>&1) || true
                local mcp_passed
                mcp_passed=$(echo "$mcp_test_output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
                local mcp_failed
                mcp_failed=$(echo "$mcp_test_output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
                [ -z "$mcp_passed" ] && mcp_passed=0
                [ -z "$mcp_failed" ] && mcp_failed=0
                test_pass=$((test_pass + mcp_passed))
                test_total=$((test_total + mcp_passed + mcp_failed))
                echo "  [TEST] TS MCP: ${mcp_passed} pass / ${mcp_failed} fail" >&2
            fi
        fi
    fi

    # TypeScript Client
    if [[ "$affected" == *Frontend* ]] && [ -d "Frontend" ] && [ -f "Frontend/tsconfig.json" ]; then
        if ! (cd Frontend && npx tsc --noEmit 2>&1) >/dev/null 2>&1; then
            compile_ok=0
            echo "  [COMPILE] TS Client: FAIL" >&2
        else
            echo "  [COMPILE] TS Client: OK" >&2
            if [ -f "Frontend/jest.config.ts" ] || [ -f "Frontend/jest.config.js" ] || grep -q '"jest"' "Frontend/package.json" 2>/dev/null; then
                local client_test_output
                client_test_output=$(cd Frontend && npx jest --passWithNoTests 2>&1) || true
                local client_passed
                client_passed=$(echo "$client_test_output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
                local client_failed
                client_failed=$(echo "$client_test_output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
                [ -z "$client_passed" ] && client_passed=0
                [ -z "$client_failed" ] && client_failed=0
                test_pass=$((test_pass + client_passed))
                test_total=$((test_total + client_passed + client_failed))
                echo "  [TEST] TS Client: ${client_passed} pass / ${client_failed} fail" >&2
            fi
        fi
    fi

    # Python Tools
    if [[ "$affected" == *Tools* ]] && [ -d "Tools" ] && command -v pytest &>/dev/null; then
        local py_test_output
        py_test_output=$(cd Tools && pytest --tb=no -q 2>&1) || true
        local py_passed
        py_passed=$(echo "$py_test_output" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
        local py_failed
        py_failed=$(echo "$py_test_output" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
        [ -z "$py_passed" ] && py_passed=0
        [ -z "$py_failed" ] && py_failed=0
        if [ "$((py_passed + py_failed))" -gt 0 ]; then
            test_pass=$((test_pass + py_passed))
            test_total=$((test_total + py_passed + py_failed))
            echo "  [TEST] Python Tools: ${py_passed} pass / ${py_failed} fail" >&2
        fi
    fi

    # 输出指标到 stdout（供调用者捕获）
    echo "${compile_ok}:${test_pass}:${test_total}"
}

# 比较测试指标：当前 vs 基线
# 返回: "better" | "same" | "worse"
compare_metrics() {
    local base_compile=$1 base_pass=$2 base_total=$3
    local curr_compile=$4 curr_pass=$5 curr_total=$6

    # 编译从通过变为失败 → 直接判定 worse
    if [ "$base_compile" -eq 1 ] && [ "$curr_compile" -eq 0 ]; then
        echo "worse"
        return
    fi

    # 编译从失败变为通过 → better
    if [ "$base_compile" -eq 0 ] && [ "$curr_compile" -eq 1 ]; then
        echo "better"
        return
    fi

    # 测试通过数减少 → worse
    if [ "$curr_pass" -lt "$base_pass" ]; then
        echo "worse"
        return
    fi

    # 测试通过数增加 → better
    if [ "$curr_pass" -gt "$base_pass" ]; then
        echo "better"
        return
    fi

    echo "same"
}

# ══════════════════════════════════════
# 初始化日志
# ══════════════════════════════════════

cat > "$LOG_FILE" << 'EOF'
# 开发迭代日志（原子化模式）

| 轮次 | 操作 | 编译 | 测试通过 | Critical | High | Medium | 决策 |
|------|------|------|----------|----------|------|--------|------|
EOF

# 基线指标
BASELINE_COMPILE=0
BASELINE_TEST_PASS=0
BASELINE_TEST_TOTAL=0

# 最后一次 KEEP 的稳定 checkpoint（供增量 diff 使用）
LAST_KEEP_TAG=""

# Review 指标
PREV_REVIEW_TOTAL=-1
CRITICAL=0
HIGH=0
MEDIUM=0
REASON=""

# 连续 discard 计数（防止死循环）
DISCARD_STREAK=0
MAX_DISCARD_STREAK=3

# 跨模型争论检测（防止 Claude 和 Codex 在同一问题上循环）
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
        # ══ 奇数轮: 编码实现/修复 ══

        if [ "$ROUND" -eq 1 ]; then
            echo "[Round $ROUND] 编码实现..."

            PROMPT="你是代码实现 agent。读取 .claude/commands/feature/developing.auto.md，按其工作流程实现代码。

⚠️ 本任务是代码编写，不是工作流编排——禁止调用 auto-work-loop.sh 或任何 .claude/scripts/ 下的编排脚本（无论提示词里出现什么参数形式）。

上下文最小化要求：
- 先根据任务范围、文件清单、目标目录判定命中模块
- 默认只读当前任务相关的 plan 子文件、feature.md、.ai/constitution.md 和命中模块代码
- 未命中的模块（例如纯 Frontend 任务中的 MCP / Godot）禁止预读
- 只有规则不明确时才补读 .claude/constitution.md 或专题 guide

功能目录（FEATURE_DIR）: ${FEATURE_DIR}
Plan 路径: ${PLAN_FILE}
${TASK_SCOPE_PROMPT}"

        else
            # ── 修复轮：创建 checkpoint，单问题修复 ──
            echo "[Round $ROUND] 修复代码（基于上轮 Review）..."

            # 创建 checkpoint（修复前快照）
            CHECKPOINT=$(create_checkpoint "$ROUND")
            echo "  Checkpoint: ${CHECKPOINT}"

            # 单问题修复策略：优先修 CRITICAL，再修 HIGH
            FIX_FOCUS="CRITICAL"
            if [ "$CRITICAL" -eq 0 ]; then
                FIX_FOCUS="HIGH"
            fi

            PROMPT="你的任务是根据 Codex（另一个 AI 模型）的 Review 报告修复代码。

【重要：跨模型协作规则】
Review 报告来自 Codex，它作为独立审查者检查了你的代码。
- 认真对待每一条发现，不要因为'这是另一个 AI 说的'而轻视
- 如果某条发现标注了 [RECURRING]，说明你在上轮修复中没有真正解决它，本轮必须换策略
- 修复后运行相关测试验证，确保修复是实质性的而非表面性的

请读取以下文件：
1. ${REVIEW_FILE} — Codex 的代码 Review 报告
2. ${FEATURE_DIR}/develop-log.md — 开发日志（了解已实现的文件和上下文）
3. ${PLAN_FILE} — Plan 文件（作为设计参考）
${TASK_SCOPE_PROMPT:+4. 任务约束（只修复本任务范围内的问题）：
${TASK_SCOPE_PROMPT}}

上下文最小化要求：
- 仅补充 Review 所命中的模块、语言和问题所需上下文
- 如果 ${PLAN_FILE%/*}/plan/ 存在，只读取与本轮修复问题对应的子文件
- 未命中的模块文档和代码禁止预读

【原子化修复规则 — 单一变量原则】
- 本轮只聚焦修复 ${FIX_FOCUS} 级别的问题
- 每个修复必须是最小可验证的变更：改一处，验证一处
- 修复后读取 .ai/constitution.md 和 .claude/constitution.md 做合宪性自检
- 不做额外重构或改进，不修复报告中未列出的问题
- MEDIUM 问题本轮不修
- 修复完成后，更新 ${FEATURE_DIR}/develop-log.md（追加修复记录）
- 禁止将任何问题标记为"需人工介入"——全部自主解决"
        fi

        mark_stage "develop-iteration" "${TASK_FILE:+$(basename "${TASK_FILE}" .md)}" "$ROUND"
        cli_call "$PROMPT" --permission-mode bypassPermissions 2>&1 | tail -20

        # ══ 机械判定：编译 + 测试 ══
        echo ""
        echo "── 机械判定：编译 + 测试 ──"
        METRICS=$(run_compile_test)
        CURR_COMPILE=$(echo "$METRICS" | cut -d: -f1)
        CURR_TEST_PASS=$(echo "$METRICS" | cut -d: -f2)
        CURR_TEST_TOTAL=$(echo "$METRICS" | cut -d: -f3)

        echo "  指标: compile=${CURR_COMPILE} test_pass=${CURR_TEST_PASS}/${CURR_TEST_TOTAL}"

        if [ "$ROUND" -eq 1 ]; then
            # ── 首轮：记录基线 ──
            BASELINE_COMPILE=$CURR_COMPILE
            BASELINE_TEST_PASS=$CURR_TEST_PASS
            BASELINE_TEST_TOTAL=$CURR_TEST_TOTAL
            DECISION="baseline"
            echo "  记录基线: compile=${BASELINE_COMPILE} test_pass=${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL}"

            # 首轮编译失败 → 自动修复编译（只收集受影响模块的错误）
            if [ "$CURR_COMPILE" -eq 0 ]; then
                echo "  首轮编译失败，启动自动修复..."
                _affected=$(_detect_affected_modules)
                COMPILE_ERRORS=""
                if [[ "$_affected" == *Backend* ]] && [ -d "Backend" ]; then
                    _go_pkgs=$(_detect_go_packages)
                    # shellcheck disable=SC2086
                    COMPILE_ERRORS+=$(cd Backend && go build $_go_pkgs 2>&1 | head -30 || true)$'\n'
                fi
                if [[ "$_affected" == *MCP* ]] && [ -d "MCP" ] && [ -f "MCP/tsconfig.json" ]; then
                    COMPILE_ERRORS+=$(cd MCP && npx tsc --noEmit 2>&1 | head -30 || true)$'\n'
                fi
                if [[ "$_affected" == *Frontend* ]] && [ -d "Frontend" ] && [ -f "Frontend/tsconfig.json" ]; then
                    COMPILE_ERRORS+=$(cd Frontend && npx tsc --noEmit 2>&1 | head -30 || true)$'\n'
                fi

                FIX_PROMPT="编译失败，请修复以下错误。只修复编译错误，不做额外改动。

\`\`\`
${COMPILE_ERRORS}
\`\`\`

修复后重新运行编译命令验证。"
                cli_call "$FIX_PROMPT" --permission-mode bypassPermissions 2>&1 | tail -10

                # 重新测量基线
                METRICS=$(run_compile_test)
                BASELINE_COMPILE=$(echo "$METRICS" | cut -d: -f1)
                BASELINE_TEST_PASS=$(echo "$METRICS" | cut -d: -f2)
                BASELINE_TEST_TOTAL=$(echo "$METRICS" | cut -d: -f3)
                echo "  更新基线: compile=${BASELINE_COMPILE} test_pass=${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL}"
                echo "| $ROUND.1 | 编译修复 | ${BASELINE_COMPILE} | ${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL} | - | - | - | baseline-fix |" >> "$LOG_FILE"
            fi

            # 首轮测试失败 → 自动修复测试（scope 到受影响包）
            if [ "$BASELINE_COMPILE" -eq 1 ] && [ "$BASELINE_TEST_PASS" -lt "$BASELINE_TEST_TOTAL" ] && [ "$BASELINE_TEST_TOTAL" -gt 0 ]; then
                echo "  部分测试失败，启动自动修复..."
                local _go_test_pkgs
                _go_test_pkgs=$(_detect_go_packages)
                # shellcheck disable=SC2086
                TEST_ERRORS=$(cd Backend && go test -short -count=1 $_go_test_pkgs 2>&1 | grep -E 'FAIL|Error|panic' | head -20 || echo "")
                FIX_PROMPT="单元测试部分失败，请修复：

\`\`\`
${TEST_ERRORS}
\`\`\`

分析失败的测试用例，判断是代码 bug 还是测试需要更新。修复后重新运行 cd Backend && go test -short -count=1 ${_go_test_pkgs} 验证。"
                cli_call "$FIX_PROMPT" --permission-mode bypassPermissions 2>&1 | tail -10

                METRICS=$(run_compile_test)
                BASELINE_COMPILE=$(echo "$METRICS" | cut -d: -f1)
                BASELINE_TEST_PASS=$(echo "$METRICS" | cut -d: -f2)
                BASELINE_TEST_TOTAL=$(echo "$METRICS" | cut -d: -f3)
                echo "  更新基线: compile=${BASELINE_COMPILE} test_pass=${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL}"
                echo "| $ROUND.2 | 测试修复 | ${BASELINE_COMPILE} | ${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL} | - | - | - | baseline-fix |" >> "$LOG_FILE"
            fi

            # 创建首轮 checkpoint（也是初始稳定基线）
            create_checkpoint "$ROUND" > /dev/null
            LAST_KEEP_TAG=$(checkpoint_tag "$ROUND")

        else
            # ── 修复轮：keep/discard 判定 ──
            VERDICT=$(compare_metrics "$BASELINE_COMPILE" "$BASELINE_TEST_PASS" "$BASELINE_TEST_TOTAL" \
                                      "$CURR_COMPILE" "$CURR_TEST_PASS" "$CURR_TEST_TOTAL")

            if [ "$VERDICT" = "worse" ]; then
                DECISION="DISCARD"
                DISCARD_STREAK=$((DISCARD_STREAK + 1))
                echo "  DISCARD: 测试指标退步 (baseline: ${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL} → current: ${CURR_TEST_PASS}/${CURR_TEST_TOTAL})"
                discard_to_checkpoint "$CHECKPOINT"

                # 连续 discard 过多 → 停止（避免死循环）
                if [ "$DISCARD_STREAK" -ge "$MAX_DISCARD_STREAK" ]; then
                    REASON="连续${MAX_DISCARD_STREAK}次回滚"
                    echo "STOP: 连续 ${MAX_DISCARD_STREAK} 次修复被回滚，停止迭代"
                    break
                fi
            else
                DECISION="KEEP"
                DISCARD_STREAK=0
                # 更新基线为当前值
                BASELINE_COMPILE=$CURR_COMPILE
                BASELINE_TEST_PASS=$CURR_TEST_PASS
                BASELINE_TEST_TOTAL=$CURR_TEST_TOTAL
                echo "  KEEP: 测试指标未退步 (${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL})"
                # 更新 checkpoint 并记录为稳定基线
                create_checkpoint "$ROUND" > /dev/null
                LAST_KEEP_TAG=$(checkpoint_tag "$ROUND")
            fi
        fi

        echo "| $ROUND | 编码/修复 | ${CURR_COMPILE} | ${CURR_TEST_PASS}/${CURR_TEST_TOTAL} | - | - | - | ${DECISION} |" >> "$LOG_FILE"

        # ══ Fail-Fast: 编译不过不进 review ══
        if [ "$CURR_COMPILE" -eq 0 ] && [ "$ROUND" -gt 1 ]; then
            echo "  FAIL-FAST: 编译未通过，跳过 review，下轮继续修编译"
            # 把下一偶数轮的 review 跳过，伪造一个 review 结果让循环继续
            CRITICAL=999
            HIGH=0
            MEDIUM=0
            echo "| $((ROUND + 1)) | Review(跳过-编译未过) | - | - | - | - | - | fail-fast |" >> "$LOG_FILE"
            # 跳过下一轮的 review（手动推进 ROUND）
            # 注意：我们不能直接 skip，但下一轮是 even，会进入 review 分支
            # 所以这里我们设置一个标记
            SKIP_NEXT_REVIEW=1
            continue
        fi
        SKIP_NEXT_REVIEW=0

    else
        # ══ 偶数轮: 代码审查 ══

        # Fail-fast: 如果上轮编译未通过，跳过 review
        if [ "${SKIP_NEXT_REVIEW:-0}" -eq 1 ]; then
            echo "[Round $ROUND] 跳过 Review (fail-fast: 编译未通过)"
            SKIP_NEXT_REVIEW=0
            continue
        fi

        echo "[Round $ROUND] Review 代码 (via Codex — 对抗审查)..."

        # 生成压缩审查输入
        REVIEW_INPUT=$(generate_develop_review_input "$ROUND" "${PRE_DEV_HEAD:-HEAD~1}")

        # 构建上轮问题摘要（供 Codex 追踪修复效果）
        PREV_ISSUES_CONTEXT=""
        if [ "$ROUND" -gt 2 ] && [ -f "$REVIEW_FILE" ]; then
            PREV_ISSUES_CONTEXT="
【上轮 Review 遗留问题摘要】
上轮 Review (Round $((ROUND - 2))) 发现: Critical=${CRITICAL}, High=${HIGH}, Medium=${MEDIUM}
请重点验证这些问题是否已被有效修复，而非被绕过或掩盖。如果发现同一问题反复出现，在报告中标注 [RECURRING] 标签。

【增量审查模式】本轮只需要关注：
1. 上轮未修复的问题是否已解决
2. 增量 diff 中引入的新问题
3. 不需要重新审查所有已有代码"
        fi

        PROMPT="你是一名严苛的资深架构师，正在审查另一个 AI（Claude）编写的代码。你的目标是找出 Claude 可能遗漏的盲区。

读取 .ai/context/reviewer-brief.md 作为审查规则。
读取 ${REVIEW_INPUT} 了解本轮审查输入（diff 摘要、测试结果、遗留问题）。

参数（已解析，直接使用）：
- version_id: ${VERSION_ID}
- feature_name: ${FEATURE_NAME}
- FEATURE_DIR: ${FEATURE_DIR}
${PREV_ISSUES_CONTEXT}

自动化模式特殊规则：
1. 完成 Review 后，将完整的 Review 报告写入文件 ${REVIEW_FILE}（覆盖之前的报告）
2. 在报告文件的最后一行，必须追加以下格式的元数据（用于脚本自动解析，不要遗漏）：
   <!-- counts: critical=X high=Y medium=Z -->
   其中 X/Y/Z 替换为实际问题数量
3. 对每个发现的问题，给出具体文件路径和行号，以及最小修复建议（一句话）
4. 如果发现上下文缺口，在报告中新增“## Context Repairs”段，写出建议更新的文件和要补充的规则"

        # 根据风险信号选择单路或并行 review
        # 使用 LAST_KEEP_TAG 作为增量基线（与 generate_develop_review_input 一致）
        # 这样后续轮次只统计本轮增量变更，而非全程变更
        if [ -n "${LAST_KEEP_TAG:-}" ] && git rev-parse "$LAST_KEEP_TAG" >/dev/null 2>&1; then
            CHANGE_METRICS=$(count_changes "$LAST_KEEP_TAG")
        else
            CHANGE_METRICS=$(count_changes "${PRE_DEV_HEAD:-HEAD~1}")
        fi
        CHANGED_DIRS=$(echo "$CHANGE_METRICS" | cut -d: -f1)
        CHANGED_FILES=$(echo "$CHANGE_METRICS" | cut -d: -f2)
        REVIEW_MODE=$(should_use_parallel "${COMPLEXITY:-L}" "$CHANGED_DIRS" "$CHANGED_FILES" "$CRITICAL" "$HIGH")
        echo "  Review mode: ${REVIEW_MODE} (dirs=${CHANGED_DIRS} files=${CHANGED_FILES})"

        if [ "$REVIEW_MODE" = "parallel" ]; then
            run_parallel_develop_reviews "$PROMPT" "$REVIEW_FILE"
        else
            run_single_develop_review "$PROMPT" "$REVIEW_FILE"
        fi

        # Context Repairs: 仅在发现 RECURRING 问题时触发
        if grep -q '\[RECURRING\]' "$REVIEW_FILE" 2>/dev/null; then
            apply_context_repairs "$REVIEW_FILE"
        else
            echo "  [Context Repair] 跳过（无 RECURRING 标记）"
        fi

        # 解析 Review 结果
        if [ -f "$REVIEW_FILE" ]; then
            COUNTS_LINE=$(grep -o 'counts: critical=[0-9]* high=[0-9]* medium=[0-9]*' "$REVIEW_FILE" 2>/dev/null | tail -1 || echo "")
            if [ -n "$COUNTS_LINE" ]; then
                CRITICAL=$(echo "$COUNTS_LINE" | sed 's/.*critical=\([0-9]*\).*/\1/')
                HIGH=$(echo "$COUNTS_LINE" | sed 's/.*high=\([0-9]*\).*/\1/')
                MEDIUM=$(echo "$COUNTS_LINE" | sed 's/.*medium=\([0-9]*\).*/\1/')
            else
                echo "WARNING: 无法解析 Review 报告中的 counts 元数据"
                tail -5 "$REVIEW_FILE"
                CRITICAL=999
                HIGH=999
                MEDIUM=0
            fi
        else
            echo "WARNING: Review 报告文件未生成: ${REVIEW_FILE}"
            CRITICAL=999
            HIGH=999
            MEDIUM=0
        fi

        CURRENT_REVIEW_TOTAL=$((CRITICAL + HIGH))
        COMPILE_LABEL=$( [ "$BASELINE_COMPILE" -eq 1 ] && echo "OK" || echo "FAIL" )
        echo "| $ROUND | Review | ${COMPILE_LABEL} | ${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL} | $CRITICAL | $HIGH | $MEDIUM | - |" >> "$LOG_FILE"
        echo "Review 结果: Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM"

        # ══ 收敛判断（双重门禁：机械指标 + AI review） ══

        # 条件 1: 编译通过 + 测试全过 + review 质量达标
        if [ "$BASELINE_COMPILE" -eq 1 ] && \
           { [ "$BASELINE_TEST_TOTAL" -eq 0 ] || [ "$BASELINE_TEST_PASS" -ge "$BASELINE_TEST_TOTAL" ]; } && \
           [ "$CRITICAL" -eq 0 ] && [ "$HIGH" -le 2 ]; then
            REASON="质量达标(编译OK+测试全过+Review清洁)"
            echo "PASS: $REASON"
            break
        fi

        # 条件 2: review 质量达标（即使没有测试，编译通过即可）
        if [ "$BASELINE_COMPILE" -eq 1 ] && [ "$CRITICAL" -eq 0 ] && [ "$HIGH" -le 2 ]; then
            REASON="质量达标(编译OK+Review清洁)"
            echo "PASS: $REASON"
            break
        fi

        # 条件 3: Review 问题数稳定不变（AI 无法再发现新问题）
        if [ "$PREV_REVIEW_TOTAL" -ge 0 ] && [ "$CURRENT_REVIEW_TOTAL" -eq "$PREV_REVIEW_TOTAL" ]; then
            REASON="Review未收敛(稳定不变)"
            echo "WARN: $REASON (问题总数未减少: $CURRENT_REVIEW_TOTAL)"
            break
        fi

        # 条件 4: 跨模型争论停机准则 — CRITICAL 数连续 N 轮不变，说明 Claude 和 Codex 在同一问题上循环
        if [ "$PREV_CRITICAL_COUNT" -ge 0 ] && [ "$CRITICAL" -eq "$PREV_CRITICAL_COUNT" ] && [ "$CRITICAL" -gt 0 ]; then
            SAME_CRITICAL_STREAK=$((SAME_CRITICAL_STREAK + 1))
            echo "  争论检测: CRITICAL 连续 ${SAME_CRITICAL_STREAK}/${MAX_SAME_CRITICAL_STREAK} 轮不变 (=${CRITICAL})"
            if [ "$SAME_CRITICAL_STREAK" -ge "$MAX_SAME_CRITICAL_STREAK" ]; then
                REASON="跨模型争论停机(CRITICAL=${CRITICAL}连续${MAX_SAME_CRITICAL_STREAK}轮未收敛)"
                echo "STOP: $REASON — Claude 和 Codex 在同一问题上循环争论，需人工介入定义业务规则"
                # 检查是否有 RECURRING 标签的问题
                if [ -f "$REVIEW_FILE" ]; then
                    RECURRING_ISSUES=$(grep -c '\[RECURRING\]' "$REVIEW_FILE" 2>/dev/null || echo "0")
                    echo "  反复出现的问题数: ${RECURRING_ISSUES}"
                fi
                break
            fi
        else
            SAME_CRITICAL_STREAK=0
        fi
        PREV_CRITICAL_COUNT=$CRITICAL

        PREV_REVIEW_TOTAL=$CURRENT_REVIEW_TOTAL
    fi
done

# 如果循环自然结束
if [ -z "$REASON" ]; then
    REASON="达到上限"
fi

# ══════════════════════════════════════
# 清理 checkpoint tags
# ══════════════════════════════════════
cleanup_checkpoints

# ══════════════════════════════════════
# 写入总结
# ══════════════════════════════════════

cat >> "$LOG_FILE" << EOF

## 总结
- 总轮次：$ROUND
- 终止原因：$REASON
- 最终编译：$( [ "$BASELINE_COMPILE" -eq 1 ] && echo "通过" || echo "失败" )
- 最终测试：${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL} 通过
- 最终 Review：Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM
- 回滚次数：$DISCARD_STREAK (累计)
EOF

echo ""
echo "══════════════════════════════════════"
echo "  开发迭代完成（原子化模式）"
echo "══════════════════════════════════════"
echo "  轮次: $ROUND"
echo "  终止原因: $REASON"
echo "  编译: $( [ "$BASELINE_COMPILE" -eq 1 ] && echo "通过" || echo "失败" )"
echo "  测试: ${BASELINE_TEST_PASS}/${BASELINE_TEST_TOTAL} 通过"
echo "  Review: Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM"
echo "  Plan 文件: $PLAN_FILE"
echo "  迭代日志: $LOG_FILE"
echo "  开发日志: ${FEATURE_DIR}/develop-log.md"
echo "══════════════════════════════════════"

# 退出码：CRITICAL > 0 且编译未通过 → 非零退出（通知调用方任务未完成）
if [ "$BASELINE_COMPILE" -eq 0 ]; then
    echo "EXIT 1: 编译未通过"
    exit 1
fi
if [ "$CRITICAL" -gt 0 ] && [ "$REASON" != "质量达标(编译OK+测试全过+Review清洁)" ] && [ "$REASON" != "质量达标(编译OK+Review清洁)" ]; then
    echo "EXIT 2: 仍有 ${CRITICAL} 个 CRITICAL 问题未修复 (终止原因: ${REASON})"
    exit 2
fi
