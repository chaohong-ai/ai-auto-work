#!/bin/bash
# fast-auto-work.sh
# 面向 direct + S 小改动的快速开发脚本：
# - 跳过 research / feature / plan / tasks / acceptance / docs / push
# - 保留 claude -p 独立上下文、编译门禁和相关测试

set -euo pipefail

source "$(dirname "$0")/cli-trace-helpers.sh"

VERSION_ID="${1:?用法: $0 <version_id> <feature_name> [requirement]}"
FEATURE_NAME="${2:?用法: $0 <version_id> <feature_name> [requirement]}"
USER_REQUIREMENT="${3:-}"

FEATURE_DIR="Docs/Version/${VERSION_ID}/${FEATURE_NAME}"
IDEA_FILE="${FEATURE_DIR}/idea.md"
CLASSIFY_FILE="${FEATURE_DIR}/classification.txt"
WORK_LOG="${FEATURE_DIR}/fast-auto-work-log.md"
ESCALATION_FILE="${FEATURE_DIR}/fast-auto-work-escalation.md"
ARTIFACT_DIR="${FEATURE_DIR}/fast-auto-work-artifacts"
DEV_OUTPUT_FILE="${ARTIFACT_DIR}/dev-output.txt"
BUILD_OUTPUT_FILE="${ARTIFACT_DIR}/build-output.txt"
TEST_OUTPUT_FILE="${ARTIFACT_DIR}/test-output.txt"
PREFLIGHT_CACHE_DIR=".claude/logs"
PREFLIGHT_CACHE_TTL="${FAST_AUTO_WORK_PREFLIGHT_TTL:-300}"
WORKSPACE_DIRTY_AT_START=0
LAST_CHANGED_FILES=""
LAST_FAILURE_SUMMARY=""

mkdir -p "$FEATURE_DIR"
export AUTO_WORK_FEATURE_DIR="$FEATURE_DIR"

CLAUDE_MODEL="${CLAUDE_MODEL:-}"
CLAUDE_MODEL_CODE="${CLAUDE_MODEL_CODE:-$CLAUDE_MODEL}"
CLAUDE_MODEL_FLAG=""
CLI_CALL_COUNT=0

if [ -n "$CLAUDE_MODEL_CODE" ]; then
    CLAUDE_MODEL_FLAG="--model $CLAUDE_MODEL_CODE"
    export CLAUDE_MODEL="$CLAUDE_MODEL_CODE"
fi

merge_requirement() {
    local merged=""
    if [ -f "$IDEA_FILE" ]; then
        merged="$(cat "$IDEA_FILE")"
    fi

    if [ -n "$USER_REQUIREMENT" ]; then
        if [ -n "$merged" ]; then
            merged="${merged}

---
补充需求：
${USER_REQUIREMENT}"
        else
            merged="$USER_REQUIREMENT"
        fi
    fi

    printf '%s' "$merged"
}

append_log() {
    printf '%s\n' "$1" >> "$WORK_LOG"
}

append_log_block() {
    local title="$1"
    local content="$2"
    {
        echo "$title"
        printf '%s\n' "$content"
    } >> "$WORK_LOG"
}

append_log_excerpt() {
    local title="$1"
    local file="$2"
    local lines="${3:-30}"
    if [ -f "$file" ]; then
        {
            echo "$title"
            tail -n "$lines" "$file"
        } >> "$WORK_LOG"
    fi
}

record_failure_summary() {
    local label="$1"
    local file="$2"
    local lines="${3:-30}"
    local excerpt=""
    if [ -f "$file" ]; then
        excerpt="$(tail -n "$lines" "$file" 2>/dev/null || true)"
    fi
    LAST_FAILURE_SUMMARY="${label}
${excerpt}"
}

write_escalation() {
    local reason="$1"
    {
        echo "# Fast Auto Work Escalation"
        echo ""
        echo "- feature: ${FEATURE_NAME}"
        echo "- version: ${VERSION_ID}"
        echo "- reason: ${reason}"
        echo "- log: ${WORK_LOG}"
        if [ -n "$LAST_CHANGED_FILES" ]; then
            echo "- changed_files:"
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                echo "  - ${file}"
            done <<< "$LAST_CHANGED_FILES"
        fi
        if [ -n "$LAST_FAILURE_SUMMARY" ]; then
            echo "- failure_summary: |"
            while IFS= read -r line; do
                echo "    ${line}"
            done <<< "$LAST_FAILURE_SUMMARY"
        fi
        echo "- next: /auto-work ${VERSION_ID} ${FEATURE_NAME}"
        echo "- alternative: /manual-work ${VERSION_ID} ${FEATURE_NAME}"
    } > "$ESCALATION_FILE"
}

collect_changed_files() {
    {
        git diff --name-only HEAD 2>/dev/null || true
        git status --porcelain --untracked-files=all 2>/dev/null | awk '{for (i=2; i<=NF; i++) print $i}' || true
    } | awk 'NF' | sort -u
}

filter_runtime_files() {
    local changed_files="$1"
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
            "$CLASSIFY_FILE"|"$WORK_LOG"|"$ESCALATION_FILE"|"$DEV_OUTPUT_FILE"|"$BUILD_OUTPUT_FILE"|"$TEST_OUTPUT_FILE")
                ;;
            "$ARTIFACT_DIR/"*|"$FEATURE_DIR/traces/"*|"$FEATURE_DIR/prompts/"*)
                ;;
            *)
                echo "$file"
                ;;
        esac
    done <<< "$changed_files"
}

fast_preflight_cache_file() {
    local model_key="${CLAUDE_MODEL_CODE:-default}"
    model_key="${model_key//[^A-Za-z0-9._-]/_}"
    printf '%s/fast-auto-work-preflight-%s.cache' "$PREFLIGHT_CACHE_DIR" "$model_key"
}

fast_preflight_check() {
    local cache_file now cached_at
    cache_file="$(fast_preflight_cache_file)"
    mkdir -p "$PREFLIGHT_CACHE_DIR"
    now="$(date +%s)"

    if [ -f "$cache_file" ]; then
        cached_at="$(awk -F= '/^ts=/{print $2; exit}' "$cache_file" 2>/dev/null || true)"
        if [ -n "$cached_at" ] && [ $((now - cached_at)) -lt "$PREFLIGHT_CACHE_TTL" ]; then
            PREFLIGHT_FAIL=""
            export __PREFLIGHT_PASSED=1
            echo "PREFLIGHT: cached success" >&2
            return 0
        fi
    fi

    __PREFLIGHT_PASSED=0
    export __PREFLIGHT_PASSED
    if preflight_check; then
        {
            echo "ts=${now}"
            echo "model=${CLAUDE_MODEL_CODE:-default}"
        } > "$cache_file"
        return 0
    fi
    return 1
}

ensure_clean_workspace_for_fast_path() {
    if git status --porcelain --untracked-files=all 2>/dev/null | grep -q .; then
        WORKSPACE_DIRTY_AT_START=1
        if [ "${FAST_AUTO_WORK_ALLOW_DIRTY:-0}" = "1" ]; then
            echo "[fast-auto-work] WARN dirty workspace detected; continuing because FAST_AUTO_WORK_ALLOW_DIRTY=1" >&2
            return 0
        fi
        write_escalation "workspace dirty before fast path; clean the worktree or set FAST_AUTO_WORK_ALLOW_DIRTY=1"
        exit 5
    fi
}

count_impl_files() {
    local changed_files="$1"
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
            *.md|*.txt|*.log|*.json|*.yml|*.yaml|*.hurl|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.uid|*.import|*.tscn)
                ;;
            *_test.go|*.test.ts|*.test.tsx|*.spec.ts|*.spec.tsx|test_*.py)
                ;;
            Docs/*|.ai/*|.claude/*)
                ;;
            Backend/*.go|Frontend/*.ts|Frontend/*.tsx|Frontend/*.js|Frontend/*.jsx|MCP/*.ts|MCP/*.tsx|MCP/*.js|Tools/*.py|Engine/*.gd|Template/*.gd|GameServer/*.go|Editor/*.ts|Editor/*.tsx)
                echo "$file"
                ;;
        esac
    done <<< "$changed_files" | awk 'NF' | sort -u | wc -l | tr -d ' '
}

count_touched_domains() {
    local changed_files="$1"
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
            Backend/*) echo "Backend" ;;
            Frontend/*) echo "Frontend" ;;
            MCP/*) echo "MCP" ;;
            Tools/*) echo "Tools" ;;
            Engine/*|Template/*) echo "Engine" ;;
            Editor/*) echo "Editor" ;;
            GameServer/*) echo "GameServer" ;;
        esac
    done <<< "$changed_files" | awk 'NF' | sort -u | wc -l | tr -d ' '
}

should_upgrade_fast_path() {
    local changed_files="$1"
    local reasons=""
    local impl_count domain_count

    impl_count="$(count_impl_files "$changed_files")"
    domain_count="$(count_touched_domains "$changed_files")"

    if [ "$impl_count" -gt 3 ]; then
        reasons="${reasons}
- touched ${impl_count} implementation files (>3)"
    fi

    if [ "$domain_count" -gt 1 ]; then
        reasons="${reasons}
- touched ${domain_count} top-level domains (cross-module change)"
    fi

    if printf '%s\n' "$changed_files" | grep -Eq '(^|/)project\.godot$'; then
        reasons="${reasons}
- touched project.godot which requires formal validation"
    fi

    if printf '%s\n' "$changed_files" | grep -Eq '(^|/)(router\.go|routes?\.go|.*\.proto)$|^Backend/tests/smoke/|^Docs/Architecture/|^\.ai/(constitution|context)/|^\.claude/(scripts|contracts|rules)/'; then
        reasons="${reasons}
- touched routing/contract/architecture workflow files outside fast-path scope"
    fi

    if printf '%s\n' "$changed_files" | grep -Eq '^Backend/internal/router/' &&
       { ! printf '%s\n' "$changed_files" | grep -Eq '^Backend/internal/router/router_test\.go$' ||
         ! printf '%s\n' "$changed_files" | grep -Eq '^Backend/tests/smoke/.*\.hurl$'; }; then
        reasons="${reasons}
- router changes without matching router_test.go + smoke hurl updates"
    fi

    if [ -n "$reasons" ]; then
        printf '%s' "$reasons"
        return 0
    fi

    return 1
}

requires_strict_tests() {
    local changed_files="$1"
    if printf '%s\n' "$changed_files" | grep -Eq '(^|/)(router\.go|routes?\.go|.*_test\.go|.*\.test\.tsx?|.*\.spec\.tsx?|test_.*\.py|.*\.hurl)$'; then
        return 0
    fi
    if printf '%s\n' "$changed_files" | grep -Eq '^Backend/internal/(handler|service|router)/|^GameServer/'; then
        return 0
    fi
    return 1
}

collect_go_packages() {
    local changed_files="$1"
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
            Backend/*.go)
                local pkg_dir rel_pkg
                pkg_dir="$(dirname "$file")"
                if [ "$pkg_dir" = "Backend" ]; then
                    echo "./..."
                else
                    rel_pkg="${pkg_dir#Backend/}"
                    echo "./${rel_pkg}/..."
                fi
                ;;
            GameServer/*.go)
                local pkg_dir rel_pkg
                pkg_dir="$(dirname "$file")"
                if [ "$pkg_dir" = "GameServer" ]; then
                    echo "GameServer:./..."
                else
                    rel_pkg="${pkg_dir#GameServer/}"
                    echo "GameServer:./${rel_pkg}/..."
                fi
                ;;
        esac
    done <<< "$changed_files" | awk 'NF' | sort -u
}

detect_godot_project_path() {
    local file="$1"
    local dir="$file"
    [ -d "$dir" ] || dir="$(dirname "$file")"
    while [ -n "$dir" ] && [ "$dir" != "." ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/project.godot" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

collect_godot_test_commands() {
    local changed_files="$1"
    local file project_root base rel_path
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
            *.gd|*.tscn)
                project_root="$(detect_godot_project_path "$file" || true)"
                [ -z "$project_root" ] && continue
                base="$(basename "$file")"
                base="${base%.*}"

                if [ -f "$project_root/test/test_${base}.tscn" ]; then
                    rel_path="test/test_${base}.tscn"
                    printf 'cd "%s" && godot --headless --path "%s" "%s"\n' "$project_root" "$project_root" "$rel_path"
                fi
                if [ -f "$project_root/test/${base}_test.tscn" ]; then
                    rel_path="test/${base}_test.tscn"
                    printf 'cd "%s" && godot --headless --path "%s" "%s"\n' "$project_root" "$project_root" "$rel_path"
                fi
                if [ -f "$project_root/test/test_${base}.gd" ] && [ -f "$project_root/addons/gut/gut_cmdln.gd" ]; then
                    rel_path="test/test_${base}.gd"
                    printf 'cd "%s" && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://%s -gexit\n' "$project_root" "$rel_path"
                fi
                if [ -f "$project_root/test/${base}_test.gd" ] && [ -f "$project_root/addons/gut/gut_cmdln.gd" ]; then
                    rel_path="test/${base}_test.gd"
                    printf 'cd "%s" && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://%s -gexit\n' "$project_root" "$rel_path"
                fi
                ;;
        esac
    done <<< "$changed_files" | awk 'NF' | sort -u
}

run_build_gate() {
    local changed_files="$1"
    local ok=0
    : > "$BUILD_OUTPUT_FILE"

    if printf '%s\n' "$changed_files" | grep -Eq '^Backend/.*\.(go|mod|sum)$'; then
        local start_ts rc
        start_ts="$(date +%s)"
        if (cd Backend && go build ./...) > "$ARTIFACT_DIR/backend-build.log" 2>&1; then
            rc=0
        else
            rc=$?
            ok=1
        fi
        cat "$ARTIFACT_DIR/backend-build.log" >> "$BUILD_OUTPUT_FILE"
        append_log "- [gate] Backend go build: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
        if [ "$rc" -ne 0 ]; then
            append_log_excerpt "```text" "$ARTIFACT_DIR/backend-build.log" 30
            append_log "```"
        fi
    fi

    if printf '%s\n' "$changed_files" | grep -Eq '^MCP/'; then
        local start_ts rc
        start_ts="$(date +%s)"
        if (cd MCP && npx tsc --noEmit) > "$ARTIFACT_DIR/mcp-build.log" 2>&1; then
            rc=0
        else
            rc=$?
            ok=1
        fi
        cat "$ARTIFACT_DIR/mcp-build.log" >> "$BUILD_OUTPUT_FILE"
        append_log "- [gate] MCP tsc: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
        if [ "$rc" -ne 0 ]; then
            append_log_excerpt "```text" "$ARTIFACT_DIR/mcp-build.log" 30
            append_log "```"
        fi
    fi

    if printf '%s\n' "$changed_files" | grep -Eq '^Frontend/'; then
        local start_ts rc
        start_ts="$(date +%s)"
        if (cd Frontend && npx tsc --noEmit) > "$ARTIFACT_DIR/frontend-build.log" 2>&1; then
            rc=0
        else
            rc=$?
            ok=1
        fi
        cat "$ARTIFACT_DIR/frontend-build.log" >> "$BUILD_OUTPUT_FILE"
        append_log "- [gate] Frontend tsc: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
        if [ "$rc" -ne 0 ]; then
            append_log_excerpt "```text" "$ARTIFACT_DIR/frontend-build.log" 30
            append_log "```"
        fi
    fi

    if [ ! -s "$BUILD_OUTPUT_FILE" ]; then
        append_log "- [gate] skipped (no buildable stacks touched)"
    fi

    if [ "$ok" -ne 0 ]; then
        record_failure_summary "build gate failed" "$BUILD_OUTPUT_FILE" 40
    fi

    return "$ok"
}

run_related_tests() {
    local changed_files="$1"
    local ok=0
    local any_test=0
    local missing_godot=0
    : > "$TEST_OUTPUT_FILE"

    local backend_go_pkgs=""
    local gameserver_go_pkgs=""
    backend_go_pkgs="$(collect_go_packages "$changed_files" | grep '^\.\/' | tr '\n' ' ' | xargs 2>/dev/null || true)"
    gameserver_go_pkgs="$(collect_go_packages "$changed_files" | grep '^GameServer:' | sed 's/^GameServer://' | tr '\n' ' ' | xargs 2>/dev/null || true)"

    if [ -n "$backend_go_pkgs" ]; then
        any_test=1
        local start_ts rc
        start_ts="$(date +%s)"
        if (cd Backend && go test -short -count=1 $backend_go_pkgs) > "$ARTIFACT_DIR/go-test.log" 2>&1; then
            rc=0
        else
            rc=$?
            ok=1
        fi
        cat "$ARTIFACT_DIR/go-test.log" >> "$TEST_OUTPUT_FILE"
        append_log "- [test] Go related packages: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
        if [ "$rc" -ne 0 ]; then
            append_log_excerpt "```text" "$ARTIFACT_DIR/go-test.log" 30
            append_log "```"
        fi
    fi

    if [ -n "$gameserver_go_pkgs" ]; then
        any_test=1
        local start_ts rc
        start_ts="$(date +%s)"
        if (cd GameServer && go test -short -count=1 $gameserver_go_pkgs) > "$ARTIFACT_DIR/gameserver-go-test.log" 2>&1; then
            rc=0
        else
            rc=$?
            ok=1
        fi
        cat "$ARTIFACT_DIR/gameserver-go-test.log" >> "$TEST_OUTPUT_FILE"
        append_log "- [test] GameServer related packages: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
        if [ "$rc" -ne 0 ]; then
            append_log_excerpt "```text" "$ARTIFACT_DIR/gameserver-go-test.log" 30
            append_log "```"
        fi
    fi

    local mcp_files=""
    mcp_files="$(printf '%s\n' "$changed_files" | grep '^MCP/.*\.tsx\?$' | tr '\n' ' ' | xargs 2>/dev/null || true)"
    if [ -n "$mcp_files" ] && [ -d "MCP" ]; then
        any_test=1
        local start_ts rc
        start_ts="$(date +%s)"
        if (cd MCP && npx jest --findRelatedTests --passWithNoTests $mcp_files) > "$ARTIFACT_DIR/mcp-test.log" 2>&1; then
            rc=0
        else
            rc=$?
            ok=1
        fi
        cat "$ARTIFACT_DIR/mcp-test.log" >> "$TEST_OUTPUT_FILE"
        append_log "- [test] MCP related tests: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
        if [ "$rc" -ne 0 ]; then
            append_log_excerpt "```text" "$ARTIFACT_DIR/mcp-test.log" 30
            append_log "```"
        fi
    fi

    local frontend_files=""
    frontend_files="$(printf '%s\n' "$changed_files" | grep '^Frontend/.*\.tsx\?$' | tr '\n' ' ' | xargs 2>/dev/null || true)"
    if [ -n "$frontend_files" ] && [ -d "Frontend" ]; then
        any_test=1
        local start_ts rc
        start_ts="$(date +%s)"
        if (cd Frontend && npx jest --findRelatedTests --passWithNoTests $frontend_files) > "$ARTIFACT_DIR/frontend-test.log" 2>&1; then
            rc=0
        else
            rc=$?
            ok=1
        fi
        cat "$ARTIFACT_DIR/frontend-test.log" >> "$TEST_OUTPUT_FILE"
        append_log "- [test] Frontend related tests: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
        if [ "$rc" -ne 0 ]; then
            append_log_excerpt "```text" "$ARTIFACT_DIR/frontend-test.log" 30
            append_log "```"
        fi
    fi

    local py_tests=""
    py_tests="$(printf '%s\n' "$changed_files" | grep '^Tools/.*\.py$' | sed 's#\([^/]*\)\.py$#test_\1.py#' | tr '\n' ' ' | xargs 2>/dev/null || true)"
    if [ -n "$py_tests" ]; then
        local existing_py_tests=""
        for test_file in $py_tests; do
            if [ -f "$test_file" ]; then
                existing_py_tests="${existing_py_tests} $test_file"
            fi
        done
        if [ -n "$existing_py_tests" ]; then
            any_test=1
            local start_ts rc
            start_ts="$(date +%s)"
            if pytest $existing_py_tests > "$ARTIFACT_DIR/python-test.log" 2>&1; then
                rc=0
            else
                rc=$?
                ok=1
            fi
            cat "$ARTIFACT_DIR/python-test.log" >> "$TEST_OUTPUT_FILE"
            append_log "- [test] Python related tests: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
            if [ "$rc" -ne 0 ]; then
                append_log_excerpt "```text" "$ARTIFACT_DIR/python-test.log" 30
                append_log "```"
            fi
        fi
    fi

    local godot_cmds=""
    godot_cmds="$(collect_godot_test_commands "$changed_files")"
    if [ -n "$godot_cmds" ]; then
        any_test=1
        if command -v godot >/dev/null 2>&1; then
            while IFS= read -r cmd; do
                [ -z "$cmd" ] && continue
                local start_ts rc
                start_ts="$(date +%s)"
                if bash -lc "$cmd" > "$ARTIFACT_DIR/godot-test.log" 2>&1; then
                    rc=0
                else
                    rc=$?
                    ok=1
                fi
                cat "$ARTIFACT_DIR/godot-test.log" >> "$TEST_OUTPUT_FILE"
                append_log "- [test] Godot related test: $( [ "$rc" -eq 0 ] && echo PASS || echo FAIL ) ($(( $(date +%s) - start_ts ))s)"
                if [ "$rc" -ne 0 ]; then
                    append_log_excerpt "```text" "$ARTIFACT_DIR/godot-test.log" 30
                    append_log "```"
                fi
            done <<< "$godot_cmds"
        else
            missing_godot=1
            append_log "- [test] Godot related tests detected but skipped ([ENVIRONMENT_MISSING: godot])"
        fi
    fi

    if [ "$any_test" -eq 0 ]; then
        if requires_strict_tests "$changed_files"; then
            append_log "- [test] FAIL no related automated tests detected for a risky change"
            ok=1
        else
            append_log "- [test] No related automated tests detected"
        fi
    fi

    if [ "$ok" -ne 0 ] || [ "$missing_godot" -eq 1 ]; then
        record_failure_summary "related tests failed or were incomplete" "$TEST_OUTPUT_FILE" 40
    fi

    return "$ok"
}

cli_call_capture() {
    local prompt="$1"
    local output_file="$2"
    shift 2
    local timeout_secs="${FAST_AUTO_WORK_CLI_TIMEOUT:-1800}"
    local rc_file waited=0 pid

    rc_file=$(mktemp 2>/dev/null || mktemp -t fast-auto-work-cli)
    : > "$output_file"
    (
        if cli_call "$prompt" "$@" > "$output_file" 2>&1; then
            echo 0 > "$rc_file"
        else
            echo $? > "$rc_file"
        fi
    ) &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$timeout_secs" ]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            echo 124 > "$rc_file"
            echo "[TIMEOUT] cli_call exceeded ${timeout_secs}s" >> "$output_file"
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    wait "$pid" 2>/dev/null || true
    CLI_CALL_CAPTURE_RC="$(cat "$rc_file" 2>/dev/null || echo 1)"
    rm -f "$rc_file"
}

maybe_commit() {
    if [ "${FAST_AUTO_WORK_COMMIT:-0}" != "1" ]; then
        append_log "- [commit] skipped (FAST_AUTO_WORK_COMMIT != 1)"
        return 0
    fi

    if [ "$WORKSPACE_DIRTY_AT_START" -eq 1 ]; then
        append_log "- [commit] blocked (workspace was dirty at start)"
        write_escalation "auto commit blocked because workspace was dirty at start; commit manually after isolating the diff"
        exit 6
    fi

    if ! git status --porcelain 2>/dev/null | grep -q .; then
        append_log "- [commit] skipped (no changes)"
        return 0
    fi

    git add -A
    git reset -q HEAD -- "$WORK_LOG" "$ESCALATION_FILE" "$CLASSIFY_FILE" "$ARTIFACT_DIR/" "$FEATURE_DIR/traces/" "$FEATURE_DIR/prompts/" 2>/dev/null || true
    if git diff --cached --quiet; then
        append_log "- [commit] skipped (only runtime files changed)"
        return 0
    fi

    git commit -m "feat(${FEATURE_NAME}): fast auto work"
    append_log "- [commit] created local commit"
}

REQUIREMENT="$(merge_requirement)"
if [ -z "$REQUIREMENT" ]; then
    echo "ERROR: 缺少需求描述，且 ${IDEA_FILE} 不存在或为空" >&2
    exit 1
fi

ensure_clean_workspace_for_fast_path
fast_preflight_check || {
    write_escalation "preflight failed: ${PREFLIGHT_FAIL:-unknown}"
    exit 1
}

mkdir -p "$ARTIFACT_DIR"

cat > "$CLASSIFY_FILE" <<EOF
type=direct
complexity=S
forced_by=fast-auto-work
EOF

START_TS="$(date '+%Y-%m-%d %H:%M:%S')"
{
    echo "# Fast Auto Work Log"
    echo ""
    echo "- feature: ${FEATURE_NAME}"
    echo "- version: ${VERSION_ID}"
    echo "- mode: direct + S"
    echo "- started_at: ${START_TS}"
    echo "- model: ${CLAUDE_MODEL_CODE:-default}"
    echo ""
    echo "## Steps"
} > "$WORK_LOG"

append_log "- [preflight] PASS"
if [ "$WORKSPACE_DIRTY_AT_START" -eq 1 ]; then
    append_log "- [workspace] WARN dirty workspace detected before run; continuing because FAST_AUTO_WORK_ALLOW_DIRTY=1"
    append_log "- [workspace] WARN auto commit will remain disabled"
else
    append_log "- [workspace] PASS clean workspace"
fi

mark_stage "fast-dev"
DEV_PROMPT="你正在执行 fast-auto-work 快速开发流程。请直接实现以下需求。

需求内容：
${REQUIREMENT}

硬规则：
1. 先搜索项目内相似实现，再复用现有模式落地。
2. 只做直接开发，不生成 feature.md、plan.md、tasks/task-*.md。
3. 变更要尽量小；如果你判断该需求明显超出小改动范围，只能单独输出一行 UPGRADE_TO_AUTO_WORK: <reason> 后结束。
4. 为本次变更补充必要测试。
5. 完成后自行运行与你改动相关的构建/测试命令并修正问题。
6. 不要向用户提问，直接完成。"

append_log "- [step] implement"
cli_call_capture "$DEV_PROMPT" "$DEV_OUTPUT_FILE" --permission-mode bypassPermissions
DEV_OUTPUT="$(cat "$DEV_OUTPUT_FILE" 2>/dev/null || true)"
printf '%s\n' "$DEV_OUTPUT" | tail -20
append_log_excerpt "```text" "$DEV_OUTPUT_FILE" 30
append_log "```"

if printf '%s\n' "$DEV_OUTPUT" | grep -qE '^UPGRADE_TO_AUTO_WORK($|:)'; then
    append_log "- [step] model requested escalation"
    record_failure_summary "model requested escalation" "$DEV_OUTPUT_FILE" 20
    write_escalation "model judged task too large for fast path"
    exit 2
fi

if [ "${CLI_CALL_CAPTURE_RC:-0}" -eq 124 ]; then
    append_log "- [step] implement timed out"
    record_failure_summary "implement timed out" "$DEV_OUTPUT_FILE" 30
    write_escalation "implement step timed out after ${FAST_AUTO_WORK_CLI_TIMEOUT:-1800}s"
    exit 7
fi

if [ "${CLI_CALL_CAPTURE_RC:-0}" -ne 0 ]; then
    append_log "- [step] implement failed (exit=${CLI_CALL_CAPTURE_RC})"
    record_failure_summary "implement failed" "$DEV_OUTPUT_FILE" 30
    write_escalation "implement step failed (exit=${CLI_CALL_CAPTURE_RC})"
    exit 8
fi

CHANGED_FILES="$(collect_changed_files)"
CHANGED_FILES="$(filter_runtime_files "$CHANGED_FILES")"
LAST_CHANGED_FILES="$CHANGED_FILES"
if [ -z "$CHANGED_FILES" ]; then
    append_log "- [result] no workspace changes detected"
    exit 0
fi

append_log_block "## Changed Files" "$CHANGED_FILES"

UPGRADE_REASONS="$(should_upgrade_fast_path "$CHANGED_FILES" || true)"
if [ -n "$UPGRADE_REASONS" ]; then
    append_log "- [route] fast path no longer applicable"
    while IFS= read -r reason; do
        [ -z "$reason" ] && continue
        append_log "  ${reason}"
    done <<< "$UPGRADE_REASONS"
    LAST_FAILURE_SUMMARY="actual diff exceeded fast-path scope
${UPGRADE_REASONS}"
    write_escalation "actual diff exceeded fast-path scope${UPGRADE_REASONS}"
    exit 2
fi

BUILD_OK=0
if run_build_gate "$CHANGED_FILES"; then
    BUILD_OK=1
else
    append_log "- [step] build gate failed, retry once"
    BUILD_FAILURES="$(cat "$BUILD_OUTPUT_FILE" 2>/dev/null || true)"
    FIX_PROMPT="fast-auto-work 的构建门禁失败。请只修复以下构建错误，不要扩散改动。

${BUILD_FAILURES}"
    cli_call_capture "$FIX_PROMPT" "$ARTIFACT_DIR/build-fix-output.txt" --permission-mode bypassPermissions
    append_log_excerpt "```text" "$ARTIFACT_DIR/build-fix-output.txt" 20
    append_log "```"
    CHANGED_FILES="$(collect_changed_files)"
    CHANGED_FILES="$(filter_runtime_files "$CHANGED_FILES")"
    LAST_CHANGED_FILES="$CHANGED_FILES"
    UPGRADE_REASONS="$(should_upgrade_fast_path "$CHANGED_FILES" || true)"
    if [ -n "$UPGRADE_REASONS" ]; then
        append_log "- [route] fast path no longer applicable after build-fix round"
        while IFS= read -r reason; do
            [ -z "$reason" ] && continue
            append_log "  ${reason}"
        done <<< "$UPGRADE_REASONS"
        LAST_FAILURE_SUMMARY="actual diff exceeded fast-path scope after build-fix round
${UPGRADE_REASONS}"
        write_escalation "actual diff exceeded fast-path scope after build-fix round${UPGRADE_REASONS}"
        exit 2
    fi
    if run_build_gate "$CHANGED_FILES"; then
        BUILD_OK=1
    fi
fi

if [ "$BUILD_OK" -ne 1 ]; then
    append_log "- [result] build gate still failing"
    write_escalation "build gate failed after one repair round"
    exit 3
fi

if run_related_tests "$CHANGED_FILES"; then
    append_log "- [result] related tests passed"
else
    append_log "- [result] related tests failed"
    write_escalation "related tests failed"
    exit 4
fi

maybe_commit

END_TS="$(date '+%Y-%m-%d %H:%M:%S')"
append_log "- completed_at: ${END_TS}"
append_log "- status: success"

echo "FAST_AUTO_WORK_OK"
echo "log: ${WORK_LOG}"
