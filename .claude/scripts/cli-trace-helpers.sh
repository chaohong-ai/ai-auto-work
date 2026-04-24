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
    local model root trace_file ts sha sha8 prompt_rel prompt_bytes stdout_bytes stdout_tail pid
    local estimated_input_tokens estimated_output_tokens estimated_total_tokens
    ts="$(__cli_trace_timestamp)"
    model="$(__cli_trace_model_from_args "$@")"
    root="$(__cli_trace_root)"
    sha=$(printf '%s' "$prompt" | __cli_trace_sha256)
    [ -z "$sha" ] && sha="unknown"
    sha8="${sha:0:8}"
    prompt_rel="$(__cli_trace_save_prompt "$root" "$prompt" "$sha8" "$ts" 2>/dev/null || true)"
    trace_file="$(__cli_trace_next_jsonl_path "$root" 2>/dev/null || true)"
    [ -z "$trace_file" ] && return 0

    prompt_bytes=$(printf '%s' "$prompt" | wc -c | tr -d ' ')
    [ -z "$prompt_bytes" ] && prompt_bytes=0
    stdout_bytes=$(wc -c < "$output_file" 2>/dev/null | tr -d ' ')
    [ -z "$stdout_bytes" ] && stdout_bytes=0
    # Best-effort estimate only: current CLI output does not expose provider usage.
    # Use bytes/4 as a stable approximation and keep the field name explicit.
    estimated_input_tokens=$(((prompt_bytes + 3) / 4))
    estimated_output_tokens=$(((stdout_bytes + 3) / 4))
    estimated_total_tokens=$((estimated_input_tokens + estimated_output_tokens))
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
        printf '"prompt_bytes":%s,' "$prompt_bytes"
        printf '"estimated_input_tokens":%s,' "$estimated_input_tokens"
        printf '"exit_code":%s,' "$exit_code"
        printf '"duration_ms":%s,' "$duration_ms"
        printf '"stdout_bytes":%s,' "$stdout_bytes"
        printf '"estimated_output_tokens":%s,' "$estimated_output_tokens"
        printf '"estimated_total_tokens":%s,' "$estimated_total_tokens"
        printf '"token_estimate_source":"bytes_div_4",'
        printf '"stdout_tail":"%s",' "$(__cli_trace_json_escape "$stdout_tail")"
        printf '"feature_dir":"%s",' "$(__cli_trace_json_escape "${AUTO_WORK_FEATURE_DIR:-}")"
        printf '"pid":%s' "$pid"
        printf '}\n'
    } >> "$trace_file" 2>/dev/null || true
}

# ── Claude 速率限制处理 ──
#
# Anthropic Claude CLI 在用量上限时输出形如
#   "You've hit your limit · resets 1am (Asia/Shanghai)"
# 然后非零退出。auto-work 此前直接报错终止，过了 reset 时间也不会自动恢复。
#
# 本节实现：
#   1. __parse_claude_rate_limit_wait <text-file>
#         成功识别速率限制并解析出 reset 时间 → 输出"等待秒数"到 stdout
#         未识别 → 输出空串
#   2. __cli_trace_run 内 claude 分支检测到速率限制后：
#         sleep 到 reset + 缓冲 → 自动重试同一 prompt
#         **默认无限重试**，直到成功或调用方 Ctrl+C / kill 进程
#         非速率限制的失败（5xx / 网络 / auth）立即返回原 exit code
#
# 配置开关（环境变量，**全部为可选 opt-in**）：
#   AUTO_WORK_RATE_LIMIT_MAX_RETRIES   ≥1 时启用次数上限；默认 0 表示无限
#   AUTO_WORK_RATE_LIMIT_MAX_WAIT      ≥1 时启用单次等待秒数上限；默认 0 表示不截断
#   AUTO_WORK_RATE_LIMIT_BUFFER        reset 时间外加缓冲秒数；默认 60
#   AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT 命中关键字但解析不到时间时的兜底等待；默认 600
#   AUTO_WORK_RATE_LIMIT_DISABLE       置 1 完全关闭本机制（恢复旧"立即失败"行为，仅排障用）

# 解析 claude -p stdout 中的 "You've hit your limit · resets X (TZ)" 形式，
# 输出本进程当前时间到 reset 时刻所需等待的秒数（含缓冲）。
# 未匹配到 → 输出空串。
#
# 支持的时间格式：
#   "1am" / "12pm" / "12:30am" / "13:45"（24h 制）
# 时区识别：括号内 IANA 名（Asia/Shanghai、UTC、America/Los_Angeles 等）；
# 缺省时按本机时区解析。
# 内部：用 GNU date 把 (time_str, tz_str, qualifier) 转换为 epoch；失败返回空串。
# qualifier 例："today" / "tomorrow" / ""（绝对日期串本身已含日期，无需 today）。
__compute_reset_epoch() {
    local time_str="$1" tz_str="$2" qualifier="$3"
    local expr="$time_str"
    [ -n "$qualifier" ] && expr="$time_str $qualifier"
    local epoch
    if [ -n "$tz_str" ]; then
        epoch=$(TZ="$tz_str" date -d "$expr" +%s 2>/dev/null) || epoch=""
    else
        epoch=$(date -d "$expr" +%s 2>/dev/null) || epoch=""
    fi
    printf '%s' "$epoch"
}

__parse_claude_rate_limit_wait() {
    local file="$1"
    [ -f "$file" ] || return 0
    local body
    body=$(cat "$file" 2>/dev/null) || return 0

    # 必须命中限流类关键字才进入解析。覆盖语序变体：
    # - "hit your usage limit" / "hit your limit"
    # - "usage limit reached" / "usage limit hit" / "usage limit exceeded"
    # - "rate limit" / "ratelimit"
    # - "quota"
    # - "try again at" 紧贴在限流上下文里（多数 Anthropic 文案以此短语开始绝对时间）
    if ! printf '%s' "$body" | grep -qiE "(usage|rate).?limit|hit (your )?limit|quota|try again at "; then
        return 0
    fi

    local fallback="${AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT:-600}"
    local now_epoch reset_epoch absolute_form="" time_str="" tz_str=""
    now_epoch=$(date +%s)

    # ── 形态 A：absolute date — "try again at Apr 14th, 2026 1:50 AM (UTC)" ──
    # Anthropic 真实文案历史出现过此格式，含完整日期，无需 today/tomorrow 推断。
    # 提取规则：try again at <Month> <Day>(st|nd|rd|th)?, <Year> <H>(:MM)? AM|PM [(<TZ>)]
    local abs_line
    abs_line=$(printf '%s' "$body" | grep -oiE "try again at +[A-Za-z]+ +[0-9]{1,2}(st|nd|rd|th)?, *[0-9]{4} +[0-9]{1,2}(:[0-9]{2})? *(am|pm)[^[:alnum:]_/-]*(\([^)]+\))?" | head -n 1)
    if [ -n "$abs_line" ]; then
        # 去除 "1st/2nd/3rd/14th" 中的序数后缀；GNU date 不识别它们
        absolute_form=$(printf '%s' "$abs_line" | sed -E 's/^try again at +//I; s/([0-9])(st|nd|rd|th)/\1/Ig; s/[[:space:]]*\([^)]+\)$//')
        tz_str=$(printf '%s' "$abs_line" | sed -nE 's/.*\(([^)]+)\).*/\1/p' | head -n 1)
        reset_epoch=$(__compute_reset_epoch "$absolute_form" "$tz_str" "")
        if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now_epoch" ]; then
            local buffer="${AUTO_WORK_RATE_LIMIT_BUFFER:-60}"
            local w=$((reset_epoch - now_epoch + buffer))
            [ "$w" -lt 1 ] && w="$fallback"
            printf '%s' "$w"
            return 0
        fi
        # 命中绝对形态但日期无法 parse → fallback；不要静默失败
        printf '%s' "$fallback"
        return 0
    fi

    # ── 形态 B：relative time-of-day — "resets 1am (Asia/Shanghai)" / "resets 13:30 (UTC)" ──
    local resets_line
    resets_line=$(printf '%s' "$body" | grep -oiE "reset[s]? +[0-9]{1,2}(:[0-9]{2})?(am|pm)?[^[:alnum:]_/-]*\([^)]+\)" | head -n 1)
    if [ -z "$resets_line" ]; then
        # 命中关键字但无任何 reset 时间：兜底等保守值循环重试
        printf '%s' "$fallback"
        return 0
    fi
    time_str=$(printf '%s' "$resets_line" | grep -oiE "[0-9]{1,2}(:[0-9]{2})?(am|pm)?" | head -n 1)
    tz_str=$(printf '%s' "$resets_line" | sed -nE 's/.*\(([^)]+)\).*/\1/p' | head -n 1)
    if [ -z "$time_str" ]; then
        # 形态匹配但提不出时间 → fallback（防御性，不应到达）
        printf '%s' "$fallback"
        return 0
    fi

    # 先按 today 试，已过则按 tomorrow；任何失败都退到 fallback（关键 fix:
    # 旧代码在第一次解析失败时直接 return 0 输出空串，外层把它当非限流错误立即放弃）
    reset_epoch=$(__compute_reset_epoch "$time_str" "$tz_str" "today")
    if [ -z "$reset_epoch" ]; then
        printf '%s' "$fallback"
        return 0
    fi
    if [ "$reset_epoch" -le "$now_epoch" ]; then
        reset_epoch=$(__compute_reset_epoch "$time_str" "$tz_str" "tomorrow")
    fi
    if [ -z "$reset_epoch" ]; then
        printf '%s' "$fallback"
        return 0
    fi

    local buffer="${AUTO_WORK_RATE_LIMIT_BUFFER:-60}"
    local wait_seconds=$((reset_epoch - now_epoch + buffer))
    # 防御：时区漂移导致负值时退到 fallback
    if [ "$wait_seconds" -lt 1 ]; then
        wait_seconds="$fallback"
    fi
    printf '%s' "$wait_seconds"
}

# 把秒数格式化为可读字符串（用于日志）
__format_wait_secs() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
    elif [ "$s" -ge 60 ]; then
        printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
    else
        printf '%ds' "$s"
    fi
}

__cli_trace_run() {
    local cli="$1"
    local prompt="$2"
    shift 2

    local tmp_output
    tmp_output=$(mktemp 2>/dev/null || mktemp -t cli-trace-output) || return 1

    # 0 = 无限制 / 不截断；调用方按需 opt-in
    local max_retries="${AUTO_WORK_RATE_LIMIT_MAX_RETRIES:-0}"
    local max_wait="${AUTO_WORK_RATE_LIMIT_MAX_WAIT:-0}"
    local rl_disabled="${AUTO_WORK_RATE_LIMIT_DISABLE:-0}"
    local attempt=0

    # SIGINT/SIGTERM 在 sleep 期间应能立即中断，bash 默认即满足；
    # 此处不安装 trap，让信号自然传播终结整个 auto-work 进程组。

    while :; do
        local start_ms end_ms duration_ms exit_code
        start_ms=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
        __cli_trace_debug "exec: ${cli} stage=${AUTO_WORK_STAGE:-} task=${AUTO_WORK_TASK:-} round=${AUTO_WORK_ROUND:-} attempt=${attempt}"

        # 两个分支统一用直接重定向到文件 + cat 回放：
        # - 避免 tee 管道的 TTY 依赖，支持后台/无头运行（main: thin-client 引入）
        # - 父脚本使用 set -e，用 `|| exit_code=$?` 吞掉非零退出后再继续，
        #   否则 claude 403/rate-limit 会直接炸穿整条 feature-develop-loop
        if [ "$cli" = "claude" ]; then
            exit_code=0
            # shellcheck disable=SC2086
            claude -p "$prompt" "$@" > "$tmp_output" 2>&1 || exit_code=$?
            cat "$tmp_output"
        else
            exit_code=0
            # shellcheck disable=SC2086
            codex exec --full-auto "$@" "$prompt" > "$tmp_output" 2>&1 || exit_code=$?
            cat "$tmp_output"
        fi

        end_ms=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
        duration_ms=$((end_ms - start_ms))
        __cli_trace_write_record "$cli" "$prompt" "$exit_code" "$duration_ms" "$tmp_output" "$@" || true

        # 速率限制检测：仅 claude 分支启用（codex 已有自有 fallback 逻辑）
        if [ "$exit_code" -ne 0 ] && [ "$cli" = "claude" ] && [ "$rl_disabled" != "1" ]; then
            local wait_secs
            wait_secs=$(__parse_claude_rate_limit_wait "$tmp_output")
            if [ -n "$wait_secs" ] && [ "$wait_secs" -gt 0 ]; then
                attempt=$((attempt + 1))

                # 仅在显式设置 MAX_RETRIES 时启用次数封顶
                if [ "$max_retries" -gt 0 ] && [ "$attempt" -gt "$max_retries" ]; then
                    echo "" >&2
                    echo "  [RATE_LIMIT] 已重试 $((attempt - 1)) 次仍命中速率限制，达到 MAX_RETRIES=${max_retries}，放弃" >&2
                    rm -f "$tmp_output"
                    __cli_trace_debug "give-up: exit=${exit_code} attempts=${attempt}"
                    return "$exit_code"
                fi

                # 仅在显式设置 MAX_WAIT 时截断单次等待
                if [ "$max_wait" -gt 0 ] && [ "$wait_secs" -gt "$max_wait" ]; then
                    echo "  [RATE_LIMIT] 解析到等待 $(__format_wait_secs "$wait_secs")，超过 MAX_WAIT $(__format_wait_secs "$max_wait")，截断到上限" >&2
                    wait_secs="$max_wait"
                fi

                local retry_label
                if [ "$max_retries" -gt 0 ]; then
                    retry_label="attempt ${attempt}/${max_retries}"
                else
                    retry_label="attempt ${attempt} (no cap)"
                fi
                echo "" >&2
                echo "  [RATE_LIMIT] claude -p 命中速率上限 (${retry_label})；" >&2
                echo "  [RATE_LIMIT] 自动等待 $(__format_wait_secs "$wait_secs") 后重试本次调用..." >&2
                echo "  [RATE_LIMIT] 想中止：Ctrl+C 或 kill 进程；想关掉本机制：AUTO_WORK_RATE_LIMIT_DISABLE=1" >&2
                # 把每分钟一次的心跳印出来，便于观察长 sleep 仍然存活
                local slept=0 chunk remain="$wait_secs"
                while [ "$remain" -gt 0 ]; do
                    chunk=60
                    [ "$remain" -lt 60 ] && chunk="$remain"
                    sleep "$chunk"
                    slept=$((slept + chunk))
                    remain=$((wait_secs - slept))
                    [ "$remain" -gt 0 ] && echo "  [RATE_LIMIT] 已等待 $(__format_wait_secs "$slept") / $(__format_wait_secs "$wait_secs") ..." >&2
                done
                echo "  [RATE_LIMIT] 等待完成，重试 claude -p..." >&2
                # 用同一 tmp_output 覆盖式重写，进入下一轮
                : > "$tmp_output"
                continue
            fi
            # 命中关键字但 wait_secs 为空 / 0 → 不应到达这里，__parse_* 至少返回 fallback；
            # 真到这里说明既非速率限制，按原失败返回
        fi

        rm -f "$tmp_output"
        __cli_trace_debug "done: exit=${exit_code} duration_ms=${duration_ms} attempts=$((attempt + 1))"
        return "$exit_code"
    done
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
#
# 优先走 Codex 跨模型对抗审查；失败时自动回退到 claude -p 以"严苛架构审查者"角色执行。
# 保证 auto-work 在 Codex 不可用 / 用量限制时仍能前进。
#
# 每次调用独立尝试 Codex（不用全局 CODEX_DISABLED 永久禁用）：
# - CODEX_AVAILABLE=0（二进制缺失）时立即走 claude 回退，不再尝试 Codex
# - 其他失败（额度/超时/API 错误）只降级本次调用，下次仍尝试 Codex（额度可能已恢复）
# - claude 回退保留"严苛架构审查者"prompt 前缀，并复用 __cli_trace_run 的速率限制无限重试
codex_review_exec() {
    CLI_CALL_COUNT=$((CLI_CALL_COUNT + 1))
    local prompt="$1"

    # 硬性失败：二进制不在 PATH，本进程永久降级
    if [ "${CODEX_AVAILABLE:-1}" = "0" ]; then
        echo "[codex_review_exec] Codex 不可用（二进制缺失），降级为 claude -p 严苛审查者" >&2
        __codex_review_fallback_claude "$prompt"
        return $?
    fi

    # 每次独立尝试 Codex（缓冲输出，失败时不污染调用方收到的内容）
    local _codex_tmp _codex_exit _t_start _t_end _t_ms
    _codex_tmp=$(mktemp 2>/dev/null || mktemp -t codex-review-out)
    _t_start=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")

    # shellcheck disable=SC2086
    codex exec --full-auto $CODEX_MODEL_FLAG "$prompt" > "$_codex_tmp" 2>&1
    _codex_exit=$?

    _t_end=$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")
    _t_ms=$((_t_end - _t_start))
    # shellcheck disable=SC2086
    __cli_trace_write_record "codex" "$prompt" "$_codex_exit" "$_t_ms" "$_codex_tmp" $CODEX_MODEL_FLAG || true

    if [ "$_codex_exit" -ne 0 ]; then
        local _err
        _err=$(cat "$_codex_tmp")
        rm -f "$_codex_tmp"

        if ! command -v codex >/dev/null 2>&1; then
            echo "[codex_review_exec] codex 命令消失，永久降级" >&2
            export CODEX_AVAILABLE=0
        elif echo "$_err" | grep -qiE "usage limit|hit your usage|quota|rate.?limit|429|try again|Unauthorized|401"; then
            echo "[codex_review_exec] Codex 触达用量/鉴权限制 (exit=$_codex_exit)，本次降级，下次仍尝试" >&2
        else
            echo "[codex_review_exec] Codex 本次调用失败 (exit=$_codex_exit)，本次降级，下次仍尝试" >&2
        fi

        # 降级到 claude 严苛审查者（丢弃 codex 错误输出，避免污染审查报告）
        __codex_review_fallback_claude "$prompt"
        return $?
    fi

    cat "$_codex_tmp"
    rm -f "$_codex_tmp"
    return 0
}

# 内部回退：用 claude -p 以严苛架构审查者角色执行同一 review 任务
# __cli_trace_run claude 自带速率限制无限等待+重试，所以这里不需要额外重试逻辑
__codex_review_fallback_claude() {
    local prompt="$1"
    local reviewer_prompt="你是一名严苛的资深架构审查者，以与编码者不同的视角对代码做对抗审查。
你的目标是找出编码者可能遗漏的盲区：并发竞态、资源泄漏、异常路径、边界输入、安全漏洞、上下文缺口。
禁止放水；禁止把 MEDIUM 以上的问题伪装成 LOW；禁止擅自修改代码，只做审查与报告。

下面是本轮审查的具体任务，严格按要求执行：

${prompt}"
    # shellcheck disable=SC2086
    __cli_trace_run claude "$reviewer_prompt" --permission-mode bypassPermissions $CLAUDE_MODEL_FLAG
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
        echo "PREFLIGHT WARN: codex 不在 PATH 中，review 将降级为 claude -p" >&2
        export CODEX_AVAILABLE=0
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

    # 3. codex API 冒烟测试（仅验证 API 可达性；软性失败不设全局标志）
    # 策略：CODEX_AVAILABLE=0 只在二进制缺失时设置（硬性失败）。
    # 额度/超时/API 错误属于临时问题，不全局禁用——各调用点（codex_review_exec）
    # 会单独尝试并在失败时本次降级，下次调用仍会重试 Codex。
    if [ -z "$PREFLIGHT_FAIL" ] && [ "$require_codex" = 1 ]; then
        if ! command -v codex >/dev/null 2>&1; then
            echo "PREFLIGHT WARN: codex 不在 PATH，review 将降级为 claude -p" >&2
            export CODEX_AVAILABLE=0   # 硬性失败：二进制缺失，永久降级
        else
            local codex_tmp
            codex_tmp=$(mktemp 2>/dev/null || mktemp -t preflight-codex)
            # 发送最小 prompt 验证 API 可达（非 --help）
            timeout 30 codex exec --full-auto "reply OK" > "$codex_tmp" 2>&1
            local preflight_rc=$?
            if [ "$preflight_rc" -eq 124 ]; then
                echo "PREFLIGHT WARN: codex preflight 超时，各调用点将单独尝试 Codex" >&2
                # 软性失败：不设 CODEX_AVAILABLE=0，各调用点自行重试
            elif [ "$preflight_rc" -eq 0 ]; then
                echo "PREFLIGHT OK: codex API 可达" >&2
                export CODEX_AVAILABLE=1
            else
                local codex_out
                codex_out=$(cat "$codex_tmp")
                if echo "$codex_out" | grep -qi "usage limit\|rate.limit\|quota\|429\|try again"; then
                    echo "PREFLIGHT WARN: codex API 触达用量限制，各调用点将单独尝试 Codex" >&2
                    # 软性失败：不设 CODEX_AVAILABLE=0，各调用点自行重试
                else
                    echo "PREFLIGHT WARN: codex API 测试失败 (exit=$preflight_rc)，各调用点将单独尝试 Codex" >&2
                    # 软性失败：不设 CODEX_AVAILABLE=0，各调用点自行重试
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
