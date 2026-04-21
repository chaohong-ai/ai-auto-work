#!/bin/bash
# 本地烟雾测试 cli-trace helper 的 11 项核心场景。
# 纯 Bash fake "claude" / "codex" 脚本覆盖 PATH，不依赖 Python。
#
# 用法: bash .claude/scripts/_test_cli_trace.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t cli-trace-test)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"

# ── fake claude：解析 -p 后的 prompt，回显多行，可控退出码 ──
cat > "$TMP_DIR/bin/claude" <<'FAKE_EOF'
#!/bin/bash
prompt=""
while [ $# -gt 0 ]; do
    case "$1" in
        -p) shift; prompt="$1" ;;
    esac
    shift
done
echo "FAKE-CLAUDE-LINE-1: prompt_len=${#prompt}"
echo "FAKE-CLAUDE-LINE-2: first20=${prompt:0:20}"
echo "FAKE-CLAUDE-LINE-3: last20=${prompt: -20}"
echo "COMMIT_SUCCESS"
exit "${FAKE_EXIT:-0}"
FAKE_EOF
chmod +x "$TMP_DIR/bin/claude"

# ── fake codex：最后一个 positional arg 是 prompt ──
cat > "$TMP_DIR/bin/codex" <<'FAKE_EOF'
#!/bin/bash
# 支持 --help（preflight 轻量检查用）
if [ "${1:-}" = "--help" ]; then
    echo "fake codex help"
    exit 0
fi
# exec --full-auto [-m X] <prompt>: 最后一个参数是 prompt
last=""
while [ $# -gt 0 ]; do
    last="$1"
    shift
done
echo "FAKE-CODEX-LINE-1: prompt_len=${#last}"
echo "<!-- counts: critical=0 important=1 nice=2 -->"
exit "${FAKE_EXIT:-0}"
FAKE_EOF
chmod +x "$TMP_DIR/bin/codex"

# fake 覆盖 PATH（放最前面，优先命中）
export PATH="$TMP_DIR/bin:$PATH"

# 跳过 preflight 冒烟（fake 不是真 CLI）
export __PREFLIGHT_PASSED=1

# 清理已废弃的 Python wrapper 环境变量
unset CLI_TRACE_CLAUDE_BIN CLI_TRACE_CODEX_BIN 2>/dev/null || true

export AUTO_WORK_FEATURE_DIR="$TMP_DIR/feature"
export AUTO_WORK_STAGE="test-stage"
export AUTO_WORK_TASK="task-test"
mkdir -p "$AUTO_WORK_FEATURE_DIR"

# 加载 helper
source "$SCRIPT_DIR/cli-trace-helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0
report() {
    local name="$1"; local result="$2"; local detail="${3:-}"
    if [ "$result" = "PASS" ]; then
        echo "  PASS  ${name}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  ${name}: $detail"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "══════════════════════════════════════"
echo "  cli-trace helper 烟雾测试（纯 Bash）"
echo "══════════════════════════════════════"

# ── ① stdout 实时透传 + 4 行干净捕获 ──
echo ""
echo "[1] stdout 实时透传 + 干净捕获"
out=$(cli_call "test prompt content" 2>&1)
exit1=$?
line_count=$(echo "$out" | wc -l | tr -d ' ')
if [ "$exit1" = "0" ] && echo "$out" | grep -q "COMMIT_SUCCESS"; then
    report "stdout 包含 COMMIT_SUCCESS" PASS
else
    report "stdout 流式透传" FAIL "exit=$exit1, output=$out"
fi
if [ "$line_count" = "4" ]; then
    report "捕获 4 行（无 trace 噪音）" PASS
else
    report "捕获行数=$line_count（应为 4）" FAIL "$out"
fi

# ── ② grep 解析仍可用（验证 $(...) 对 grep 的兼容）──
echo ""
echo "[2] captured 内容可被 grep -oE 解析"
captured=$(cli_call "second prompt" 2>&1)
parsed=$(echo "$captured" | grep -oE 'FAKE-CLAUDE-LINE-1' | head -1)
if [ "$parsed" = "FAKE-CLAUDE-LINE-1" ]; then
    report "grep 解析 captured 成功" PASS
else
    report "grep 解析" FAIL "captured=$captured"
fi

# ── ③ 退出码透传 ──
echo ""
echo "[3] 退出码透传"
FAKE_EXIT=42 cli_call "exit test" >/dev/null 2>&1
real_exit=$?
if [ "$real_exit" = "42" ]; then
    report "CLI 退出码=42 被透传" PASS
else
    report "退出码透传" FAIL "expected 42, got $real_exit"
fi

# ── ④ trace 写盘失败不污染主流程 ──
echo ""
echo "[4] trace 写盘失败不污染主流程"
broken_root="$TMP_DIR/broken-root"
touch "$broken_root"  # 文件占位，使得 mkdir traces 失败
AUTO_WORK_FEATURE_DIR="$broken_root" cli_call "trace fail test" >/dev/null 2>&1
broken_exit=$?
if [ "$broken_exit" = "0" ]; then
    report "trace 写盘失败时仍返回 CLI 退出码=0" PASS
else
    report "trace 写盘失败处理" FAIL "exit=$broken_exit"
fi

# ── ⑤ 长 prompt（10KB）传输完整 ──
echo ""
echo "[5] 长 prompt（10KB）传输完整"
long_prompt=$(head -c 10000 /dev/zero | tr '\0' 'A')
captured_long=$(cli_call "$long_prompt" 2>&1)
reported_len=$(echo "$captured_long" | grep -oE 'prompt_len=[0-9]+' | head -1 | sed 's/prompt_len=//')
if [ "$reported_len" = "10000" ]; then
    report "10KB prompt 完整传输 (len=$reported_len)" PASS
else
    report "10KB prompt 传输" FAIL "got len=$reported_len, expected 10000"
fi

# ── ⑥ codex_review_exec 后台 + 文件重定向 ──
echo ""
echo "[6] codex_review_exec 后台 + 文件重定向"
codex_review_exec "codex bg test prompt" > "$TMP_DIR/codex_out.txt" 2>&1 &
pid=$!
wait "$pid"
codex_exit=$?
if [ "$codex_exit" = "0" ] && grep -q "FAKE-CODEX" "$TMP_DIR/codex_out.txt"; then
    report "codex 后台运行 + 文件输出" PASS
else
    report "codex 后台运行" FAIL "exit=$codex_exit, content=$(cat "$TMP_DIR/codex_out.txt" 2>/dev/null)"
fi

# ── ⑦ 3 路并发 codex_review_exec 各自落 trace ──
echo ""
echo "[7] 3 路并发 codex_review_exec PID 不同"
codex_review_exec "parallel-prompt-1" > "$TMP_DIR/p1.txt" 2>&1 &
pid1=$!
codex_review_exec "parallel-prompt-2" > "$TMP_DIR/p2.txt" 2>&1 &
pid2=$!
codex_review_exec "parallel-prompt-3" > "$TMP_DIR/p3.txt" 2>&1 &
pid3=$!
wait "$pid1" "$pid2" "$pid3"
parallel_all_ok=1
for f in p1 p2 p3; do
    if ! grep -q "FAKE-CODEX" "$TMP_DIR/${f}.txt"; then
        parallel_all_ok=0
    fi
done
if [ "$parallel_all_ok" = "1" ]; then
    report "3 路并发各自完成" PASS
else
    report "3 路并发完成" FAIL
fi
trace_file=$(ls -t "$AUTO_WORK_FEATURE_DIR"/traces/*.jsonl 2>/dev/null | head -1)
if [ -n "${trace_file:-}" ]; then
    # 纯 grep 提取最后 3 条 trace 的 pid，统计去重数
    distinct_pids=$(tail -3 "$trace_file" | grep -oE '"pid":[0-9]+' | sort -u | wc -l | tr -d ' ')
    if [ "$distinct_pids" = "3" ]; then
        report "3 路并发 trace 各 PID 不同" PASS
    else
        report "3 路并发 PID" FAIL "distinct_pids=$distinct_pids"
    fi
fi

# ── ⑧ JSONL 字段完整性 + stage env 透传 ──
echo ""
echo "[8] JSONL 字段完整性 + stage env 透传"
if [ -n "${trace_file:-}" ]; then
    last_record=$(tail -1 "$trace_file")
    required_fields="ts stage task cli model prompt_file prompt_sha256 prompt_bytes exit_code duration_ms stdout_bytes pid"
    missing=""
    for f in $required_fields; do
        if ! echo "$last_record" | grep -q "\"$f\""; then
            missing="$missing $f"
        fi
    done
    if [ -z "$missing" ]; then
        report "所有必需字段存在" PASS
    else
        report "字段完整性" FAIL "missing:$missing"
    fi
    # 新 helpers 输出无空格 JSON: "stage":"test-stage"
    if echo "$last_record" | grep -q '"stage":"test-stage"'; then
        report "stage 字段从 env 正确传入" PASS
    else
        report "stage 字段传递" FAIL "$last_record"
    fi
fi

# ── ⑨ mark_stage 切换 ──
echo ""
echo "[9] mark_stage 切换 stage"
mark_stage "stage-A" "task-A" "1"
cli_call "ma test" >/dev/null 2>&1
mark_stage "stage-B" "task-B" "2"
cli_call "mb test" >/dev/null 2>&1
# 纯 grep + sed 提取最后 2 条 trace 的 stage 字段
last_2_stages=$(tail -2 "$trace_file" | grep -oE '"stage":"[^"]*"' | sed 's/"stage":"//;s/"//')
stage_csv=$(echo "$last_2_stages" | paste -sd, -)
if [ "$stage_csv" = "stage-A,stage-B" ]; then
    report "mark_stage 切换生效" PASS
else
    report "mark_stage 切换" FAIL "stages=$stage_csv"
fi

# ── ⑩ preflight_check 失败分类 ──
echo ""
echo "[10] preflight_check 失败分类"

# 10a: missing_dep — claude 不在 PATH
pf_result=$(
    export PATH="/nonexistent"
    export __PREFLIGHT_PASSED=0
    PREFLIGHT_FAIL=""
    preflight_check 2>/dev/null || true
    echo "$PREFLIGHT_FAIL"
)
if [ "$pf_result" = "missing_dep" ]; then
    report "preflight: PATH 缺失 → missing_dep" PASS
else
    report "preflight: missing_dep 分类" FAIL "got=$pf_result"
fi

# 10b: sandbox — fake claude 输出 EPERM 关键字
cat > "$TMP_DIR/bin/claude-eperm" <<'FAKE_EOF'
#!/bin/bash
echo "Error: EPERM: uv_spawn C:\\Windows\\System32\\reg.exe"
exit 1
FAKE_EOF
chmod +x "$TMP_DIR/bin/claude-eperm"
pf_result=$(
    # 用 eperm fake 覆盖 claude
    cp "$TMP_DIR/bin/claude-eperm" "$TMP_DIR/bin/claude"
    export __PREFLIGHT_PASSED=0
    PREFLIGHT_FAIL=""
    CLAUDE_MODEL_FLAG=""
    preflight_check 2>/dev/null || true
    echo "$PREFLIGHT_FAIL"
)
# 恢复正常 fake
cat > "$TMP_DIR/bin/claude" <<'FAKE_EOF'
#!/bin/bash
prompt=""
while [ $# -gt 0 ]; do
    case "$1" in
        -p) shift; prompt="$1" ;;
    esac
    shift
done
echo "FAKE-CLAUDE-LINE-1: prompt_len=${#prompt}"
echo "FAKE-CLAUDE-LINE-2: first20=${prompt:0:20}"
echo "FAKE-CLAUDE-LINE-3: last20=${prompt: -20}"
echo "COMMIT_SUCCESS"
exit "${FAKE_EXIT:-0}"
FAKE_EOF
chmod +x "$TMP_DIR/bin/claude"
if [ "$pf_result" = "sandbox" ]; then
    report "preflight: EPERM 输出 → sandbox" PASS
else
    report "preflight: sandbox 分类" FAIL "got=$pf_result"
fi

# 10c: auth — fake claude 输出 401/unauthorized
cat > "$TMP_DIR/bin/claude-auth" <<'FAKE_EOF'
#!/bin/bash
echo "Error: 401 unauthorized"
exit 1
FAKE_EOF
chmod +x "$TMP_DIR/bin/claude-auth"
pf_result=$(
    cp "$TMP_DIR/bin/claude-auth" "$TMP_DIR/bin/claude"
    export __PREFLIGHT_PASSED=0
    PREFLIGHT_FAIL=""
    CLAUDE_MODEL_FLAG=""
    preflight_check 2>/dev/null || true
    echo "$PREFLIGHT_FAIL"
)
# 恢复正常 fake
cat > "$TMP_DIR/bin/claude" <<'FAKE_EOF'
#!/bin/bash
prompt=""
while [ $# -gt 0 ]; do
    case "$1" in
        -p) shift; prompt="$1" ;;
    esac
    shift
done
echo "FAKE-CLAUDE-LINE-1: prompt_len=${#prompt}"
echo "FAKE-CLAUDE-LINE-2: first20=${prompt:0:20}"
echo "FAKE-CLAUDE-LINE-3: last20=${prompt: -20}"
echo "COMMIT_SUCCESS"
exit "${FAKE_EXIT:-0}"
FAKE_EOF
chmod +x "$TMP_DIR/bin/claude"
if [ "$pf_result" = "auth" ]; then
    report "preflight: 401 输出 → auth" PASS
else
    report "preflight: auth 分类" FAIL "got=$pf_result"
fi

# ── ⑪ __cli_trace_sha256 回退 ──
echo ""
echo "[11] __cli_trace_sha256 回退"
sha_out=$(echo "hello" | __cli_trace_sha256)
if [ -n "$sha_out" ] && [ ${#sha_out} -eq 64 ]; then
    report "sha256 输出 64 字符 hex" PASS
else
    report "sha256 输出" FAIL "got=${sha_out} len=${#sha_out}"
fi

echo ""
echo "══════════════════════════════════════"
echo "  结果: PASS=${PASS_COUNT}  FAIL=${FAIL_COUNT}"
echo "══════════════════════════════════════"

[ "$FAIL_COUNT" = "0" ]
