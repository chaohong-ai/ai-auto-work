#!/usr/bin/env python3
"""trace_view.py — auto-work JSONL trace 聚合查看器。

读取 {FEATURE_DIR}/traces/*.jsonl（或 .claude/logs/traces/*.jsonl），
输出每 stage/task 的调用次数、总耗时、失败率。

用法：
    python trace_view.py <trace_dir>                        # 全量
    python trace_view.py <trace_dir> --stage plan-iteration # 按 stage 过滤
    python trace_view.py <trace_dir> --task task-03         # 按 task 过滤
    python trace_view.py <trace_dir> --failed-only          # 只看失败
    python trace_view.py <trace_dir> --detail               # 逐条明细
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


def load_records(trace_dir: Path) -> list[dict]:
    records = []
    for f in sorted(trace_dir.glob("*.jsonl")):
        for line in f.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def filter_records(
    records: list[dict],
    stage: str | None,
    task: str | None,
    failed_only: bool,
) -> list[dict]:
    out = records
    if stage:
        out = [r for r in out if r.get("stage") == stage]
    if task:
        out = [r for r in out if r.get("task") == task]
    if failed_only:
        out = [r for r in out if r.get("exit_code", 0) != 0]
    return out


def fmt_ms(ms: int) -> str:
    if ms < 1000:
        return f"{ms}ms"
    secs = ms / 1000
    if secs < 60:
        return f"{secs:.1f}s"
    mins = int(secs // 60)
    remaining = secs - mins * 60
    return f"{mins}m{remaining:.0f}s"


def estimate_tokens_from_bytes(byte_count: int) -> int:
    """Fallback estimate for older trace records without estimated_* fields."""
    return (max(int(byte_count or 0), 0) + 3) // 4


def token_counts(record: dict) -> tuple[int, int, int]:
    input_tokens = record.get("estimated_input_tokens")
    output_tokens = record.get("estimated_output_tokens")
    total_tokens = record.get("estimated_total_tokens")

    if input_tokens is None:
        input_tokens = estimate_tokens_from_bytes(record.get("prompt_bytes", 0))
    if output_tokens is None:
        output_tokens = estimate_tokens_from_bytes(record.get("stdout_bytes", 0))
    if total_tokens is None:
        total_tokens = int(input_tokens or 0) + int(output_tokens or 0)

    return int(input_tokens or 0), int(output_tokens or 0), int(total_tokens or 0)


def fmt_tokens(tokens: int) -> str:
    if tokens >= 1_000_000:
        return f"{tokens / 1_000_000:.2f}M"
    if tokens >= 10_000:
        return f"{tokens / 1000:.1f}K"
    return str(tokens)


def summary_table(records: list[dict]) -> None:
    if not records:
        print("(no records)")
        return

    # group by (stage, cli)
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in records:
        key = (r.get("stage", "?"), r.get("cli", "?"))
        groups[key].append(r)

    header = f"{'Stage':<25} {'CLI':<8} {'Calls':>5} {'Failed':>6} {'Total Time':>12} {'Avg':>10} {'InTok~':>9} {'OutTok~':>9} {'Tok~':>9} {'Fail%':>6}"
    print(header)
    print("-" * len(header))

    total_calls = 0
    total_fails = 0
    total_ms = 0

    for (stage, cli), recs in sorted(groups.items()):
        n = len(recs)
        fails = sum(1 for r in recs if r.get("exit_code", 0) != 0)
        total_time = sum(r.get("duration_ms", 0) for r in recs)
        total_input_tokens = sum(token_counts(r)[0] for r in recs)
        total_output_tokens = sum(token_counts(r)[1] for r in recs)
        total_tokens = sum(token_counts(r)[2] for r in recs)
        avg_time = total_time // n if n else 0
        fail_pct = f"{100 * fails / n:.0f}%" if n else "0%"

        print(
            f"{stage:<25} {cli:<8} {n:>5} {fails:>6} "
            f"{fmt_ms(total_time):>12} {fmt_ms(avg_time):>10} "
            f"{fmt_tokens(total_input_tokens):>9} {fmt_tokens(total_output_tokens):>9} "
            f"{fmt_tokens(total_tokens):>9} {fail_pct:>6}"
        )
        total_calls += n
        total_fails += fails
        total_ms += total_time

    print("-" * len(header))
    overall_pct = f"{100 * total_fails / total_calls:.0f}%" if total_calls else "0%"
    print(
        f"{'TOTAL':<25} {'':8} {total_calls:>5} {total_fails:>6} "
        f"{fmt_ms(total_ms):>12} {'':10} "
        f"{fmt_tokens(sum(token_counts(r)[0] for r in records)):>9} "
        f"{fmt_tokens(sum(token_counts(r)[1] for r in records)):>9} "
        f"{fmt_tokens(sum(token_counts(r)[2] for r in records)):>9} {overall_pct:>6}"
    )


def detail_table(records: list[dict]) -> None:
    if not records:
        print("(no records)")
        return

    header = f"{'Timestamp':<24} {'Stage':<20} {'Task':<12} {'CLI':<7} {'Exit':>4} {'Duration':>10} {'Prompt':>8} {'Stdout':>8} {'Tok~':>8}"
    print(header)
    print("-" * len(header))

    for r in records:
        ts = r.get("ts", "?")[:23]
        stage = r.get("stage", "?")[:20]
        task = r.get("task", "")[:12]
        cli = r.get("cli", "?")
        exit_code = r.get("exit_code", "?")
        dur = fmt_ms(r.get("duration_ms", 0))
        prompt_kb = f"{r.get('prompt_bytes', 0) / 1024:.1f}K"
        stdout_kb = f"{r.get('stdout_bytes', 0) / 1024:.1f}K"
        total_tokens = token_counts(r)[2]
        print(
            f"{ts:<24} {stage:<20} {task:<12} {cli:<7} {exit_code:>4} "
            f"{dur:>10} {prompt_kb:>8} {stdout_kb:>8} {fmt_tokens(total_tokens):>8}"
        )


def markdown_table(records: list[dict]) -> None:
    print("| Stage | CLI | Calls | Failed | Total Time | Input Tokens~ | Output Tokens~ | Total Tokens~ |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    if not records:
        return

    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in records:
        key = (r.get("stage", "?"), r.get("cli", "?"))
        groups[key].append(r)

    for (stage, cli), recs in sorted(groups.items()):
        print(
            f"| {stage or '(unset)'} | {cli} | {len(recs)} | "
            f"{sum(1 for r in recs if r.get('exit_code', 0) != 0)} | "
            f"{fmt_ms(sum(r.get('duration_ms', 0) for r in recs))} | "
            f"{sum(token_counts(r)[0] for r in recs)} | "
            f"{sum(token_counts(r)[1] for r in recs)} | "
            f"{sum(token_counts(r)[2] for r in recs)} |"
        )

    print(
        f"| **TOTAL** |  | {len(records)} | "
        f"{sum(1 for r in records if r.get('exit_code', 0) != 0)} | "
        f"{fmt_ms(sum(r.get('duration_ms', 0) for r in records))} | "
        f"{sum(token_counts(r)[0] for r in records)} | "
        f"{sum(token_counts(r)[1] for r in records)} | "
        f"{sum(token_counts(r)[2] for r in records)} |"
    )

    stage_totals: dict[str, int] = defaultdict(int)
    for r in records:
        stage_totals[r.get("stage") or "(unset)"] += token_counts(r)[2]
    if stage_totals:
        top_stage, top_tokens = max(stage_totals.items(), key=lambda item: item[1])
        print(f"\n> 估算 token 消耗最高阶段：`{top_stage}`（{top_tokens} tokens~）")


def main() -> int:
    parser = argparse.ArgumentParser(description="auto-work trace viewer")
    parser.add_argument("trace_dir", help="Path to traces/ directory")
    parser.add_argument("--stage", help="Filter by stage name")
    parser.add_argument("--task", help="Filter by task name")
    parser.add_argument("--failed-only", action="store_true", help="Show only failed calls")
    parser.add_argument("--detail", action="store_true", help="Show per-call detail instead of summary")
    parser.add_argument("--markdown", action="store_true", help="Show summary as a Markdown table")
    args = parser.parse_args()

    trace_dir = Path(args.trace_dir)
    if not trace_dir.is_dir():
        print(f"ERROR: {trace_dir} is not a directory", file=sys.stderr)
        return 1

    records = load_records(trace_dir)
    filtered = filter_records(records, args.stage, args.task, args.failed_only)

    if not args.markdown:
        print(f"Loaded {len(records)} records, showing {len(filtered)} after filters\n")

    if args.markdown:
        markdown_table(filtered)
    elif args.detail:
        detail_table(filtered)
    else:
        summary_table(filtered)

    return 0


if __name__ == "__main__":
    sys.exit(main())
