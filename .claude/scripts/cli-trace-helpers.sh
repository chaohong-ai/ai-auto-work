# cli-trace-helpers.sh
# 集中定义 auto-work 系列脚本的 CLI 调用入口，纯 Bash 执行并做 best-effort trace 落盘。
#
# 用法：在 auto-work-loop / feature-plan-loop / feature-develop-loop / research-loop
# 等脚本头部 source 本文件：
#
#     source "$(dirname "$0")/cli-trace-helpers.sh"
#
# 提供：
#   cli_call <prompt> [claude flags...]  — 调 Claude
#   codex_review_exec <prompt>           — 调 Codex review
#   mark_stage <stage> [task] [round]    — 显式标注 trace 阶段
#
# 设计约束：
# - 不重复定义 CLI_CALL_COUNT / CLAUDE_MODEL_FLAG / CODEX_MODEL_FLAG，
#   由调用方脚本自己初始化。本 helper 只在缺省时兜底。
# - cli_call / codex_review_exec 的 stdout 仍透传 CLI 输出，可被 $(...) 捕获或 | tail 管道消费。
# - trace 写盘失败不影响业务退出码。

# ── 代理预设：幂等注入 HTTPS_PROXY/HTTP_PROXY ──
# auto-work 所有子 loop 都会 source 本文件，集中一点确保 claude -p / codex 子进程能出站。
# shellcheck source=./ensure-proxy.sh
source "$(dirname "${BASH_SOURCE[0]}")/ensure-proxy.sh"

# ── 兜底初始化（调用方未设时）──
: "${CLI_CALL_COUNT:=0}"
: "${CLAUDE_MODEL_FLAG:=}"
: "${CODEX_MODEL_FLAG:=}"

__cli_trace_debug() {
    if [ "${AUTO_WORK_TRACE_DEBUG:-0}" = "1" ]; then
        echo "[cli_trace] $*" >&2
    fi
}

__cli_trace_root() {
    if [ -n "${AUTO_WORK_FEATURE_DIR:-}" ]; then
        echo "${AUTO_WORK_FEATURE_DIR}/traces"
    else
        echo ".claude/logs/traces"
    fi
}

__cli_trace_json_escape() {
    local s="${1-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

__cli_trace_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z' | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/'
}

__cli_trace_save_prompt() {
    local root="$1"
    local prompt="$2"
    local sha8="$3"
    local ts="$4"
    local prompts_dir="${root}/prompts"
    mkdir -p "$prompts_dir" 2>/dev/null || return 1
    local safe_ts="${ts//:/}"
    safe_ts="${safe_ts//-/}"
    safe_ts="${safe_ts//+/_}"
    local rel="prompts/${sha8}-${safe_ts}.txt"
    local fpath="${root}/${rel}"
    if [ ! -f "$fpath" ]; then
        printf '%s' "$prompt" > "$fpath" || return 1
    fi
    printf '%s' "$rel"
}

__cli_trace_next_jsonl_path() {
    local root="$1"
    mkdir -p "$root" 2>/dev/null || return 1
    local day base size
    day=$(date '+%Y%m%d')
    base="${root}/${day}.jsonl"
    if [ ! -f "$base" ]; then
        printf '%s' "$base"
        return 0
    fi
    size=$(wc -c < "$base" 2>/dev/null | tr -d ' ')
    if [ -z "$size" ] || [ "$size" -lt 10485760 ]; then
        printf '%s' "$base"
        return 0
    fi
    local n=1 cand cand_size
    while :; do
        cand="${root}/${day}-${n}.jsonl"
        if [ ! -f "$cand" ]; then
            printf '%s' "$cand"
            return 0
        fi
        cand_size=$(wc -c < "$cand" 2>/dev/null | tr -d ' ')
        if [ -z "$cand_size" ] || [ "$cand_size" -lt 10485760 ]; then
            printf '%s' "$cand"
            return 0
        fi
        n=$((n + 1))
    done
}

__cli_trace_sha256() {
    # sha256sum 优先，shasum -a 256 回退，都没有则输出空串
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        echo ""
    fi
}

__cli_trace_model_from_args() {
    local prev=""
    local arg
    for arg in "$@"; do
        if [ "$prev" = "--model" ] || [ "$prev" = "-m" ]; then
            printf '%s' "$arg"
            return 0
        fi
        prev="$arg"
    done
    printf ''
}

__cli_trace_write_record() {
    local cli="$1"
    local prompt="$2"
    local exit_code="$3"
    local duration_ms="$4"
    local output_file="$5"
    shift 5
    local model root trace_file ts sha sha8 prompt_rel stdout_bytes stdout_tail pid
    ts="$(__cli_trace_timestamp)"
    model="$(__cli_trace_model_from_args "$@")"
    root="$(__cli_trace_root)"
    sha=$(printf '%s' "$prompt" | __cli_trace_sha256)
    [ -z "$sha" ] && sha="unknown"
    sha8="${sha:0:8}"
    prompt_rel="$(__cli_trace_save_prompt "$root" "$prompt" "$sha8" "$ts" 2>/dev/null || true)"
    trace_file="$(__cli_trace_next_jsonl_path "$root" 2>/dev/null || true)"
    [ -z "$trace_file" ] && return 0

    stdout_bytes=$(wc -c < "$output_file" 2>/dev/null | tr -d ' ')
    [ -z "$stdout_bytes" ] && stdout_bytes=0
    stdout_tail=$(tail -c 2048 "$output_file" 2>/dev/null || true)
    pid="${BASHPID:-$$}"

    {
        printf '{"ts":"%s",' "$(__cli_trace_json_escape "$ts")"
        printf '"stage":"%s",' "$(__cli_trace_json_escape "${AUTO_WORK_STAGE:-}")"
        printf '"task":"%s",' "$(__cli_trace_json_escape "${AUTO_WORK_TASK:-}")"
        printf '"round":"%s",' "$(__cli_trace_json_escape "${AUTO_WORK_ROUND:-}")"
        printf '"cli":"%s",' "$(__cli_trace_json_escape "$cli")"
        printf '"model":"%s",' "$(__cli_trace_json_escape "$model")"
        printf '"prompt_file":"%s",' "$(__cli_trace_json_escape "$prompt_rel")"
        printf '"prompt_sha256":"%s",' "$(__cli_trace_json_escape "$sha")"
        printf '"prompt_bytes":%s,' "$(printf '%s' "$prompt" | wc -c | tr -d ' ')"
        printf '"exit_code":%s,' "$exit_code"
        printf '"duration_ms":%s,' "$duration_ms"
        printf '"stdout_bytes":%s,' "$stdout_bytes"
        printf '"stdout_tail":"%s",' "$(__cli_trace_json_escape "$stdout_tail")"
        printf '"feature_dir":"%s",' "$(__cli_trace_json_escape "${AUTO_WORK_FEATURE_DIR:-}")"
        printf '"pid":%s' "$pid"
        printf '}\n'
    } >> "$trace_file" 2>/dev/null || true
}

__cli_trace_run() {
    local cli="$1"
    local prompt="$2"
    shift 2

    local tmp_output
    tmp_output=$(mktemp 2>/dev/null || mktemp -t cli-trace-output) || return 1

    local start_ms end_ms duration_ms exit_code
    start_ms=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
    __cli_trace_debug "exec: ${cli} stage=${AUTO_WORK_STAGE:-} task=${AUTO_WORK_TASK:-} round=${AUTO_WORK_ROUND:-}"

    if [ "$cli" = "claude" ]; then
        # 直接重定向到文件，避免 tee 管道的 TTY 依赖，支持后台/无头运行
        # shellcheck disable=SC2086
        claude -p "$prompt" "$@" > "$tmp_output" 2>&1
        exit_code=$?
        cat "$tmp_output"
    else
        # shellcheck disable=SC2086
        codex exec --full-auto "$@" "$prompt" 2>&1 | tee "$tmp_output"
        exit_code=${PIPESTATUS[0]}
    fi

    end_ms=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
    duration_ms=$((end_ms - start_ms))
    __cli_trace_write_record "$cli" "$prompt" "$exit_code" "$duration_ms" "$tmp_output" "$@" || true
    rm -f "$tmp_output"
    __cli_trace_debug "done: exit=${exit_code} duration_ms=${duration_ms}"
    return "$exit_code"
}

# cli_call <prompt> [claude flags...]
cli_call() {
    CLI_CALL_COUNT=$((CLI_CALL_COUNT + 1))
    local prompt="$1"
    shift
    # shellcheck disable=SC2086
    __cli_trace_run claude "$prompt" "$@" $CLAUDE_MODEL_FLAG
}

# codex_review_exec <prompt>
# Falls back to claude -p when CODEX_AVAILABLE=0 (rate-limited or unavailable).
codex_review_exec() {
    CLI_CALL_COUNT=$((CLI_CALL_COUNT + 1))
    local prompt="$1"
    if [ "${CODEX_AVAILABLE:-1}" = "0" ]; then
        echo "[codex_review_exec] Codex 不可用，降级为 claude -p review" >&2
        # shellcheck disable=SC2086
        __cli_trace_run claude "$prompt" --permission-mode bypassPermissions $CLAUDE_MODEL_FLAG
    else
        # shellcheck disable=SC2086
        __cli_trace_run codex "$prompt" $CODEX_MODEL_FLAG
    fi
}

# mark_stage <stage> [task] [round]
# 显式标注本进程后续 cli_call / codex_review_exec 的 trace 上下文。
# 子进程通过环境变量继承；不传的位置用空串覆盖，避免上一阶段污染。
mark_stage() {
    export AUTO_WORK_STAGE="${1:-}"
    export AUTO_WORK_TASK="${2:-}"
    export AUTO_WORK_ROUND="${3:-}"
}

# preflight_check [--require-codex]
#
# 验证 auto-work 系列脚本的运行环境。失败时输出诊断并 return 1。
# 调用方可据此决定 exit 或降级。
#
# 失败分类（通过 PREFLIGHT_FAIL 导出）：
#   missing_dep — claude/codex 不在 PATH
#   sandbox     — 子进程被系统/沙箱拦截（EPERM, uv_spawn 等）
#   auth        — 认证/OAuth 失败
#   wrapper     — 其他非零退出
#
# 用法：
#   preflight_check --require-codex || exit 1   # auto-work（需要 codex）
#   preflight_check || exit 1                   # 仅检查 claude
preflight_check() {
    # 父进程已通过时跳过（避免子脚本重复冒烟）
    if [ "${__PREFLIGHT_PASSED:-0}" = "1" ]; then
        return 0
    fi

    local require_codex=0
    [ "${1:-}" = "--require-codex" ] && require_codex=1

    PREFLIGHT_FAIL=""

    # 1. PATH 存在性
    if ! command -v claude >/dev/null 2>&1; then
        PREFLIGHT_FAIL="missing_dep"
        echo "PREFLIGHT FAIL [missing_dep]: claude 不在 PATH 中" >&2
        echo "  PATH=${PATH}" >&2
    fi
    if [ "$require_codex" = 1 ] && ! command -v codex >/dev/null 2>&1; then
        PREFLIGHT_FAIL="missing_dep"
        echo "PREFLIGHT FAIL [missing_dep]: codex 不在 PATH 中" >&2
    fi

    # 2. claude -p 端到端冒烟（参数与 cli_call 实际调用对齐）
    if [ -z "$PREFLIGHT_FAIL" ]; then
        echo "PREFLIGHT: 测试 claude -p 子进程..." >&2
        local tmp_file tmp_body tmp_exit
        tmp_file=$(mktemp 2>/dev/null || mktemp -t preflight)
        # 拼装与 cli_call 一致的参数：CLAUDE_MODEL_FLAG + bypassPermissions
        # shellcheck disable=SC2086
        if claude -p "reply OK" --permission-mode bypassPermissions $CLAUDE_MODEL_FLAG > "$tmp_file" 2>&1; then
            echo "PREFLIGHT OK: claude -p 成功" >&2
        else
            tmp_exit=$?
            tmp_body=$(cat "$tmp_file")
            if echo "$tmp_body" | grep -qi "EPERM\|uv_spawn\|spawn.*denied\|Access is denied"; then
                PREFLIGHT_FAIL="sandbox"
                echo "PREFLIGHT FAIL [sandbox]: 子进程被系统/沙箱拦截 (exit=${tmp_exit})" >&2
                echo "  输出: $(head -c 500 "$tmp_file")" >&2
                echo "  当前 shell 可能运行在受限 agent 环境中" >&2
            elif echo "$tmp_body" | grep -qi "401\|403\|auth\|OAuth\|token\|unauthorized"; then
                PREFLIGHT_FAIL="auth"
                echo "PREFLIGHT FAIL [auth]: 认证失败 (exit=${tmp_exit})" >&2
                echo "  输出: $(head -c 500 "$tmp_file")" >&2
            else
                PREFLIGHT_FAIL="wrapper"
                echo "PREFLIGHT FAIL [wrapper]: 非零退出 (exit=${tmp_exit})" >&2
                echo "  输出: $(head -c 500 "$tmp_file")" >&2
            fi
        fi
        rm -f "$tmp_file"
    fi

    # 3. codex API 冒烟测试（--help 不够，必须验证 API 可达）
    if [ -z "$PREFLIGHT_FAIL" ] && [ "$require_codex" = 1 ]; then
        if ! command -v codex >/dev/null 2>&1; then
            echo "PREFLIGHT WARN: codex 不在 PATH，review 将降级为 claude -p" >&2
            export CODEX_AVAILABLE=0
        else
            local codex_tmp
            codex_tmp=$(mktemp 2>/dev/null || mktemp -t preflight-codex)
            # 发送最小 prompt 验证 API 可达（非 --help）
            if codex exec --full-auto "reply OK" > "$codex_tmp" 2>&1; then
                echo "PREFLIGHT OK: codex API 可达" >&2
                export CODEX_AVAILABLE=1
            else
                local codex_out
                codex_out=$(cat "$codex_tmp")
                if echo "$codex_out" | grep -qi "usage limit\|rate.limit\|quota\|429\|try again"; then
                    echo "PREFLIGHT WARN: codex API 触达用量限制，review 将降级为 claude -p" >&2
                    export CODEX_AVAILABLE=0
                else
                    echo "PREFLIGHT WARN: codex API 测试失败，review 将降级为 claude -p" >&2
                    export CODEX_AVAILABLE=0
                fi
            fi
            rm -f "$codex_tmp"
        fi
    fi

    # 4. trace 依赖（非阻断）— 验证 __cli_trace_sha256 实际可工作
    if [ -z "$(echo test | __cli_trace_sha256)" ]; then
        echo "PREFLIGHT WARN: sha256sum/shasum 均不可用，trace 的 prompt_sha256 将为 unknown" >&2
    fi

    if [ -n "$PREFLIGHT_FAIL" ]; then
        export PREFLIGHT_FAIL
        return 1
    fi
    # 标记已通过，子脚本继承后可跳过
    export __PREFLIGHT_PASSED=1
    echo "PREFLIGHT: 全部通过" >&2
    return 0
}
