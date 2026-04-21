#!/bin/bash
# review-helpers.sh
# 共享 review 调度工具函数，供 auto-work-loop.sh / feature-develop-loop.sh / feature-plan-loop.sh 使用
#
# 环境变量:
#   REVIEW_SHARD_MODE: 强制覆盖 review 分片策略（single|parallel），默认自动判断

# ══════════════════════════════════════════════════════════
# context_repair_cheap_gate
# 廉价预检：判断 review 文件是否包含实质性的 Context Repair 内容
# 返回 0（真）= 有内容需要处理；返回 1（假）= 无内容或只有占位符
# ══════════════════════════════════════════════════════════
context_repair_cheap_gate() {
    local review_file="$1"
    [ -f "$review_file" ] || return 1
    grep -q "^## Context Repairs" "$review_file" 2>/dev/null || return 1
    local section
    section=$(sed -n '/^## Context Repairs/,/^## /{ /^## Context Repairs/d; /^## /d; p }' "$review_file" 2>/dev/null)
    [ -n "$section" ] || return 1
    local stripped
    stripped=$(echo "$section" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | grep -v '^-[[:space:]]*无$' | grep -v '^无$')
    [ -n "$stripped" ] || return 1
    return 0
}

# ══════════════════════════════════════════════════════════
# count_changes
# 统计自指定 git ref 以来的变更规模，输出格式："DIRS:FILES"
# ══════════════════════════════════════════════════════════
count_changes() {
    local ref="${1:-HEAD~1}"
    if ! git rev-parse "$ref" >/dev/null 2>&1; then
        echo "0:0"
        return 0
    fi
    local changed_files
    changed_files=$(git diff --name-only "$ref"..HEAD 2>/dev/null | wc -l | tr -d ' ')
    local changed_dirs
    changed_dirs=$(git diff --name-only "$ref"..HEAD 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort -u | wc -l | tr -d ' ')
    echo "${changed_dirs}:${changed_files}"
}

# ══════════════════════════════════════════════════════════
# should_use_parallel
# 为 develop/plan review 决定使用单路还是并行 review
# 参数：<complexity> <dirs> <files> <critical> <high>
# 输出："parallel" 或 "single"
# ══════════════════════════════════════════════════════════
should_use_parallel() {
    local complexity="${1:-L}"
    local dirs="${2:-0}"
    local files="${3:-0}"
    local critical="${4:-0}"
    local high="${5:-0}"
    if [ -n "${REVIEW_SHARD_MODE:-}" ]; then
        echo "$REVIEW_SHARD_MODE"
        return 0
    fi
    if [ "$complexity" = "S" ] || [ "$complexity" = "M" ]; then
        echo "single"
        return 0
    fi
    if [ "$critical" -gt 0 ] || [ "$files" -gt 15 ] || [ "$dirs" -gt 4 ]; then
        echo "parallel"
        return 0
    fi
    echo "single"
}

# ══════════════════════════════════════════════════════════
# should_acceptance_use_parallel
# 为 acceptance review 决定使用单路还是并行 review
# 参数：<complexity> <dirs> <files>
# 输出："parallel" 或 "single"
# ══════════════════════════════════════════════════════════
should_acceptance_use_parallel() {
    local complexity="${1:-L}"
    local dirs="${2:-0}"
    local files="${3:-0}"
    if [ -n "${REVIEW_SHARD_MODE:-}" ]; then
        echo "$REVIEW_SHARD_MODE"
        return 0
    fi
    if [ "$complexity" = "S" ] || [ "$complexity" = "M" ]; then
        echo "single"
        return 0
    fi
    if [ "$files" -gt 20 ] || [ "$dirs" -gt 5 ]; then
        echo "parallel"
        return 0
    fi
    echo "single"
}
