# CLI 调用 Trace（可观测性）

auto-work 系列脚本（`auto-work-loop.sh`、`feature-plan-loop.sh`、`feature-develop-loop.sh`、`research-loop.sh`）的所有 `claude -p` / `codex exec` 调用都通过 `.claude/scripts/cli-trace-helpers.sh` 中的 Bash helper 执行，自动记录 JSONL trace。

## Trace 落盘位置
- `{FEATURE_DIR}/traces/*.jsonl`（由 `AUTO_WORK_FEATURE_DIR` 环境变量决定）
- 缺省回退到 `.claude/logs/traces/`
- 单文件超 10MB 自动按日期切片

## Trace 字段
每条 JSONL 记录包含：`ts`、`stage`、`task`、`round`、`cli`（claude/codex）、`model`、`prompt_file`（落盘副本路径）、`prompt_sha256`、`prompt_bytes`、`exit_code`、`duration_ms`、`stdout_bytes`、`stdout_tail`（最后 2KB）、`pid`。

## Stage 标注约定
脚本通过 `mark_stage <name> [task] [round]` 设置 `AUTO_WORK_STAGE` / `AUTO_WORK_TASK` / `AUTO_WORK_ROUND` 环境变量。标准 stage 名：
- `classify` — 需求分类
- `research` / `research-iteration` — 技术调研
- `feature-gen` — 生成 feature.md
- `plan-iteration` — Plan 迭代
- `task-split` — 任务拆分
- `task-dev` — 逐任务开发
- `develop-iteration` — 开发迭代（子 loop 内）
- `task-guardian` / `acceptance` — 守卫与验收
- `doc-gen` / `git-push` — 文档生成与推送

## 查看 Trace
```bash
python .claude/scripts/trace_view.py <trace_dir>                        # 全量汇总
python .claude/scripts/trace_view.py <trace_dir> --stage plan-iteration # 按 stage
python .claude/scripts/trace_view.py <trace_dir> --task task-03         # 按 task
python .claude/scripts/trace_view.py <trace_dir> --failed-only          # 仅失败
python .claude/scripts/trace_view.py <trace_dir> --detail               # 逐条明细
```

## 设计约束
- helper **绝不向 stdout 写非 CLI 内容**（保证 `$(cli_call ...)` 捕获干净）
- trace 写盘失败不影响业务退出码（best effort）
- 当前实现为纯 Bash，不依赖 Python wrapper
