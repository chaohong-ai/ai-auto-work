#!/bin/bash
# check-contracts.sh
# 校验 contracts 与 scripts/commands 的引用完整性
# 用法: bash .claude/scripts/check-contracts.sh

set -euo pipefail

ERRORS=0
WARNINGS=0

err()  { echo "ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN:  $1"; WARNINGS=$((WARNINGS + 1)); }
ok()   { echo "OK:    $1"; }

echo "=== Contract integrity check ==="
echo ""

# 1. 每个 contract 目录必须有 4 个文件
echo "1. Contract file existence..."
for scene in feature-plan feature-plan-review feature-develop feature-develop-review research-do research-review; do
    dir=".claude/contracts/${scene}"
    if [ ! -d "$dir" ]; then
        err "Missing contract directory: ${dir}"
        continue
    fi
    for part in inputs.md expand.md outputs.md gates.md; do
        if [ ! -f "${dir}/${part}" ]; then
            err "Missing contract file: ${dir}/${part}"
        fi
    done
done

echo ""

# 2. 每个 loop 脚本必须逐一引用对应 contract 目录的 4 个 part 文件
echo "2. Script references to all 4 contract parts per scene..."
declare -A SCRIPT_CONTRACTS
SCRIPT_CONTRACTS[".claude/scripts/feature-plan-loop.sh"]="feature-plan feature-plan-review"
SCRIPT_CONTRACTS[".claude/scripts/feature-develop-loop.sh"]="feature-develop feature-develop-review"
SCRIPT_CONTRACTS[".claude/scripts/research-loop.sh"]="research-do research-review"

for script in "${!SCRIPT_CONTRACTS[@]}"; do
    if [ ! -f "$script" ]; then
        err "Missing script: ${script}"
        continue
    fi
    for scene in ${SCRIPT_CONTRACTS[$script]}; do
        for part in inputs.md expand.md outputs.md gates.md; do
            if grep -qF "contracts/${scene}/${part}" "$script" 2>/dev/null; then
                ok "${script##*/} -> contracts/${scene}/${part}"
            else
                err "${script##*/} does NOT reference contracts/${scene}/${part}"
            fi
        done
    done
done

echo ""

# 3. 每个 command 文档必须引用对应的 contract 目录（不复制内容）
echo "3. Command doc references to contract directories..."
declare -A CMD_CONTRACTS
CMD_CONTRACTS[".claude/commands/feature/plan-creator.md"]="feature-plan"
CMD_CONTRACTS[".claude/commands/feature/plan-review.md"]="feature-plan-review"
CMD_CONTRACTS[".claude/commands/feature/developing.md"]="feature-develop"
CMD_CONTRACTS[".claude/commands/feature/develop-review.md"]="feature-develop-review"
CMD_CONTRACTS[".claude/commands/research/do.md"]="research-do"
CMD_CONTRACTS[".claude/commands/research/review.md"]="research-review"

for cmd in "${!CMD_CONTRACTS[@]}"; do
    if [ ! -f "$cmd" ]; then
        err "Missing command doc: ${cmd}"
        continue
    fi
    scene="${CMD_CONTRACTS[$cmd]}"
    if grep -qF "contracts/${scene}/" "$cmd" 2>/dev/null; then
        ok "${cmd##*/} references contracts/${scene}/"
    else
        err "${cmd##*/} does NOT reference contracts/${scene}/"
    fi
done

echo ""

# 4. 检查 command 文档中不应残留旧式硬编码契约关键词（包含所有常见 section 名）
echo "4. Checking for residual inline contract sections in command docs..."
for cmd in .claude/commands/feature/plan-creator.md .claude/commands/feature/plan-review.md .claude/commands/feature/developing.md .claude/commands/feature/develop-review.md .claude/commands/research/do.md .claude/commands/research/review.md; do
    if [ ! -f "$cmd" ]; then continue; fi
    for keyword in '必读输入' '按需展开' '输出要求' '硬性 gate' '硬性gate'; do
        if grep -qE "^\*\*${keyword}" "$cmd" 2>/dev/null; then
            warn "${cmd##*/} still has inline '${keyword}' section (should reference contract)"
        fi
    done
done

echo ""

# 5. bash -n 语法检查
echo "5. Shell script syntax..."
for script in .claude/scripts/feature-plan-loop.sh .claude/scripts/feature-develop-loop.sh .claude/scripts/research-loop.sh .claude/scripts/auto-work-loop.sh; do
    if [ ! -f "$script" ]; then continue; fi
    if bash -n "$script" 2>/dev/null; then
        ok "${script##*/} syntax OK"
    else
        err "${script##*/} syntax FAIL"
    fi
done

echo ""

# 6. 占位符一致性检查：contract 文件中出现的 {VAR} 必须在对应脚本的 load_contract() 里有 sed 规则
echo "6. Placeholder consistency (contracts/{VAR} -> load_contract sed rules)..."
declare -A SCENE_SCRIPT_MAP
SCENE_SCRIPT_MAP["feature-plan"]=".claude/scripts/feature-plan-loop.sh"
SCENE_SCRIPT_MAP["feature-plan-review"]=".claude/scripts/feature-plan-loop.sh"
SCENE_SCRIPT_MAP["feature-develop"]=".claude/scripts/feature-develop-loop.sh"
SCENE_SCRIPT_MAP["feature-develop-review"]=".claude/scripts/feature-develop-loop.sh"
SCENE_SCRIPT_MAP["research-do"]=".claude/scripts/research-loop.sh"
SCENE_SCRIPT_MAP["research-review"]=".claude/scripts/research-loop.sh"

for scene in feature-plan feature-plan-review feature-develop feature-develop-review research-do research-review; do
    dir=".claude/contracts/${scene}"
    script="${SCENE_SCRIPT_MAP[$scene]}"
    if [ ! -d "$dir" ] || [ ! -f "$script" ]; then continue; fi

    # Collect unique {VAR} placeholders across all 4 contract files for this scene
    placeholders=$(grep -ohE '\{[A-Z_]+\}' "${dir}"/*.md 2>/dev/null | sort -u)
    if [ -z "$placeholders" ]; then
        ok "contracts/${scene}/ has no placeholders"
        continue
    fi
    for ph in $placeholders; do
        if grep -qF "s|${ph}|" "$script" 2>/dev/null; then
            ok "${script##*/} load_contract() handles ${ph} (${scene})"
        else
            err "${script##*/} load_contract() missing sed rule for ${ph} -- used in contracts/${scene}/"
        fi
    done
done

echo ""
echo "=== Summary: ${ERRORS} errors, ${WARNINGS} warnings ==="
exit $ERRORS
