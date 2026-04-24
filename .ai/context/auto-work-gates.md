# auto-work 生成侧机械门禁清单

> 本文件是 **auto-work / manual-work / feature-develop** 在 review 阶段入口处**生成侧**必须机械执行的硬门禁清单的权威来源。
>
> **为什么落在 `.ai/`：** `.claude/commands/auto-work.md` 自 task-11 起累计 12 批次 Edit 权限被拒（sensitive file / requires permission），导致门禁无法直接落地。按 task-12 CR-1 裁定，将权威清单固化到 `.ai/context/auto-work-gates.md`（全 agent 可读、允许写入），由 `.claude/commands/auto-work.md` 在下一次权限窗口通过"仅引用"方式接入；在引用尚未落地的窗口期内，auto-work / manual-work / develop 执行者读取本文件时仍必须手动执行所有机械检查。
>
> **作用域：** 适用于所有 agent 执行的 auto-work / manual-work / bug-fix 流程，在进入 reviewer（develop-review / plan-review / acceptance-review）阶段前触发。

---

## 门禁 G1：`verify_commands` 必须实际运行测试（task-11/12/13/14/15 CR RECURRING）

**触发条件**（任一命中）：

1. `tasks/task-NN.md` 的 `新增` / `modify` 列表主要包含 `_test.go` / `*.test.ts` / `*.test.tsx` / `.hurl`；
2. 任务的 `验证标准` 段落列出具名 `Test*` / `describe(` / `test(` / `GET .+ HTTP/1.1`；
3. 任务名或描述含 "单元测试" / "unit test" / "补测试" / "测试覆盖"；
4. 任务涉及后台定时 goroutine（`ticker` / `time.After` / cleanup loop / heartbeat reaper）、CAS 状态机（`CompareAndSwap*`）、timeout / deadline 生命周期清理、channel close 协议、`Session.Send` / `Session.Close` / broadcast / registry 注销路径（即使 plan 未显式标注 `[强制]`）；
5. **[task-32 H1] 任务验证标准描述了可执行行为**：具名函数签名（`_on_*_pressed()` / `class_name X extends Y`）、按钮或信号处理器副作用、运行时状态切换（`network_enabled = true`）、场景重载（`reload_current_scene()`）、节点树裁剪（`queue_free()` / 移除子节点）、FSM 状态跳转等，且当前 `verify_commands` 仅由 `bash -c "test -f ..."` / `ls <path>` / `stat <path>` 这类存在性检查构成。
6. **[v0.0.1 animator task-02 H1] FBX → `.tscn` 导入任务声称"可实例化 / 可渲染"**：task scope 含 `.fbx` 导入并落盘 `.tscn`（`assets/**/models/**/*.tscn` / 类似路径），task 验证标准出现 *"实例化"* / *"MeshInstance3D 正常渲染"* / *"无 null 报错"* / *"可加载场景"* 等渲染语义关键词，但 `verify_commands` 仅为 `test -f` / `ls` / `stat` —— 视同 `FBX_WRAPPER_EXISTENCE_ONLY`，由 G1 在写盘前机械阻断并回退 developing 补：(a) 展开 `Skeleton3D` / `MeshInstance3D` 节点的 `.tscn`，或 (b) headless scene-load 断言脚本（`godot --headless --script` + `get_node()` 断言）。权威语义见 `.ai/constitution/testing-review.md §Godot 资源装配非空轨道核验 §2` 的 "FBX-to-`.tscn` 导入任务的 `test -f` only 阻断" 子条。

**机械检查**：

- `verify_commands` 必须按语言栈包含下列其中一条实测命令：
  - Go：`go test -count=1 ./<目标目录>/...` 或 `go test -run '<TestName>' ./<目标目录>`
  - TypeScript：`jest --testPathPattern '<目标目录>'`
  - HTTP 冒烟：`hurl <目标 .hurl>`
  - GDScript / Godot：`godot --headless --path <project> --script <smoke.gd>` 或 gdUnit / GUT 用例命令（`--import` / `--check-only` 不构成行为验证，仅属资产落盘检查）。
- 命中高风险特征（触发条件 4）时，必须追加 `-race`；`-race requires cgo` 时降级为 ≥100 goroutine 并发压测并在 `verify_commands` 注释中显式记录降级原因。
- **仅 `go build` / `go vet` / `tsc --noEmit` 视同"只检查语法不跑测试"**，直接阻断 reviewer 阶段。
- **[task-32 H1] 存在性-only 组合阻断**：命中触发条件 5 时（任务描述有行为、`verify_commands` 只含存在性检查），生成侧必须以 `VERIFY_COMMANDS_EXISTENCE_ONLY` 信号阻断 reviewer；豁免仅限"纯文件占位型任务"（资产 `.uid` 占位、空目录骨架、素材落盘，task 验证标准中**不含**任何行为/副作用描述）。下面的 grep 在生成 `review-input-*.md` 前必跑：

    ```bash
    # 识别 verify_commands 是否仅包含存在性检查
    TASK=tasks/task-NN.md
    # 抽取 verify_commands 列表
    VCMDS=$(awk '/^verify_commands:/{flag=1;next} /^[a-zA-Z_]+:/{flag=0} flag && /^ *- /' "$TASK")
    # 非存在性命令 = 含 go test / jest / hurl / godot --headless --script / pytest 等
    NONEXIST=$(echo "$VCMDS" | grep -E 'go test|jest|hurl|godot[^|]*--script|pytest|npm test|gdunit|gut' || true)
    # 任务描述含行为关键字（中英兼容）
    HASBEHAVIOR=$(awk '/^## .*验证标准|^## .*Verification/{flag=1;next} /^## /{flag=0} flag' "$TASK" \
      | grep -E '_on_|call\(|queue_free|reload_current_scene|network_enabled|state\s*=|FSM|handler|signal|press|click|emit|emit_signal|disconnect|副作用|切换|跳转' || true)
    if [ -z "$NONEXIST" ] && [ -n "$HASBEHAVIOR" ]; then
      echo "VERIFY_COMMANDS_EXISTENCE_ONLY: $TASK 声明了行为验证，但 verify_commands 仅含存在性检查"
      exit 1
    fi
    ```

**阻断动作**：退回 developing 阶段修正 `task-NN.md` 并补测试；未修正前不得生成 `review-input-develop.md`。

**权威语义来源**：`.ai/constitution.md` §4 + `.ai/constitution/testing-review.md`「Task verify_commands 必须覆盖 plan 可自动化验证条目」（含高风险任务自动识别、Task scope 本身为测试文件的强制 verify 规则、并发测试替代方案三小节）。

---

## 门禁 G2：`review-input-*.md` 必须三源采集 + scope 交集校验（task-12 C1 / task-13 CR-2 / task-14 H2 / task-15 H2 RECURRING）

**触发条件**：生成 `review-input-develop.md` / `review-input-acceptance.md` 的任意阶段。

**机械检查**（生成完成后、写盘前）：

1. **三源采集**：`## Git Diff --stat` / `## Changed Files` 段落必须合并以下三源，不得只取其一：
   - `git diff --stat`（已暂存 + 未暂存的跟踪文件）
   - `git diff --name-only`（补全文件清单）
   - `git status --short`（含未跟踪 `??` 文件，必须并入 `## Changed Files`）
   - **同 `git -C <repo-root>` baseline（v0.0.1 animator task-02 CR-1 RECURRING 触发）**：三条命令必须在**同一次** `git -C <repo-root>` 调用序列内、针对**同一个工作区根**执行；严禁将上一阶段 / 其他 feature / 旧版 develop-loop 缓存的 `## Git Diff --stat` 内容拼接到本轮 `review-input-*.md`（典型失败模式：v0.0.1 animator task-02 的 `review-input-develop.md` 内嵌 diff 全部来自 v0.0.4 test-thin-client 工作，task-02 交付物反而一个未上榜）。生成器必须在三源采集前重新执行 `git rev-parse --show-toplevel` 并断言其路径与 `FEATURE_DIR` 解析出的 repo 根一致，任一不一致即判 `STALE_REVIEW_INPUT_CROSS_FEATURE` 阻断写盘。
2. **工作区覆盖率 100%（task-12 round-8 CR-1 / round-10 CR-1 RECURRING）**：三源合并后的工作区文件清单 `W = (git diff --name-only) ∪ (git status --short --untracked-files=all 去前缀列)` 必须**逐一**出现在 `## Changed Files` 段，覆盖率不得 < 100%。
   - 未跟踪文件（`??` 前缀，必须启用 `--untracked-files=all` 获取，默认 `normal` 模式会遗漏新目录内的文件）、仅 rename（`R `）、仅删除（`D ` / ` D`）也必须列入，不能以"未 staged"为由豁免；
   - 验证脚手架：`comm -23 <(工作区文件清单 | sort -u) <(Changed Files 段列出文件 | sort -u)` 必须输出为空；非空 → `WORKSPACE_COVERAGE_INCOMPLETE` 阻断；
   - **逆向 stale 路径检测（v0.0.1 animator task-02 CR-1 RECURRING）**：`comm -23 <(Changed Files 段列出文件 | sort -u) <(工作区文件清单 | sort -u)` 亦必须为空；非空表示 `## Changed Files` 包含当前工作区不存在的历史 feature 路径（典型：task-02 的 `review-input-develop.md` 列出了 `v0.0.4/test-thin-client/*` 路径）→ `STALE_REVIEW_INPUT_CROSS_FEATURE` 阻断，立即删除 `review-input-*.md` 并退回 developing；
   - 典型遗漏类型（task-12 round-8/10 实证）：新增的 `review-input-*.md` / `acceptance-*.md` / `.ai/context/auto-work-gates.md` / `task-guardian-report.md` / 批量新增的 `develop-iteration-log-task-NN.md` / `Template/*/project.godot` / 任意未跟踪脚手架 —— 任一"真实存在于工作区但 review-input 摘要未列出"即判阻断。
   - **可直接复制的检测脚本（生成 review-input 后写盘前必跑）**：

     ```bash
     # 在 feature 目录下执行；失败即视为 WORKSPACE_COVERAGE_INCOMPLETE
     INPUT=Docs/Version/<version>/<feature>/review-input-develop.md
     WORKSPACE=$(mktemp); LISTED=$(mktemp)
     # 1) 合并 git diff + git status（含未跟踪 `--untracked-files=all`）
     { git diff --name-only; \
       git status --short --untracked-files=all | awk '{for(i=2;i<=NF;i++) print $i}'; \
     } | sort -u > "$WORKSPACE"
     # 2) 从 review-input 的 ## Changed Files 段抽取文件名
     awk '/^## Changed Files/{flag=1;next} /^## /{flag=0} flag' "$INPUT" \
       | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+|[A-Za-z0-9_./-]+/' \
       | sort -u > "$LISTED"
     # 3) 求差集：工作区存在但 review-input 未列出
     MISSING=$(comm -23 "$WORKSPACE" "$LISTED")
     if [ -n "$MISSING" ]; then
       echo "WORKSPACE_COVERAGE_INCOMPLETE: 以下工作区文件未出现在 $INPUT 的 Changed Files 段："
       echo "$MISSING"
       rm -f "$INPUT"        # 删除半成品 review-input，禁止写盘后兜底
       exit 1                 # 返回 INPUT_INCOMPLETE；reviewer 不得继续执行
     fi
     # 4) 逆向检测：Changed Files 列出的路径必须存在于工作区（v0.0.1 animator task-02 CR-1）
     STALE=$(comm -23 "$LISTED" "$WORKSPACE")
     if [ -n "$STALE" ]; then
       echo "STALE_REVIEW_INPUT_CROSS_FEATURE: Changed Files 包含工作区不存在的历史/跨 feature 路径:"
       echo "$STALE"
       rm -f "$INPUT"
       exit 1
     fi
     ```
   - **强制动作**：差集非空 → **立即删除本次 `review-input-*.md`** 并以 `INPUT_INCOMPLETE` 信号退回 developing 阶段重新生成；**不允许 reviewer 以"其他段落信息足够"为由兜底推进**，这一豁免通道本身就是 task-12 C1 跨 round 多次复现的根因。
3. **scope 交集校验**：对当前 `tasks/task-NN.md` 的 `新增` / `modify` 清单，计算：
   ```
   I = intersection(task_scope_files, git diff + git status)
   ```
   - `I == ∅` → 输入生成失败，**禁止写盘**，回退至 developing；
   - Changed Files 包含上一 task（task-(N-1)）的核心实现文件且当前 task 核心文件缺位 → 视为跨 task diff 污染，同样回退。
4. **Test Results Summary 本包/总计数标注**：`## Test Results Summary` 段必须同时包含：
   - 本包测试数（格式示例 `game_net_tests: N/N`）
   - 仓库总测试数（格式示例 `repo_total: M/M`）
   - 两者任一缺失视同输入不完整，阻断 reviewer 阶段。
5. **顶层独立 `## Gate Results` 段（task-12 round-14 CR-1 / CR-2，task-32 C1 RECURRING）**：写盘前，生成侧必须在 `review-input-*.md` 顶层追加独立的 `## Gate Results` 段（不得嵌入 `## Changed Files` diff 内部或迭代日志叙述），字段至少包含：

   ```
   ## Gate Results

   tracked: <N>              # git diff --name-only 条数
   untracked: <N>            # git status --short --untracked-files=all 中 ?? 条数
   listed: <N>               # review-input 的 ## Changed Files 所列文件数
   missing: <N>              # 工作区存在但 Changed Files 未列出的差集条数（必须为 0）
   scope_intersection: <N>   # |task_scope_files ∩ (git diff ∪ git status)|（必须 ≥ 1）
   status: PASS | WORKSPACE_COVERAGE_INCOMPLETE | SCOPE_INTERSECTION_EMPTY | VERIFY_COMMANDS_NOT_RUN
   ```

   - `missing ≠ 0` 或 `scope_intersection == 0` → 拒绝写盘，删除半成品 `review-input-*.md`，以对应信号退回 developing；
   - 任一字段缺失 / 嵌入在 diff hunk 或段落叙述中 / 格式不可机械解析 → 视同 `Gate Results` 未落地，reviewer 直接判输入不完整阻断；
   - 同一 `review-input-*.md` 中若 `Gate Results` 与 `Changed Files` 计数口径矛盾（例如 `listed` 与 `## Changed Files` 实际条数不符），同样判输入不完整。
   - **[task-32 C1] 顶层 Section 结构预检（写盘前强制）**：`## Gate Results` 必须是**顶层 section 标题**（行首 `## ` 开头、前一空行位于段落边界、不处于代码块 / 引用块 / diff hunk 内）。以下情形均判 `GATE_RESULTS_NOT_TOPLEVEL`：
     - 出现在 ```` ``` ```` / ` ``` ` 代码围栏内部；
     - 出现在 `diff --git` 行之后、下一个 `## ` 顶层段之前的 diff hunk 区域（典型：被当作某个改动文件的 diff 内容贴入）；
     - 列表缩进下的 `  ## Gate Results` / `> ## Gate Results` 等伪 section；
     - `## Gate Results` 之后紧跟的不是 `tracked:` / `untracked:` ... 等键值行，而是另一个 diff hunk 或表格。
   - **结构预检脚本（写盘前必跑）**：

     ```bash
     INPUT=Docs/Version/<version>/<feature>/review-input-develop.md
     # 抽取顶层 section 行（忽略代码围栏与 diff hunk 内部）
     TOPLEVEL=$(awk '
       /^```/      { fence=!fence; next }
       /^diff --git/ { indiff=1; next }
       /^## /      { if (!fence && !indiff) print NR": "$0; indiff=0 }
     ' "$INPUT")
     if ! echo "$TOPLEVEL" | grep -qE '^\s*[0-9]+: ## Gate Results\b'; then
       echo "GATE_RESULTS_NOT_TOPLEVEL: $INPUT 未在顶层出现 ## Gate Results"
       rm -f "$INPUT"
       exit 1
     fi
     # Gate Results 必须出现在 ## Changed Files 和 ## Git Diff --stat 之前（v0.0.1 animator task-11 CR）
     LINE_GR=$(echo "$TOPLEVEL" | grep -nE 'Gate Results'    | head -n1 | awk -F: '{print $1}')
     LINE_CF=$(echo "$TOPLEVEL" | grep -nE 'Changed Files'   | head -n1 | awk -F: '{print $1}')
     LINE_GD=$(echo "$TOPLEVEL" | grep -nE 'Git Diff --stat' | head -n1 | awk -F: '{print $1}')
     if [ -n "$LINE_CF" ] && [ -n "$LINE_GR" ] && [ "$LINE_GR" -gt "$LINE_CF" ]; then
       echo "GATE_RESULTS_NOT_TOPLEVEL: ## Gate Results 必须位于 ## Changed Files 之前"
       rm -f "$INPUT"
       exit 1
     fi
     if [ -n "$LINE_GD" ] && [ -n "$LINE_GR" ] && [ "$LINE_GR" -gt "$LINE_GD" ]; then
       echo "GATE_RESULTS_NOT_TOPLEVEL: ## Gate Results 必须位于 ## Git Diff --stat 之前（v0.0.1 animator task-11 CR）"
       rm -f "$INPUT"
       exit 1
     fi
     ```

   - 命中任一分支 → 立即删除半成品 `review-input-*.md` 并以 `GATE_RESULTS_NOT_TOPLEVEL` 退回 developing；reviewer 遇到此信号同样直接判 Critical [RECURRING] 阻断。

**阻断动作**：不得写盘进入 reviewer；日志必须打印阻断原因（`SCOPE_INTERSECTION_EMPTY` / `CROSS_TASK_DIFF_POLLUTION` / `TEST_SUMMARY_INCOMPLETE` / `WORKSPACE_COVERAGE_INCOMPLETE` / `GATE_RESULTS_MISSING`）并指向需修正的 task / commit。

**权威语义来源**：`.ai/constitution/testing-review.md`「review-input diff 段落必须覆盖未跟踪核心产物与 task scope」+ `.ai/context/reviewer-brief.md` §零-B 第 4 / 5 条（reviewer 侧兜底）。

---

## 门禁 G3：task scope 与实际 diff 的交集非空（task-12 C1 RECURRING）

**触发条件**：进入 develop-review 分片执行前（独立于 G2，G2 是 review-input 生成侧；本门禁是 reviewer 启动前的二次校验）。

**机械检查**：

- 取 `tasks/task-NN.md` 声明的 `新增` / `modify` 文件清单 `S`；
- 取 `git diff --name-only` ∪ `git status --short --untracked-files=all` 三源合并的文件清单 `D`；
- 要求 `S ∩ D ≠ ∅`；
- 若 `task-NN.md` 将某个文件（如 `server.go`）列为核心交付物，但 `D` 中完全不存在该文件的改动 → 判定为"task scope 与 diff 脱钩"，**阻断 reviewer 阶段**。
- **`D` 的证据域只能是当前工作区（task-12 round-14 CR-1）**：严禁用 `git log`、历史 commit 列表、上一轮 reviewer 结论、迭代日志叙述或任何"联合历史"口径（典型如 `scope_intersection_check: "git_log_union_working_diff"`）将过去提交的文件伪装成本轮 diff；develop-review 的 `D` **只能**来自当前 `git diff --name-only ∪ git status --short --untracked-files=all`。若 `tasks/task-NN.md` 中 `scope_intersection_check` 字段值包含 `git log` / `history` / `union_*history*` / `base..HEAD` 等关键字，直接判阻断，不进入 reviewer。
- **acceptance review 的 `base..HEAD` 口径不可外溢**：已提交历史的验收只能在 **acceptance review** 阶段使用 `git diff base..HEAD --name-only` 作为证据域，且必须在 `review-input-acceptance.md` 顶层 `## Gate Results` 段显式标注 `review_phase: acceptance` + `base: <commit>`；develop-review 阶段读取 acceptance 口径一律判阻断。
- **联合历史口径必须被 grep 机械阻断（task-13 round-2 CR-2）**：进入 reviewer 前，必须对**本轮变更命中的** `tasks/task-*.md` 文件执行下列 grep；**任一命中**即判 `SCOPE_INTERSECTION_EMPTY` 并阻断，唯一豁免是当前输入文件名明确为 `review-input-acceptance.md`：

    ```bash
    # 在 feature 目录下执行；命中任一正则即视为 develop-review 场景下的 SCOPE_INTERSECTION_EMPTY
    INPUT_NAME=$(basename "$REVIEW_INPUT")   # review-input-develop.md | review-input-acceptance.md
    CHANGED_TASKS=$(git diff --name-only; git status --short --untracked-files=all | awk '{for(i=2;i<=NF;i++) print $i}')
    CHANGED_TASKS=$(echo "$CHANGED_TASKS" | grep -E 'tasks/task-[0-9]+\.md$' | sort -u)
    if [ -n "$CHANGED_TASKS" ] && [ "$INPUT_NAME" != "review-input-acceptance.md" ]; then
      HITS=$(grep -nE 'scope_intersection_check|git_log_union_working_diff|git log --|base\.\.HEAD' $CHANGED_TASKS || true)
      if [ -n "$HITS" ]; then
        echo "SCOPE_INTERSECTION_EMPTY: develop-review 输入不得依赖联合历史口径："
        echo "$HITS"
        rm -f "$REVIEW_INPUT"   # 删除半成品，禁止写盘后兜底
        exit 1
      fi
    fi
    ```

    - `acceptance review` 走 `review-input-acceptance.md` 时才允许出现 `base..HEAD`，且仍须配合顶层 `## Gate Results` 段的 `review_phase: acceptance` + `base: <commit>` 字段；
    - develop-review 场景下命中任一关键字 → 立即删除 `review-input-develop.md`，回退 developing 修正 `tasks/task-NN.md`，不得通过 reviewer 兜底放行。

**阻断动作**：

1. 若 task 声明过时，回退至 plan / task 拆分阶段修正 `task-NN.md` 的 scope 声明；
2. 若 developer 漏交付核心文件，回退至 developing 阶段补交付；
3. 不得以"已有其他文件改动"为由放行 —— 核心交付物缺位是 Critical，非 Medium；
4. 不得通过修改 `scope_intersection_check` 计算域（改用历史/联合口径）自行放行 —— 生成器篡改计算域等同于绕过门禁，视为同轮 non-recoverable，直接回退到最近一次合规快照重跑。

**路由规则：核心文件已提交 → 切换 acceptance review（task-29 CR-2）**：

当 `tasks/task-NN.md` 声明的核心交付物已存在于 `git log` 但**不在**当前 `git diff --name-only ∪ git status --short --untracked-files=all` 内（典型特征：迭代日志显式指向历史 commit 如 `8e788796`，而当前 worktree 无对应文件改动），生成侧**禁止**再次回退 develop 补交付或重写 `review-input-develop.md` —— 核心文件已落盘到历史，不可能通过 developing 再产生新的工作区 diff，继续留在 develop-review 会无限死循环触发 `SCOPE_INTERSECTION_EMPTY`。此时**必须**切换阶段：

1. 不再生成 `review-input-develop.md`；若已存在则立即删除；
2. 生成 `review-input-acceptance.md`，证据域改用 `git diff base..HEAD --name-only`，其中 `base` 为核心文件入库前一个 commit；
3. 顶层 `## Gate Results` 段必须显式携带 `review_phase: acceptance` + `base: <commit>` 两个字段，且其他字段口径同步改为 acceptance 语义（`scope_intersection` 基于 `base..HEAD` 口径重算）；
4. 编排日志（`auto-work-log.md` / `develop-iteration-log-task-NN.md`）必须记录一行 `PHASE_SWITCH: develop-review → acceptance-review reason=core_file_already_committed commit=<hash>`，便于审计定位。

该路由只覆盖"核心文件已提交"这一单一触发条件。其他 `SCOPE_INTERSECTION_EMPTY` 成因（task 声明错误、developer 漏交付、跨 task 污染）仍按阻断动作 1-4 处置，不得借用本路由绕过 developing 阶段。

**权威语义来源**：task-12 develop-review-report-task-12.md C1 / C2 / M1 RECURRING；task-29 develop-review-report-task-29.md CR-2；`.ai/constitution/testing-review.md`「review-input diff 段落必须覆盖未跟踪核心产物与 task scope」第 3 条"生成侧必须阻断跨 task 污染"的推广形式。

---

## 门禁 G5：phase-switch 完整性与 stale develop-input 阻断（task-30 CR-1 触发）

**触发条件**：进入任一 `develop-review` / `acceptance-review` 分片前（独立于 G3，G3 定义"何时触发切换 acceptance"的路由规则，本门禁定义"切换后必须把旧 develop-input 从工作区清理干净"的强 enforcement）。

**机械检查**：

- 读取当前 `tasks/task-NN.md`，提取 `review_phase` 字段；
- 若 `review_phase: acceptance`，当前 feature 目录下**必须不存在** `review-input-develop.md`（无论跟踪态 `M` / 未跟踪态 `??` / 已删除未提交态 `D` 都算存在性残留——`git status --short` 看得到即视为存在）；
- 同一 task 不得同时持有 `review-input-develop.md` 与 `review-input-acceptance*.md`，并存即 phase-switch 未完成；
- 可直接复用的检测脚本：

    ```bash
    # 在 feature 目录下执行；任一分支命中即判 STALE_DEVELOP_INPUT_AFTER_PHASE_SWITCH
    TASK=tasks/task-NN.md
    PHASE=$(awk -F': *' '/^review_phase:/{print $2; exit}' "$TASK")
    DEV_INPUT=review-input-develop.md
    ACC_INPUT=$(ls review-input-acceptance*.md 2>/dev/null | head -n1)
    if [ "$PHASE" = "acceptance" ] && { [ -f "$DEV_INPUT" ] || git status --short -- "$DEV_INPUT" | grep -q .; }; then
      echo "STALE_DEVELOP_INPUT_AFTER_PHASE_SWITCH: $DEV_INPUT still present while $TASK declares review_phase=acceptance"
      exit 1
    fi
    if [ -n "$ACC_INPUT" ] && [ -f "$DEV_INPUT" ]; then
      echo "STALE_DEVELOP_INPUT_AFTER_PHASE_SWITCH: $DEV_INPUT coexists with $ACC_INPUT"
      exit 1
    fi
    ```

**阻断动作**：

1. 立即删除工作区内遗留的 `review-input-develop.md`（补执行 G3「路由规则：核心文件已提交 → 切换 acceptance review」应完成而未完成的清理动作）；
2. 以 `STALE_DEVELOP_INPUT_AFTER_PHASE_SWITCH` 信号阻断 reviewer 阶段，**本轮 non-recoverable**——不得以"reviewer 报告已标注异常"或"acceptance input 同时存在"为由让 develop-review 继续推进；
3. 清理完成后，仅从清理后的 worktree 快照重新生成 `review-input-acceptance*.md`，再以 acceptance 身份进入 reviewer；
4. 编排日志（`auto-work-log.md` / `develop-iteration-log-task-NN.md`）必须追加一行 `PHASE_SWITCH_CLEANUP: removed stale review-input-develop.md reason=review_phase=acceptance task=task-NN`，便于跨轮审计。

**权威语义来源**：task-30 develop-review-report-task-30.md CR-1；`.ai/context/auto-work-gates.md` G3「路由规则：核心文件已提交 → 切换 acceptance review」的 enforcement 补齐；`.ai/context/reviewer-brief.md` §零-B 第 7 条（审查侧兜底）。

---

## 门禁 G6：写盘后的 review-input 再校验（task-32 Round 3+ CR-1 触发）

**触发条件**：`review-input-develop.md` / `review-input-acceptance*.md` **已经落盘**、编排层准备调用 reviewer 分片之前。本门禁独立于 G2（G2 是写盘前的生成侧自检），目的是防止"生成侧自检口径与真实落盘文件脱钩"——即生成器逻辑校验通过但写出的文本仍不合规（结构丢失、差集未覆盖、task 文件残留历史口径等）。task-32 Round 3+ 的 C1 / C2 / C3 `[RECURRING]` 均由"写盘前 pass、但文件实际不合规 → reviewer 兜底"造成，证明 G2 的写盘前口径必须配套一道写盘后复核。

**机械检查**（按序执行，任一失败即立即阻断）：

1. **重新打开最终 `review-input-*.md`**（不得复用 G2 阶段的内存缓冲）：
   - 必须使用 `cat` / `awk` / 相同的解析器从磁盘再次读取；
   - 与 G2 阶段保存的预期 `Gate Results` 计数块逐字节比对，不一致即判 `GATE_RESULTS_WRITE_SKEW`。
2. **顶层 `## Gate Results` 结构复核**：复用 G2 第 5 子项的 awk 脚本（忽略代码围栏与 diff hunk）确认 `## Gate Results` 是顶层 section 且位于 `## Changed Files` / `## Git Diff --stat` 之前；任一失败即 `GATE_RESULTS_NOT_TOPLEVEL`。
3. **`diff --git` hunk 数量与工作区对齐**：统计落盘文件内 `^diff --git ` 行数，与 `git diff --name-only ∪ git status --short --untracked-files=all` 的 tracked 条目数比较——缺一即 `WORKSPACE_COVERAGE_INCOMPLETE`；未跟踪（`??`）条目必须在 `## Changed Files` 段以显式列表 / 占位块列出，不能以 diff 缺失为由豁免。
4. **task 文件历史口径扫描**：对本轮所有被修改 / 新增 / 未跟踪的 `tasks/task-*.md`（当前 worktree 内）grep 下列关键字，命中即 `SCOPE_INTERSECTION_EMPTY`：
   - `scope_intersection_check: *"?git_log_union_working_diff"?`
   - `git log --`
   - `base\.\.HEAD`（仅 `review-input-acceptance*.md` 场景豁免，且必须同时携带顶层 `review_phase: acceptance` + `base: <commit>`）。
5. **迭代日志 FIXED 声称 × 落盘 review-input 交叉核对（v0.0.1 animator task-03 round 4 C1 / C2 RECURRING）**：`develop-iteration-log-task-NN.md` 的 FIXED 声明不得作为合规证据，必须逐条与落盘 `review-input-*.md` 实际内容比对；任一不一致即判 `FIXED_CLAIM_MISMATCH` 并删除半成品回退 developing。必须核对的对照集至少包含：

   | 日志声称 | 落盘文件实际检查 | 不一致信号 |
   |---------|------------------|-----------|
   | "Gate Results 已加入" / "顶层 `## Gate Results` 已补" | awk 扫描顶层 section（忽略代码围栏 / diff hunk）实际存在 `## Gate Results` 行 | `GATE_RESULTS_NOT_TOPLEVEL` + `FIXED_CLAIM_MISMATCH` |
   | "三源已重采 / 从 `git -C <repo-root>` baseline 重新生成" | `diff --git` hunk 数量 ≥ `git diff --name-only` 条数，且所列 hunk 路径与当前 repo 根一致（无跨 feature 串味） | `STALE_REVIEW_INPUT_CROSS_FEATURE` + `FIXED_CLAIM_MISMATCH` |
   | "未跟踪核心产物已列入 `## Changed Files`" | `comm -23 <工作区文件清单> <Changed Files 列出文件清单>` 空集 | `WORKSPACE_COVERAGE_INCOMPLETE` + `FIXED_CLAIM_MISMATCH` |
   | "task scope 与 diff 交集已非空" / "核心交付物已纳入本轮 diff" | `task scope_files ∩ (git diff ∪ git status) ≠ ∅`，且路径指向本轮 `task-NN.md` | `SCOPE_INTERSECTION_EMPTY` + `FIXED_CLAIM_MISMATCH` |
   | "`-race` 已执行" / "stress fallback 已跑" | `review-input-*.md` 含具名 `go test -race` / stress 用例命令与 stdout 片段 | `VERIFY_COMMANDS_NOT_RUN` + `FIXED_CLAIM_MISMATCH` |
   | "headless 已通过" / "`godot --headless` 已跑" / "`AnimationPlayer` 已驱动 `Skeleton3D`" / "场景 load/实例化通过" / "`verify_*.gd` 已覆盖 Cx/Hx" 类声称（v0.0.1 animator task-01 round 5 CR-3）| `## Test Results Summary` 任一包 / 总计数 **不得**为 `0/0 passed`；必须携带具名测试的**实际命令**、**退出码**、**关键 stdout/stderr 片段**三项证据（与 `-race` 同级）；环境缺失则必须改写为 `[ENVIRONMENT_MISSING: godot]` 并撤销 `FIXED` | `FIXED_CLAIM_MISMATCH` + `TEST_RESULTS_ZERO_ZERO_WITH_FIX_CLAIM` |

   - 强制动作：任一对照失败 → **立即删除** `review-input-*.md`，以 `FIXED_CLAIM_MISMATCH` 信号退回 developing；validator stdout 必须同时列出"log 原文声称"与"磁盘实际结果"两列，便于下轮 reviewer / 编排层审计；
   - 本条不可与第 1-4 项互斥豁免："日志声称 FIXED 但磁盘实际不合规"是 task-03 round 4 C1 / C2 同轮 RECURRING 触发的唯一根因，跳过该对照即视为 G6 未闭环。
6. **task scope ∩ Changed Files 独立校验（v0.0.1 animator task-08 CR-1）**：G6 脚本除通过 Gate Results 字段值间接验证外，必须独立从 `tasks/task-NN.md` 提取核心 scope 文件并直接与落盘 `## Changed Files` 段内容比对（basename 匹配）；交集为空时触发 `SCOPE_INTERSECTION_EMPTY`、删除半成品 review-input 并退回 developing。防两类场景：(a) `## Gate Results` 完全缺失时 scope 脱钩无法被间接发现；(b) Gate Results 存在但 `scope_intersection` 数值伪造。与 G6 section (e)「逆向 stale 路径检测」互补：(e) 防 Changed Files 包含工作区不存在的历史路径；本条防 task 核心产物在 Changed Files 中缺位。
7. **可直接执行的 post-write validator 脚本（模板）**：

    ```bash
    # 在 feature 目录下执行；任一 exit 非 0 即阻断 reviewer
    INPUT=Docs/Version/<version>/<feature>/review-input-develop.md
    [ -f "$INPUT" ] || { echo "POST_WRITE_VALIDATOR: $INPUT missing"; exit 1; }

    # (a) Gate Results 顶层结构复核
    awk '
      /^```/      { fence=!fence; next }
      /^diff --git/ { indiff=1; next }
      /^## /      { if (!fence && !indiff) print NR": "$0; indiff=0 }
    ' "$INPUT" | tee /tmp/toplevel.$$
    grep -qE '^[0-9]+: ## Gate Results\b' /tmp/toplevel.$$ \
      || { echo "GATE_RESULTS_NOT_TOPLEVEL"; rm -f "$INPUT"; exit 1; }
    LINE_GR=$(grep -nE 'Gate Results'    /tmp/toplevel.$$ | head -n1 | awk -F: '{print $1}')
    LINE_CF=$(grep -nE 'Changed Files'   /tmp/toplevel.$$ | head -n1 | awk -F: '{print $1}')
    LINE_GD=$(grep -nE 'Git Diff --stat' /tmp/toplevel.$$ | head -n1 | awk -F: '{print $1}')
    [ -n "$LINE_CF" ] && [ -n "$LINE_GR" ] && [ "$LINE_GR" -gt "$LINE_CF" ] \
      && { echo "GATE_RESULTS_NOT_TOPLEVEL: Gate Results 必须在 ## Changed Files 之前"; rm -f "$INPUT"; exit 1; }
    [ -n "$LINE_GD" ] && [ -n "$LINE_GR" ] && [ "$LINE_GR" -gt "$LINE_GD" ] \
      && { echo "GATE_RESULTS_NOT_TOPLEVEL: Gate Results 必须在 ## Git Diff --stat 之前（v0.0.1 animator task-11 CR）"; rm -f "$INPUT"; exit 1; }

    # (a2) ## Gate Results 字段值强制校验（v0.0.1 animator task-11 CR）
    # 从文件提取 missing / scope_intersection 并验证值，防止生成侧仅写结构却填错数值
    GR_MISSING=$(awk '/^## Gate Results/,/^## [^G]/' "$INPUT" | grep -E '^missing:' | head -1 | awk '{print $2}')
    GR_SI=$(awk '/^## Gate Results/,/^## [^G]/' "$INPUT" | grep -E '^scope_intersection:' | head -1 | awk '{print $2}')
    if [ -n "$GR_MISSING" ] && [ "$GR_MISSING" != "0" ]; then
      echo "WORKSPACE_COVERAGE_INCOMPLETE: Gate Results.missing=$GR_MISSING (必须=0)"; rm -f "$INPUT"; exit 1
    fi
    if [ -n "$GR_SI" ] && [ "$GR_SI" -le 0 ] 2>/dev/null; then
      echo "SCOPE_INTERSECTION_EMPTY: Gate Results.scope_intersection=$GR_SI (必须≥1)"; rm -f "$INPUT"; exit 1
    fi

    # (b) diff --git hunk 数量与工作区对齐
    HUNK=$(grep -cE '^diff --git ' "$INPUT")
    TRACKED=$(git diff --name-only | wc -l)
    [ "$HUNK" -lt "$TRACKED" ] && { echo "WORKSPACE_COVERAGE_INCOMPLETE: diff hunks=$HUNK < tracked=$TRACKED"; rm -f "$INPUT"; exit 1; }

    # (c) tasks/task-*.md 历史口径 grep
    CHANGED_TASKS=$({ git diff --name-only; git status --short --untracked-files=all | awk '{for(i=2;i<=NF;i++) print $i}'; } \
      | grep -E 'tasks/task-[0-9]+\.md$' | sort -u)
    INPUT_NAME=$(basename "$INPUT")
    if [ -n "$CHANGED_TASKS" ] && [ "$INPUT_NAME" != "review-input-acceptance.md" ]; then
      HITS=$(grep -nE 'scope_intersection_check|git_log_union_working_diff|git log --|base\.\.HEAD' $CHANGED_TASKS || true)
      [ -n "$HITS" ] && { echo "SCOPE_INTERSECTION_EMPTY: task 文件残留历史口径"; echo "$HITS"; rm -f "$INPUT"; exit 1; }
    fi

    # (d) 迭代日志 FIXED 声称 × 落盘 review-input 交叉核对（v0.0.1 animator task-03 round 4 CR-1/CR-2）
    TASK_NN=$(basename "$INPUT" | sed -E 's/.*task-([0-9]+).*/\1/')
    ITER_LOG=$(dirname "$INPUT")/develop-iteration-log-task-${TASK_NN}.md
    if [ -f "$ITER_LOG" ]; then
      # 声称 "Gate Results 已加入" → 必须真的有顶层 Gate Results
      if grep -qE 'Gate Results.*(已加入|已补|FIXED|已落地)' "$ITER_LOG" \
         && ! grep -qE '^[0-9]+: ## Gate Results\b' /tmp/toplevel.$$; then
        echo "FIXED_CLAIM_MISMATCH: 迭代日志声称 Gate Results 已落地，但落盘 review-input 顶层无该 section"
        rm -f "$INPUT"; exit 1
      fi
      # 声称 "未跟踪核心产物已列入 Changed Files" → 必须覆盖率 100%
      if grep -qE '(未跟踪|untracked|核心产物|交付物).*(已列入|已加入|FIXED)' "$ITER_LOG"; then
        WORKSPACE=$(mktemp); LISTED=$(mktemp)
        { git diff --name-only; \
          git status --short --untracked-files=all | awk '{for(i=2;i<=NF;i++) print $i}'; \
        } | sort -u > "$WORKSPACE"
        awk '/^## Changed Files/{flag=1;next} /^## /{flag=0} flag' "$INPUT" \
          | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+|[A-Za-z0-9_./-]+/' \
          | sort -u > "$LISTED"
        MISSING=$(comm -23 "$WORKSPACE" "$LISTED")
        if [ -n "$MISSING" ]; then
          echo "FIXED_CLAIM_MISMATCH: 迭代日志声称未跟踪产物已列入，但工作区文件仍缺:"
          echo "$MISSING"
          rm -f "$INPUT"; exit 1
        fi
      fi
      # 声称 "-race 已执行" → review-input 必须含 go test -race 片段
      if grep -qE '(-race|race detector|stress.*fallback).*(已执行|已跑|FIXED)' "$ITER_LOG" \
         && ! grep -qE 'go test.*-race|go test.*stress' "$INPUT"; then
        echo "FIXED_CLAIM_MISMATCH: 迭代日志声称 -race 已跑，但 review-input 无对应命令/输出证据"
        rm -f "$INPUT"; exit 1
      fi
      # 声称 "headless / Godot / verify_*.gd / AnimationPlayer / 场景实例化 已通过"
      # → review-input 的 ## Test Results Summary 不得为 0/0 passed（v0.0.1 animator task-01 round 5 CR-3）
      if grep -qE '(headless|godot --headless|Skeleton3D|AnimationPlayer|verify_[A-Za-z0-9_]+\.gd|场景.*(load|实例化|渲染)).*(已通过|已跑|已覆盖|FIXED)' "$ITER_LOG"; then
        TRS=$(awk '/^## Test Results Summary/,/^## [^T]/' "$INPUT")
        if ! echo "$TRS" | grep -qE '[1-9][0-9]*/[1-9][0-9]* passed'; then
          echo "FIXED_CLAIM_MISMATCH: 迭代日志声称 headless/测试验证已完成，但 ## Test Results Summary 仍为 0/0 passed 或缺失"
          echo "$TRS"
          rm -f "$INPUT"; exit 1
        fi
        # 必须含命令 / 退出码 / 关键输出三项
        if ! echo "$TRS" | grep -qE 'godot .*--headless|godot --script|go test |pytest |jest ' \
           || ! echo "$TRS" | grep -qE 'exit(_code)?[:=]? *[0-9]+|rc=|RC=|return code' \
           || ! echo "$TRS" | grep -qE 'PASS|OK|stdout|stderr|output|tracks/|Skeleton3D|MeshInstance3D'; then
          echo "FIXED_CLAIM_MISMATCH: 依赖 headless/测试的 FIXED 声称缺少完整三项证据（命令/退出码/关键 stdout）"
          rm -f "$INPUT"; exit 1
        fi
      fi
    fi

    # (e) 逆向 stale 路径检测（v0.0.1 animator task-02 CR-1 RECURRING）
    LF=$(mktemp); WF=$(mktemp)
    awk '/^## Changed Files/{flag=1;next} /^## /{flag=0} flag' "$INPUT" \
      | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+|[A-Za-z0-9_./-]+/' | sort -u > "$LF"
    { git diff --name-only; git status --short --untracked-files=all | awk '{for(i=2;i<=NF;i++) print $i}'; } \
      | sort -u > "$WF"
    STALE=$(comm -23 "$LF" "$WF")
    if [ -n "$STALE" ]; then
      echo "STALE_REVIEW_INPUT_CROSS_FEATURE: Changed Files 包含工作区不存在的历史/跨 feature 路径:"
      echo "$STALE"
      rm -f "$INPUT" "$LF" "$WF"; exit 1
    fi
    rm -f "$LF" "$WF"

    # (f) task scope ∩ Changed Files 独立校验（v0.0.1 animator task-08 CR-1）
    # 不依赖 Gate Results 数值；防 Gate Results 缺失或伪造时 scope 脱钩被漏判
    TASK_NUM_F=$(echo "$INPUT" | grep -oE 'task-[0-9]+' | tail -1 | grep -oE '[0-9]+')
    if [ -n "$TASK_NUM_F" ]; then
      TASK_FILE_F=$(find . -name "task-${TASK_NUM_F}.md" -path "*/tasks/*" 2>/dev/null | head -n1)
      if [ -n "$TASK_FILE_F" ]; then
        SCOPE_F=$(grep -oE '[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)+\.[A-Za-z0-9]+' "$TASK_FILE_F" | sort -u)
        CHANGED_F=$(awk '/^## Changed Files/{flag=1;next} /^## /{flag=0} flag' "$INPUT")
        if [ -n "$SCOPE_F" ]; then
          HIT_F=0
          while IFS= read -r sp; do
            [ -z "$sp" ] && continue
            BN=$(basename "$sp")
            echo "$CHANGED_F" | grep -qF "$BN" && { HIT_F=1; break; }
          done <<< "$SCOPE_F"
          if [ "$HIT_F" -eq 0 ]; then
            echo "SCOPE_INTERSECTION_EMPTY: ## Changed Files 无 task scope 核心文件（v0.0.1 animator task-08 CR-1）"
            echo "  task: $TASK_FILE_F"
            echo "  scope_sample: $(echo "$SCOPE_F" | head -5)"
            rm -f "$INPUT"; exit 1
          fi
        fi
      fi
    fi

    echo "POST_WRITE_VALIDATOR: PASS"
    ```

**强制动作**：

- validator 的 **stdout 全量**必须逐字追加到 `develop-iteration-log-task-NN.md` / `auto-work-log.md` 末尾作为执行证据——这是"文档化事实 ≠ 修复"反模式的唯一反证；
- exit ≠ 0 时，编排层**禁止**在迭代日志写 `status=PASS`、**禁止**调用 reviewer；必须以对应信号（`GATE_RESULTS_NOT_TOPLEVEL` / `WORKSPACE_COVERAGE_INCOMPLETE` / `SCOPE_INTERSECTION_EMPTY` / `GATE_RESULTS_WRITE_SKEW`）退回 developing；
- 本门禁与 G2 **不可互相豁免**：G2 写盘前通过 ≠ G6 写盘后通过。reviewer 侧遇到"日志声明 G2 PASS 但 G6 未执行"时直接判 `POST_WRITE_VALIDATOR_MISSING` Critical [RECURRING]。

**权威语义来源**：`.ai/constitution.md` §4「文档化事实 ≠ 修复缺陷」「`review-input-*.md` 必须含顶层独立 `## Gate Results` 段」「review-input 工作区覆盖率必须 100%」「scope 交集的证据域只能是当前工作区」；task-32 develop-review-report-task-32.md Round 3+ C1 / C2 / C3 `[RECURRING]`。

---

## 门禁 G4：Context Repair ack 日志（task-11 CR-1 触发）

**触发条件**：develop 执行单元（`claude -p` / Agent）进入 `review-input-develop.md` 生成前。

**机械检查**：

- 读取当前 feature 最新的 `develop-review-report-task-*.md` 的 `## Context Repairs` 段；
- 对每条 CR 的"目标文件"生成一行 `已读取 <文件路径>，本轮产物中已规避 <规则名>` 的 ack 日志，写入 `develop-iteration-log-task-NN.md` 或 `develop-log.md`；
- 缺 ack → 阻断进入 reviewer。

**权威语义来源**：`.ai/constitution/testing-review.md`「Developer 侧预检清单」第 1 条。

---

## 门禁 G7：gate 文档 shell 模板必须通过 `bash -n` 语法预检后方可引用（v0.0.1 animator task-11 C3）

**触发条件**：任何向 `.ai/context/auto-work-gates.md` / `.ai/constitution/*.md` / `.claude/commands/*.md` / `.claude/rules/*.md` 新增或修改可运行 shell 代码块的变更，且该代码块被引用为"权威门禁/enforcement fix 模板"。

**机械检查**（变更写盘前执行）：

```bash
# 将新增/修改的 shell snippet 写入临时文件，执行 bash -n 语法检查
cat > /tmp/gate_snippet_check.sh << 'EOF'
# 粘贴完整 shell 代码块
EOF
bash -n /tmp/gate_snippet_check.sh && echo "SYNTAX_OK" || { echo "SHELL_TEMPLATE_SYNTAX_ERROR"; exit 1; }
```

**规则**：
- `bash -n` 检查命令与被检查 snippet 必须**出现在同一变更（commit / session）中**，不得"先引用再补验证"；
- 未附 `bash -n` 通过证据的 shell 模板引用：reviewer 侧判 `SHELL_TEMPLATE_SYNTAX_UNVERIFIED` Medium；连续两轮 RECURRING → High；
- G6 validator 及 G2 结构预检脚本中的每个 echo 字符串必须在完整闭合引号内，中文全角括号 `（）` 不替代双引号闭合；

**背景（task-11 C3 实证）**：`.ai/context/auto-work-gates.md` G2 和 G6 两处 shell snippet 被 reviewer 识别为"echo 字符串未闭合"，导致任何复制粘贴执行该模板的 runner 遭遇 shell parse error 而非输出预期信号，门禁形同虚设。G7 确保此类问题在落地时即被拦截，而非等到执行时才发现。

**阻断动作**：`bash -n` 返回非零 → 禁止将该 snippet 标记为权威模板、禁止写入权威文档；修正并通过 `bash -n` 后方可落地。

---

## 门禁 G8：Godot 资源装配内容核验（develop 写盘前 + 写盘后）（v0.0.1 animator task-01 round 2 C2 + M1 RECURRING 触发）

**触发条件**（任一命中，按 task scope 判定）：

1. task 交付 `animation_library.tres` / `animation_library.res` / `AnimationLibrary` 资源；
2. task scope 含 plan / task / 权威映射文档 (`*-asset-import.md` / `*-animator.md` / `plan.md` / `plan/*.md` / `task-*.md`) 且文档内声称"已填写 / 已核实 / 已回填 / 已确认"节点名、骨骼路径、ArmatureNode、Skeleton3D / MeshInstance3D 映射；
3. 上轮 `develop-review-report-*.md` 已标注 `STUB_ANIMATION_LIBRARY` 或 `AUTHORITY_MAPPING_PLACEHOLDER_RESIDUAL` 且本轮仍在同一 task。

**机械检查**（`review-input-*.md` 生成后、写盘前；G6 post-write validator 亦必须复用同一脚本核对落盘文件）：

（a）**AnimationLibrary 伪真实轨道扫描**：task 交付 `animation_library.tres` 时：
- 必须至少有一条非 Root 骨骼路径：`grep -cE 'NodePath\("Rig/Skeleton3D:[^R][^o]' <animation_library.tres>` ≥ 1，否则判 `STUB_ANIMATION_LIBRARY`（全库仅 `Rig/Skeleton3D:Root` 轨道即视同单轨道伪真实，即便每条动画都含 `tracks/*` 子节）；
- 全库 key 数据不得退化为同一组常量：抽取 `PackedFloat32Array(...)` 字段 `sort -u | wc -l`，条目 ≥ 2 且 unique == 1 → 判 `STUB_ANIMATION_LIBRARY`；
- verify 脚本不得以 `get_track_count() > 0` 作为通过门槛；必须同时断言 (i) 非 Root 骨骼路径存在 + (ii) 全库 key 非唯一常量 + (iii) `get_track_count() ≥ 2` 或至少 1 条非 `position_3d` 轨道。仅 `track_count > 0` 视为"只计轨道数不核内容"，一律判 STUB。

（b）**权威映射文档 "已填写/已核实" × 占位符残留双向扫描**：对本轮变更命中的 plan / task / asset-import / mapping 文档执行：
- `CLAIM = grep -cE '已填写|已核实|已回填|已确认' <doc>`
- `PLACE = grep -cE '<[A-Z][A-Za-z0-9_]+>|首次 Godot 打开后确认|待验证字段|待填写|TBD' <doc>`
- `CLAIM ≥ 1` 且 `PLACE ≥ 1` → 判 `AUTHORITY_MAPPING_PLACEHOLDER_RESIDUAL`；禁止放行"声称已填但正文仍是 `<ArmatureNode>`"的伪闭环状态。下游 AnimationTree / `.gd` 消费该映射时会继续依赖猜测路径。

**可直接执行的 G8 脚本（写盘前 + G6 post-write 复用）**：

```bash
# 在 feature 目录下执行；任一 exit 非 0 即阻断 reviewer
# 依赖：当前 worktree 为 feature repo root；tasks/task-NN.md 已定位
TASK=tasks/task-NN.md

# (a) AnimationLibrary 伪真实轨道扫描
ANIM_RES=$(grep -oE '[A-Za-z0-9_./-]+animation_library\.tres' "$TASK" 2>/dev/null | head -n1)
if [ -n "$ANIM_RES" ] && [ -f "$ANIM_RES" ]; then
  NON_ROOT=$(grep -cE 'NodePath\("Rig/Skeleton3D:[^R][^o]' "$ANIM_RES" || true)
  if [ "$NON_ROOT" -lt 1 ] 2>/dev/null; then
    echo "STUB_ANIMATION_LIBRARY: $ANIM_RES 全库仅有 Rig/Skeleton3D:Root 轨道，缺非根骨骼轨道"
    exit 1
  fi
  UNIQUE_KEYS=$(grep -oE 'PackedFloat32Array\([^)]*\)' "$ANIM_RES" | sort -u | wc -l)
  TOTAL_KEYS=$(grep -cE 'PackedFloat32Array\(' "$ANIM_RES" || true)
  if [ "$TOTAL_KEYS" -ge 2 ] && [ "$UNIQUE_KEYS" -eq 1 ] 2>/dev/null; then
    echo "STUB_ANIMATION_LIBRARY: $ANIM_RES 全库 key 数据退化为同一组常量（$UNIQUE_KEYS 种 / $TOTAL_KEYS 条）"
    exit 1
  fi
fi

# (b) 权威映射文档 已填写/已核实 × 占位符残留双向扫描
MAP_DOCS=$(git diff --name-only; git status --short --untracked-files=all | awk '{for(i=2;i<=NF;i++) print $i}')
MAP_DOCS=$(echo "$MAP_DOCS" | grep -E '(plan|task|mapping|asset-import|animator)\.md$' | sort -u)
for d in $MAP_DOCS; do
  [ -f "$d" ] || continue
  CLAIM=$(grep -cE '已填写|已核实|已回填|已确认' "$d" || true)
  PLACE=$(grep -cE '<[A-Z][A-Za-z0-9_]+>|首次 Godot 打开后确认|待验证字段|待填写|TBD' "$d" || true)
  if [ "$CLAIM" -ge 1 ] && [ "$PLACE" -ge 1 ] 2>/dev/null; then
    echo "AUTHORITY_MAPPING_PLACEHOLDER_RESIDUAL: $d 声称已填写但仍含占位符"
    grep -nE '<[A-Z][A-Za-z0-9_]+>|首次 Godot 打开后确认|待验证字段|待填写|TBD' "$d" | head -5
    exit 1
  fi
done
echo "G8: PASS"
```

**强制动作**：

- 写盘前触发：立即删除半成品 `review-input-*.md`，以 `STUB_ANIMATION_LIBRARY` / `AUTHORITY_MAPPING_PLACEHOLDER_RESIDUAL` 信号退回 developing。修复路径：(a) 用 Godot 对真实 FBX 动画重新导入并保存 `.tres`，确保抽样动画包含非 Root 骨骼轨道 + 非零差异 key；(b) 回填占位符为真实 Armature / Skeleton3D / Root Bone 节点名，或显式标注"待验证"并拆分为独立后续 task 明确承接。
- 写盘后触发（G6 post-write validator 复用本脚本）：同样删除半成品、退回 developing，reviewer 遇到"G2 PASS 但 G8 未执行" → 直接判 `POST_WRITE_VALIDATOR_MISSING` + `STUB_ANIMATION_LIBRARY` Critical [RECURRING]。
- 本门禁与 G1 / G2 **不可互相豁免**：G1 只核 verify_commands 字面形态，G2 只核 review-input 结构/覆盖率，G8 核资源内容与权威映射占位符；三者任一失败都阻断进入 reviewer。

**权威语义来源**：`.ai/constitution/testing-review.md §Godot 资源装配非空轨道核验`（第 1 条非根骨骼轨道强制 + 全库禁止退化常量 + verify 脚本断言升级；第 4 条"已填写/已核实"× 占位符残留双向扫描）；`.ai/constitution.md §4` 对应新增 bullet。

---

## 阻断信号落地位置（核心设计）

`.claude/commands/auto-work.md` 因权限限制无法直接承载这些门禁规则时，遵循以下顺序定位权威：

1. **本文件 `.ai/context/auto-work-gates.md`** —— 权威机械清单（本文件，全 agent 可读）。
2. **`.ai/constitution.md` §4 + `.ai/constitution/testing-review.md`** —— 宪法级语义。
3. **`.ai/context/reviewer-brief.md` §零-B** —— reviewer 侧兜底规则。
4. **`.claude/commands/auto-work.md` Triple-Check Gate** —— 在权限窗口开放时仅引用本文件，不重复语义。

**引用模板**（`.claude/commands/auto-work.md` 下一次编辑时使用）：

```markdown
**收敛前必跑清单（Triple-Check Gate）：**
- ...（原有条目保留）
- **生成侧机械门禁（写盘前）**：生成 `review-input-*.md` 前按 `.ai/context/auto-work-gates.md` 全量执行 G1 / G2 / G3 / G4 / G5 五条门禁，任一不满足即阻断，不得降级。
- **生成侧机械门禁（写盘后）**：`review-input-*.md` 落盘后、调用 reviewer 前必须执行 G6「post-write validator」；validator 的 stdout 必须逐字追加到 `develop-iteration-log-task-NN.md` 末尾；exit ≠ 0 时禁止在迭代日志写 `status=PASS`、禁止进入 reviewer 分片。
```

---

## 维护约定

- 新增门禁时，必须同时在 `.ai/constitution/testing-review.md` 或 `.ai/context/reviewer-brief.md` 补齐语义层规则；本文件只承载"可机械执行清单"，不承载语义论证。
- 门禁编号 `G1..Gn` 一旦分配不得复用，弃用时改写为 `G?-DEPRECATED` 并保留说明。
- 触发条件与阻断动作必须可机械判定（shell / grep / wc 可执行），避免"需要人工判断"的表述。
