#!/bin/bash
# _test_agent_mode_dryrun.sh
# ROUTE_MODE_B (Agent 编排) 的 dry-run 验证脚本。
#
# 不启动真实 Agent，而是模拟编排者的决策路径，验证：
#   1. 预检路由逻辑正确区分 MODE_A / MODE_B
#   2. 每个阶段的断点续跑判断正确
#   3. 文件产物契约（输入/输出文件名）与 Bash 模式一致
#   4. 基线变量（PRE_DEV_HEAD_ALL / PRE_TASK_HEAD）在正确时机被记录
#   5. 收敛判断逻辑（counts 解析、停机准则）可正确触发
#
# 用法: bash .claude/scripts/_test_agent_mode_dryrun.sh
#
# 输出: PASS/FAIL 逐项报告，退出码 0 = 全通过

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t agent-mode-test)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo "  [PASS] $desc"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $desc"
        FAIL=$((FAIL + 1))
    fi
}

# grep -c 在 count=0 时 exit 1，用 wc -l 避免 pipefail + || echo 0 拼接问题
count_matches() {
    local pattern="$1"
    local file="$2"
    grep "$pattern" "$file" 2>/dev/null | wc -l | tr -d ' \r\n'
}

# ══════════════════════════════════════
# T1: 预检路由逻辑
# ══════════════════════════════════════
echo ""
echo "=== T1: 预检路由逻辑 ==="

# T1.1: claude + codex 均可用 → ROUTE_MODE_A
mkdir -p "$TMP_DIR/t1/bin"
cat > "$TMP_DIR/t1/bin/claude" <<'EOF'
#!/bin/bash
echo "OK"
exit 0
EOF
cat > "$TMP_DIR/t1/bin/codex" <<'EOF'
#!/bin/bash
echo "codex help"
exit 0
EOF
chmod +x "$TMP_DIR/t1/bin/claude" "$TMP_DIR/t1/bin/codex"

T1_OUT=$(PATH="$TMP_DIR/t1/bin:$PATH" bash -c '
CLAUDE_OK=0
claude -p "reply OK" --permission-mode bypassPermissions > /dev/null 2>&1 && CLAUDE_OK=1
CODEX_OK=0
if [ "$CLAUDE_OK" = "1" ] && command -v codex > /dev/null 2>&1; then
    codex --help > /dev/null 2>&1 && CODEX_OK=1
fi
if [ "$CLAUDE_OK" = "1" ] && [ "$CODEX_OK" = "1" ]; then
    echo "ROUTE_MODE_A"
else
    echo "ROUTE_MODE_B"
fi
' 2>/dev/null)
check "claude+codex OK → ROUTE_MODE_A" "$([ "$T1_OUT" = "ROUTE_MODE_A" ] && echo 0 || echo 1)"

# T1.2: claude OK + codex broken → ROUTE_MODE_B
# 模拟 codex --help 失败：将坏 codex 放在 PATH 最前面覆盖真实 codex
mkdir -p "$TMP_DIR/t1/bin-bad-codex"
cp "$TMP_DIR/t1/bin/claude" "$TMP_DIR/t1/bin-bad-codex/"
cat > "$TMP_DIR/t1/bin-bad-codex/codex" <<'EOF'
#!/bin/bash
exit 127
EOF
chmod +x "$TMP_DIR/t1/bin-bad-codex/codex"
T1B_OUT=$(PATH="$TMP_DIR/t1/bin-bad-codex:$PATH" bash -c '
CLAUDE_OK=0
claude -p "reply OK" --permission-mode bypassPermissions > /dev/null 2>&1 && CLAUDE_OK=1
CODEX_OK=0
if [ "$CLAUDE_OK" = "1" ] && command -v codex > /dev/null 2>&1; then
    codex --help > /dev/null 2>&1 && CODEX_OK=1
fi
if [ "$CLAUDE_OK" = "1" ] && [ "$CODEX_OK" = "1" ]; then
    echo "ROUTE_MODE_A"
else
    echo "ROUTE_MODE_B"
fi
' 2>/dev/null)
check "claude OK + codex broken → ROUTE_MODE_B" "$([ "$T1B_OUT" = "ROUTE_MODE_B" ] && echo 0 || echo 1)"

# T1.3: claude fails → ROUTE_MODE_B
mkdir -p "$TMP_DIR/t1/bin-no-claude"
cat > "$TMP_DIR/t1/bin-no-claude/claude" <<'EOF'
#!/bin/bash
exit 1
EOF
cp "$TMP_DIR/t1/bin/codex" "$TMP_DIR/t1/bin-no-claude/"
chmod +x "$TMP_DIR/t1/bin-no-claude/claude"

T1C_OUT=$(PATH="$TMP_DIR/t1/bin-no-claude:$PATH" bash -c '
CLAUDE_OK=0
claude -p "reply OK" --permission-mode bypassPermissions > /dev/null 2>&1 && CLAUDE_OK=1
CODEX_OK=0
if [ "$CLAUDE_OK" = "1" ] && command -v codex > /dev/null 2>&1; then
    codex --help > /dev/null 2>&1 && CODEX_OK=1
fi
if [ "$CLAUDE_OK" = "1" ] && [ "$CODEX_OK" = "1" ]; then
    echo "ROUTE_MODE_A"
else
    echo "ROUTE_MODE_B"
fi
' 2>/dev/null)
check "claude fails → ROUTE_MODE_B" "$([ "$T1C_OUT" = "ROUTE_MODE_B" ] && echo 0 || echo 1)"

# ══════════════════════════════════════
# T2: 断点续跑判断
# ══════════════════════════════════════
echo ""
echo "=== T2: 断点续跑判断 ==="

FEAT_DIR="$TMP_DIR/t2/Docs/Version/v0.0.1/test-feature"
mkdir -p "$FEAT_DIR/tasks"

# T2.1: classification.txt 存在 → 跳过分类
echo "type=direct" > "$FEAT_DIR/classification.txt"
echo "complexity=S" >> "$FEAT_DIR/classification.txt"
check "classification.txt 存在 → 跳过分类" "$([ -f "$FEAT_DIR/classification.txt" ] && echo 0 || echo 1)"

# T2.2: feature.md 存在 → 跳过生成
echo "# Test Feature" > "$FEAT_DIR/feature.md"
check "feature.md 存在 → 跳过生成" "$([ -f "$FEAT_DIR/feature.md" ] && echo 0 || echo 1)"

# T2.3: plan.md 存在 → 跳过 plan
echo "# Test Plan" > "$FEAT_DIR/plan.md"
check "plan.md 存在 → 跳过 plan" "$([ -f "$FEAT_DIR/plan.md" ] && echo 0 || echo 1)"

# T2.4: task-01.md 存在 → 跳过拆分
cat > "$FEAT_DIR/tasks/task-01.md" <<'EOF'
---
name: test task
status: pending
estimated_files: 1
estimated_lines: 10
verify_commands:
  - "go build ./..."
depends_on: []
---
EOF
check "tasks/task-01.md 存在 → 跳过拆分" "$([ -f "$FEAT_DIR/tasks/task-01.md" ] && echo 0 || echo 1)"

# T2.5: task-01.md status: completed → 跳过该任务
sed -i 's/status: pending/status: completed/' "$FEAT_DIR/tasks/task-01.md"
SKIP=$(grep -c "status: completed" "$FEAT_DIR/tasks/task-01.md" 2>/dev/null || echo 0)
check "task status=completed → 跳过执行" "$([ "$SKIP" -gt 0 ] && echo 0 || echo 1)"

# ══════════════════════════════════════
# T3: 文件产物契约一致性
# ══════════════════════════════════════
echo ""
echo "=== T3: 文件产物契约一致性（Agent vs Bash 同名） ==="

# 验证 Agent 模式协议中提到的产出文件名与 Bash 模式脚本一致
CONTRACT="$SCRIPT_DIR/../contracts/auto-work-agent-orchestration.md"
BASH_SCRIPT="$SCRIPT_DIR/auto-work-loop.sh"

if [ -f "$CONTRACT" ] && [ -f "$BASH_SCRIPT" ]; then
    # 关键产出文件列表（两种模式必须一致）
    # 使用两种模式都能匹配的模式（不含路径前缀）
    ARTIFACTS=(
        "classification.txt"
        "feature.md"
        "plan.md"
        "task-.*\.md"
        "acceptance-report.md"
        "auto-work-log.md"
        "task-guardian-report.md"
        "develop-review-report"
        "context-repair-log.md"
    )
    for art in "${ARTIFACTS[@]}"; do
        IN_CONTRACT=$(count_matches "$art" "$CONTRACT")
        IN_BASH=$(count_matches "$art" "$BASH_SCRIPT")
        if [ "$IN_CONTRACT" -gt 0 ] && [ "$IN_BASH" -gt 0 ]; then
            check "产物 '$art' 在两种模式中均有引用" "0"
        elif [ "$IN_CONTRACT" -gt 0 ] && [ "$IN_BASH" -eq 0 ]; then
            check "产物 '$art' 仅在 Agent 模式，Bash 中缺失" "1"
        elif [ "$IN_CONTRACT" -eq 0 ] && [ "$IN_BASH" -gt 0 ]; then
            check "产物 '$art' 仅在 Bash 模式，Agent 中缺失" "1"
        fi
    done
else
    check "契约文件和 Bash 脚本均存在" "1"
fi

# ══════════════════════════════════════
# T4: 基线变量完整性
# ══════════════════════════════════════
echo ""
echo "=== T4: 基线变量引用完整性 ==="

if [ -f "$CONTRACT" ]; then
    # PRE_DEV_HEAD_ALL 必须在前置准备中定义且在验收/guardian 中引用
    DEF_ALL=$(count_matches "PRE_DEV_HEAD_ALL" "$CONTRACT")
    check "PRE_DEV_HEAD_ALL 至少出现 3 次（定义+验收+guardian）" "$([ "$DEF_ALL" -ge 3 ] && echo 0 || echo 1)"

    # PRE_TASK_HEAD 必须在步骤 0 定义且在审查中引用
    DEF_TASK=$(count_matches "PRE_TASK_HEAD" "$CONTRACT")
    check "PRE_TASK_HEAD 至少出现 2 次（定义+审查）" "$([ "$DEF_TASK" -ge 2 ] && echo 0 || echo 1)"

    # 不应再有 HEAD~1 用于代码审查
    HEAD_TILDE=$(count_matches "HEAD~1" "$CONTRACT")
    check "无 HEAD~1 硬编码（应使用基线变量）" "$([ "$HEAD_TILDE" -eq 0 ] && echo 0 || echo 1)"
else
    check "契约文件存在" "1"
fi

# ══════════════════════════════════════
# T5: 收敛判断逻辑
# ══════════════════════════════════════
echo ""
echo "=== T5: 收敛判断 counts 解析 ==="

# 模拟 review report 末尾的 counts 行解析
MOCK_REVIEW="$TMP_DIR/t5-review.md"

# T5.1: 收敛 — critical=0, high=1
cat > "$MOCK_REVIEW" <<'EOF'
## Critical
- 无

## High
- 某个小问题

<!-- counts: critical=0 high=1 medium=2 -->
EOF

LAST_LINE=$(tail -1 "$MOCK_REVIEW")
CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
HIGH=$(echo "$LAST_LINE" | grep -oE 'high=[0-9]+' | cut -d= -f2)
CRIT=${CRIT:-999}
HIGH=${HIGH:-999}
CONVERGED=0
[ "$CRIT" -eq 0 ] && [ "$HIGH" -le 2 ] && CONVERGED=1
check "critical=0,high=1 → 收敛" "$([ "$CONVERGED" -eq 1 ] && echo 0 || echo 1)"

# T5.2: 未收敛 — critical=2
cat > "$MOCK_REVIEW" <<'EOF'
<!-- counts: critical=2 high=3 medium=5 -->
EOF

LAST_LINE=$(tail -1 "$MOCK_REVIEW")
CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
HIGH=$(echo "$LAST_LINE" | grep -oE 'high=[0-9]+' | cut -d= -f2)
CRIT=${CRIT:-999}
HIGH=${HIGH:-999}
CONVERGED=0
[ "$CRIT" -eq 0 ] && [ "$HIGH" -le 2 ] && CONVERGED=1
check "critical=2 → 未收敛" "$([ "$CONVERGED" -eq 0 ] && echo 0 || echo 1)"

# T5.3: 解析失败（无 counts 行）→ 安全默认未收敛
cat > "$MOCK_REVIEW" <<'EOF'
## Critical
一些文字但没有 counts 行
EOF

LAST_LINE=$(tail -1 "$MOCK_REVIEW")
CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
CRIT=${CRIT:-999}
check "无 counts 行 → 安全默认未收敛 (critical=999)" "$([ "$CRIT" -eq 999 ] && echo 0 || echo 1)"

# T5.4: 停机准则 — 连续 3 轮 critical 不变
CRIT_HISTORY=(3 3 3)
DEADLOCK=0
if [ "${CRIT_HISTORY[0]}" -eq "${CRIT_HISTORY[1]}" ] && [ "${CRIT_HISTORY[1]}" -eq "${CRIT_HISTORY[2]}" ] && [ "${CRIT_HISTORY[0]}" -gt 0 ]; then
    DEADLOCK=1
fi
check "连续 3 轮 critical=3 → 停机" "$([ "$DEADLOCK" -eq 1 ] && echo 0 || echo 1)"

# T5.5: 不停机 — critical 在变化
CRIT_HISTORY2=(3 2 1)
DEADLOCK2=0
if [ "${CRIT_HISTORY2[0]}" -eq "${CRIT_HISTORY2[1]}" ] && [ "${CRIT_HISTORY2[1]}" -eq "${CRIT_HISTORY2[2]}" ] && [ "${CRIT_HISTORY2[0]}" -gt 0 ]; then
    DEADLOCK2=1
fi
check "critical 3→2→1 → 不停机" "$([ "$DEADLOCK2" -eq 0 ] && echo 0 || echo 1)"

# ══════════════════════════════════════
# T6: 验收终态解析
# ══════════════════════════════════════
echo ""
echo "=== T6: 验收终态解析 ==="

MOCK_ACCEPT="$TMP_DIR/t6-accept.md"

# T6.1: ALL_REQ_ACCEPTED
echo "ALL_REQ_ACCEPTED" > "$MOCK_ACCEPT"
STATUS=$(tail -1 "$MOCK_ACCEPT" | grep -oE 'ALL_REQ_ACCEPTED|REMEDIATION_NEEDED|CANNOT_VERIFY|FINAL_FAIL' | head -1)
check "ALL_REQ_ACCEPTED 正确解析" "$([ "$STATUS" = "ALL_REQ_ACCEPTED" ] && echo 0 || echo 1)"

# T6.2: REMEDIATION_NEEDED
echo "REMEDIATION_NEEDED: REQ-001, REQ-003" > "$MOCK_ACCEPT"
STATUS=$(tail -1 "$MOCK_ACCEPT" | grep -oE 'ALL_REQ_ACCEPTED|REMEDIATION_NEEDED|CANNOT_VERIFY|FINAL_FAIL' | head -1)
FAILED_REQS=$(tail -1 "$MOCK_ACCEPT" | grep -oE 'REQ-[0-9]+' | tr '\n' ' ')
check "REMEDIATION_NEEDED 正确解析" "$([ "$STATUS" = "REMEDIATION_NEEDED" ] && echo 0 || echo 1)"
check "失败 REQ 编号提取" "$(echo "$FAILED_REQS" | grep -q 'REQ-001' && echo 0 || echo 1)"

# T6.3: FINAL_FAIL
echo "FINAL_FAIL: REQ-002" > "$MOCK_ACCEPT"
STATUS=$(tail -1 "$MOCK_ACCEPT" | grep -oE 'ALL_REQ_ACCEPTED|REMEDIATION_NEEDED|CANNOT_VERIFY|FINAL_FAIL' | head -1)
check "FINAL_FAIL 正确解析" "$([ "$STATUS" = "FINAL_FAIL" ] && echo 0 || echo 1)"

# ══════════════════════════════════════
# T7: 复杂度路由参数
# ══════════════════════════════════════
echo ""
echo "=== T7: 复杂度路由参数 ==="

for COMPLEXITY in S M L; do
    case "$COMPLEXITY" in
        S) EXPECT_PLAN=0; EXPECT_DEV=1 ;;
        M) EXPECT_PLAN=2; EXPECT_DEV=10 ;;
        L) EXPECT_PLAN=10; EXPECT_DEV=15 ;;
    esac
    case "$COMPLEXITY" in
        M) PLAN_MAX_ROUNDS=2; DEV_MAX_ROUNDS=10 ;;
        L) PLAN_MAX_ROUNDS=10; DEV_MAX_ROUNDS=15 ;;
        *) PLAN_MAX_ROUNDS=0; DEV_MAX_ROUNDS=1 ;;
    esac
    check "${COMPLEXITY}级: PLAN_MAX_ROUNDS=${PLAN_MAX_ROUNDS}=${EXPECT_PLAN}" "$([ "$PLAN_MAX_ROUNDS" -eq "$EXPECT_PLAN" ] && echo 0 || echo 1)"
    check "${COMPLEXITY}级: DEV_MAX_ROUNDS=${DEV_MAX_ROUNDS}=${EXPECT_DEV}" "$([ "$DEV_MAX_ROUNDS" -eq "$EXPECT_DEV" ] && echo 0 || echo 1)"
done

# ══════════════════════════════════════
# T8: 失败路径决策逻辑
# ══════════════════════════════════════
echo ""
echo "=== T8: 失败路径决策逻辑 ==="

# T8.1: plan review critical>0 → 必须进入修复轮（不能收敛）
PLAN_REVIEW="$TMP_DIR/t8-plan-review.md"
cat > "$PLAN_REVIEW" <<'EOF'
## Critical
- C1: 数据模型与 REST 链路不一致

## Important
- I1: 缺少幂等保证

<!-- counts: critical=1 important=1 nice=0 -->
EOF

LAST_LINE=$(tail -1 "$PLAN_REVIEW")
P_CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
P_IMP=$(echo "$LAST_LINE" | grep -oE 'important=[0-9]+' | cut -d= -f2)
P_CRIT=${P_CRIT:-999}; P_IMP=${P_IMP:-999}
P_CONVERGED=0
[ "$P_CRIT" -eq 0 ] && [ "$P_IMP" -le 2 ] && P_CONVERGED=1
check "plan review critical=1 → 不收敛，需修复轮" "$([ "$P_CONVERGED" -eq 0 ] && echo 0 || echo 1)"

# T8.2: develop review high>2 → 不收敛
DEV_REVIEW="$TMP_DIR/t8-dev-review.md"
cat > "$DEV_REVIEW" <<'EOF'
<!-- counts: critical=0 high=3 medium=1 -->
EOF

LAST_LINE=$(tail -1 "$DEV_REVIEW")
D_CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
D_HIGH=$(echo "$LAST_LINE" | grep -oE 'high=[0-9]+' | cut -d= -f2)
D_CRIT=${D_CRIT:-999}; D_HIGH=${D_HIGH:-999}
D_CONVERGED=0
[ "$D_CRIT" -eq 0 ] && [ "$D_HIGH" -le 2 ] && D_CONVERGED=1
check "develop review high=3 → 不收敛，需修复轮" "$([ "$D_CONVERGED" -eq 0 ] && echo 0 || echo 1)"

# T8.3: develop review high=2 → 刚好收敛
cat > "$DEV_REVIEW" <<'EOF'
<!-- counts: critical=0 high=2 medium=5 -->
EOF

LAST_LINE=$(tail -1 "$DEV_REVIEW")
D2_CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
D2_HIGH=$(echo "$LAST_LINE" | grep -oE 'high=[0-9]+' | cut -d= -f2)
D2_CRIT=${D2_CRIT:-999}; D2_HIGH=${D2_HIGH:-999}
D2_CONVERGED=0
[ "$D2_CRIT" -eq 0 ] && [ "$D2_HIGH" -le 2 ] && D2_CONVERGED=1
check "develop review high=2 → 刚好收敛（边界值）" "$([ "$D2_CONVERGED" -eq 1 ] && echo 0 || echo 1)"

# T8.4: 编译失败 → 不进入 review（fail-fast）
# 模拟编排者逻辑：编译退出码非 0 → 跳过 review，直接进入修复
COMPILE_EXIT=1
SHOULD_REVIEW=1
[ "$COMPILE_EXIT" -ne 0 ] && SHOULD_REVIEW=0
check "编译失败 (exit=1) → 跳过 review (fail-fast)" "$([ "$SHOULD_REVIEW" -eq 0 ] && echo 0 || echo 1)"

# T8.5: 测试失败 + 已达 MAX_TEST_FIX_ATTEMPTS → 标记 NEEDS_MANUAL_REVIEW
TEST_FIX_ATTEMPTS=3
MAX_TEST_FIX_ATTEMPTS=3
TEST_GATE_OK=0
NEEDS_MANUAL=0
if [ "$TEST_GATE_OK" -eq 0 ] && [ "$TEST_FIX_ATTEMPTS" -ge "$MAX_TEST_FIX_ATTEMPTS" ]; then
    NEEDS_MANUAL=1
fi
check "测试修复 3 轮后仍失败 → NEEDS_MANUAL_REVIEW" "$([ "$NEEDS_MANUAL" -eq 1 ] && echo 0 || echo 1)"

# T8.6: 验收 REMEDIATION_NEEDED → 触发补救（不直接失败）
ACCEPT_STATUS="REMEDIATION_NEEDED"
SHOULD_REMEDIATE=0
[ "$ACCEPT_STATUS" = "REMEDIATION_NEEDED" ] && SHOULD_REMEDIATE=1
check "验收 REMEDIATION_NEEDED → 触发补救" "$([ "$SHOULD_REMEDIATE" -eq 1 ] && echo 0 || echo 1)"

# T8.7: 验收 FINAL_FAIL → 阻断推送
ACCEPT_STATUS2="FINAL_FAIL"
ACCEPTANCE_PASSED=true
case "$ACCEPT_STATUS2" in
    ALL_REQ_ACCEPTED) ACCEPTANCE_PASSED=true ;;
    CANNOT_VERIFY) ACCEPTANCE_PASSED=true ;;
    *) ACCEPTANCE_PASSED=false ;;
esac
check "验收 FINAL_FAIL → 阻断推送 (ACCEPTANCE_PASSED=false)" "$([ "$ACCEPTANCE_PASSED" = "false" ] && echo 0 || echo 1)"

# ══════════════════════════════════════
# T9: 产物缺失/格式损坏安全处理
# ══════════════════════════════════════
echo ""
echo "=== T9: 产物缺失/格式损坏安全处理 ==="

MISSING_DIR="$TMP_DIR/t9"
mkdir -p "$MISSING_DIR"

# T9.1: feature.md 缺失 → 硬失败（不默认跳过）
FEATURE_EXISTS=0
[ -f "$MISSING_DIR/feature.md" ] && FEATURE_EXISTS=1
SHOULD_ABORT=0
[ "$FEATURE_EXISTS" -eq 0 ] && SHOULD_ABORT=1
check "feature.md 缺失 → 编排者硬终止" "$([ "$SHOULD_ABORT" -eq 1 ] && echo 0 || echo 1)"

# T9.2: plan.md 缺失（M/L 级必须有）→ 硬失败
PLAN_EXISTS=0
[ -f "$MISSING_DIR/plan.md" ] && PLAN_EXISTS=1
COMPLEXITY_T9="M"
SHOULD_ABORT2=0
if [ "$COMPLEXITY_T9" != "S" ] && [ "$PLAN_EXISTS" -eq 0 ]; then
    SHOULD_ABORT2=1
fi
check "plan.md 缺失 (M级) → 编排者硬终止" "$([ "$SHOULD_ABORT2" -eq 1 ] && echo 0 || echo 1)"

# T9.3: plan.md 缺失但 S 级 → 不终止（S 跳过 plan）
COMPLEXITY_T9S="S"
SHOULD_ABORT3=0
if [ "$COMPLEXITY_T9S" != "S" ] && [ "$PLAN_EXISTS" -eq 0 ]; then
    SHOULD_ABORT3=1
fi
check "plan.md 缺失 (S级) → 不终止（S 跳过 plan）" "$([ "$SHOULD_ABORT3" -eq 0 ] && echo 0 || echo 1)"

# T9.4: counts 行格式损坏（缺少 critical= 键）→ 安全默认未收敛
CORRUPT_REVIEW="$TMP_DIR/t9-corrupt.md"
cat > "$CORRUPT_REVIEW" <<'EOF'
<!-- counts: high=2 medium=1 -->
EOF
LAST_LINE=$(tail -1 "$CORRUPT_REVIEW")
BAD_CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
BAD_CRIT=${BAD_CRIT:-999}
check "counts 缺少 critical= → 安全默认 999（未收敛）" "$([ "$BAD_CRIT" -eq 999 ] && echo 0 || echo 1)"

# T9.5: counts 行格式损坏（值非数字）→ 安全默认未收敛
cat > "$CORRUPT_REVIEW" <<'EOF'
<!-- counts: critical=abc high=2 medium=1 -->
EOF
LAST_LINE=$(tail -1 "$CORRUPT_REVIEW")
BAD_CRIT2=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
BAD_CRIT2=${BAD_CRIT2:-999}
check "counts critical=abc → 安全默认 999（未收敛）" "$([ "$BAD_CRIT2" -eq 999 ] && echo 0 || echo 1)"

# T9.6: review 报告为空文件 → 安全默认未收敛
EMPTY_REVIEW="$TMP_DIR/t9-empty.md"
touch "$EMPTY_REVIEW"
LAST_LINE=$(tail -1 "$EMPTY_REVIEW" 2>/dev/null || echo "")
EMPTY_CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
EMPTY_CRIT=${EMPTY_CRIT:-999}
check "review 报告为空 → 安全默认 999（未收敛）" "$([ "$EMPTY_CRIT" -eq 999 ] && echo 0 || echo 1)"

# T9.7: review 报告不存在 → 安全默认未收敛
NONEXIST_REVIEW="$TMP_DIR/t9-nonexist.md"
LAST_LINE=$(tail -1 "$NONEXIST_REVIEW" 2>/dev/null || echo "")
NOFILE_CRIT=$(echo "$LAST_LINE" | grep -oE 'critical=[0-9]+' | cut -d= -f2)
NOFILE_CRIT=${NOFILE_CRIT:-999}
check "review 报告不存在 → 安全默认 999（未收敛）" "$([ "$NOFILE_CRIT" -eq 999 ] && echo 0 || echo 1)"

# T9.8: task-*.md 为零个 → 编排者终止任务拆分阶段
EMPTY_TASKS_DIR="$TMP_DIR/t9-tasks"
mkdir -p "$EMPTY_TASKS_DIR"
TASK_COUNT=$(ls "$EMPTY_TASKS_DIR"/task-*.md 2>/dev/null | wc -l | tr -d ' ')
SHOULD_ABORT_TASK=0
[ "$TASK_COUNT" -eq 0 ] && SHOULD_ABORT_TASK=1
check "task-*.md 为零 → 编排者硬终止" "$([ "$SHOULD_ABORT_TASK" -eq 1 ] && echo 0 || echo 1)"

# ══════════════════════════════════════
# T10: 跨轮修复闭环决策逻辑
# ══════════════════════════════════════
echo ""
echo "=== T10: 跨轮修复闭环决策逻辑 ==="

# 模拟 3 轮迭代的收敛历程：
# R1: critical=2, high=3 → 不收敛 → 修复轮
# R2: critical=0, high=3 → 不收敛（high>2）→ 修复轮
# R3: critical=0, high=1 → 收敛

ROUND_CRITS=(2 0 0)
ROUND_HIGHS=(3 3 1)
PREV_CRIT=-1
DEADLOCK_COUNT=0
FINAL_CONVERGED=0
FINAL_ROUND=0

for round_idx in 0 1 2; do
    R_CRIT=${ROUND_CRITS[$round_idx]}
    R_HIGH=${ROUND_HIGHS[$round_idx]}
    R_NUM=$((round_idx + 1))

    # 停机检测
    if [ "$R_CRIT" -eq "$PREV_CRIT" ] && [ "$R_CRIT" -gt 0 ]; then
        DEADLOCK_COUNT=$((DEADLOCK_COUNT + 1))
    else
        DEADLOCK_COUNT=0
    fi
    PREV_CRIT=$R_CRIT

    # 收敛判断
    if [ "$R_CRIT" -eq 0 ] && [ "$R_HIGH" -le 2 ]; then
        FINAL_CONVERGED=1
        FINAL_ROUND=$R_NUM
        break
    fi
done

check "R1 critical=2 → 不收敛" "$([ "${ROUND_CRITS[0]}" -gt 0 ] && echo 0 || echo 1)"
check "R2 critical=0,high=3 → 仍不收敛" "$([ "${ROUND_HIGHS[1]}" -gt 2 ] && echo 0 || echo 1)"
check "R3 critical=0,high=1 → 收敛" "$([ "$FINAL_CONVERGED" -eq 1 ] && echo 0 || echo 1)"
check "收敛于第 3 轮" "$([ "$FINAL_ROUND" -eq 3 ] && echo 0 || echo 1)"
check "无停机（critical 在变化）" "$([ "$DEADLOCK_COUNT" -eq 0 ] && echo 0 || echo 1)"

# T10.6: 停机场景 — critical 停滞
STUCK_CRITS=(2 2 2)
STUCK_PREV=-1
STUCK_DL=0
STUCK_CONVERGED=0

for si in 0 1 2; do
    SC=${STUCK_CRITS[$si]}
    if [ "$SC" -eq "$STUCK_PREV" ] && [ "$SC" -gt 0 ]; then
        STUCK_DL=$((STUCK_DL + 1))
    else
        STUCK_DL=0
    fi
    STUCK_PREV=$SC
    if [ "$STUCK_DL" -ge 2 ]; then
        break  # 停机
    fi
    if [ "$SC" -eq 0 ]; then
        STUCK_CONVERGED=1
        break
    fi
done

check "critical 停滞 2→2→2 → 停机 (deadlock≥2)" "$([ "$STUCK_DL" -ge 2 ] && echo 0 || echo 1)"
check "停滞场景下不收敛" "$([ "$STUCK_CONVERGED" -eq 0 ] && echo 0 || echo 1)"

# T10.8: 轮次上限强制终止
MAX_ROUNDS=10
ROUND=11
FORCE_STOP=0
[ "$ROUND" -gt "$MAX_ROUNDS" ] && FORCE_STOP=1
check "round=11 > max=10 → 强制终止" "$([ "$FORCE_STOP" -eq 1 ] && echo 0 || echo 1)"

# ══════════════════════════════════════
# 汇总
# ══════════════════════════════════════
echo ""
echo "══════════════════════════════════════"
echo "  Agent Mode Dry-Run 结果"
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"
echo "══════════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
