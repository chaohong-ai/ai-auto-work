#!/usr/bin/env python3
"""CLI trace wrapper for auto-work scripts.

读 stdin 取 prompt，subprocess 调 claude/codex CLI，行级转发 stdout，
落 JSONL trace 到 ${FEATURE_DIR}/traces/。

设计约束（不可协商）：
1. **绝不向 stdout 写非 CLI 内容**——上层有大量 $(cli_call ...) 捕获，
   wrapper 自己的诊断只走 stderr，且仅在 AUTO_WORK_TRACE_DEBUG=1 时输出。
2. **stdout 行级实时透传**——上层 `| tail -20` 依赖流式，禁止 buffer 到 EOF。
3. **退出码透传 CLI 的退出码**——trace 写失败用 try/except 吞掉。
4. **prompt 仍走 argv**——保持与现有 `claude -p "$PROMPT"` 一致；
   实测仓库最长 prompt ~10KB，远低于 bash execve 限制。
5. **size-based JSONL rotate**——单文件 ≥10MB 切片为 YYYYMMDD-N.jsonl。

环境变量：
- AUTO_WORK_STAGE / AUTO_WORK_TASK / AUTO_WORK_ROUND: 调用方显式标注
- AUTO_WORK_FEATURE_DIR: trace 落盘根目录（缺省 .claude/logs/traces/）
- AUTO_WORK_TRACE_DEBUG=1: 启用 stderr 诊断输出
- AUTO_WORK_LANGSMITH=1 + LANGSMITH_API_KEY: 可选 LangSmith 上报

用法（prompt 通过 stdin 传入，避免在 ps 里泄漏 + 通用接口）：
    printf '%s' "$PROMPT" | python cli_trace.py claude --permission-mode bypassPermissions --model X
    printf '%s' "$PROMPT" | python cli_trace.py codex -m X
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

ROTATE_BYTES = 10 * 1024 * 1024  # 10MB
STDOUT_TAIL_BYTES = 2048


def _debug(msg: str) -> None:
    if os.environ.get("AUTO_WORK_TRACE_DEBUG") == "1":
        print(f"[cli_trace] {msg}", file=sys.stderr, flush=True)


def _trace_root() -> Path:
    feature_dir = os.environ.get("AUTO_WORK_FEATURE_DIR")
    if feature_dir:
        return Path(feature_dir) / "traces"
    return Path(".claude/logs/traces")


def _next_jsonl_path(root: Path) -> Path:
    """返回当天的 JSONL 路径，超过 ROTATE_BYTES 自动开新分片。"""
    root.mkdir(parents=True, exist_ok=True)
    day = _dt.datetime.now().strftime("%Y%m%d")
    base = root / f"{day}.jsonl"
    if not base.exists() or base.stat().st_size < ROTATE_BYTES:
        return base
    # 找下一个未满的分片
    n = 1
    while True:
        cand = root / f"{day}-{n}.jsonl"
        if not cand.exists() or cand.stat().st_size < ROTATE_BYTES:
            return cand
        n += 1


def _save_prompt(root: Path, prompt: str, sha8: str, ts: str) -> str:
    """落盘 prompt 全文，返回相对路径（写 trace 时记录）。"""
    prompts_dir = root / "prompts"
    prompts_dir.mkdir(parents=True, exist_ok=True)
    safe_ts = ts.replace(":", "").replace("-", "").replace(".", "")
    fname = f"{sha8}-{safe_ts}.txt"
    fpath = prompts_dir / fname
    if not fpath.exists():
        fpath.write_text(prompt, encoding="utf-8")
    return str(fpath.relative_to(root))


def _resolve_bin_prefix(name: str) -> list[str]:
    """Resolve a CLI name to a launchable argv prefix.

    On Windows, npm-installed CLIs are .CMD batch files that wrap a
    `node <cli.js>` call. We read the .CMD to extract the JS entry-point
    and return `[node, <js_path>]` directly — this avoids cmd.exe's
    argument-parsing rules (special chars like & | ^ % are transparent
    to CreateProcess/MSVC-runtime quoting, but *not* to cmd.exe).

    Fallback chain (Windows):
      1. Read .CMD → extract node + .js path
      2. cmd /c <name>          (cmd.exe still works for simple prompts)
      3. bare name              (let Popen raise a clear FileNotFoundError)

    On POSIX the name is returned as-is (bash/exec handles it fine).
    """
    if sys.platform != "win32":
        return [name]

    resolved = shutil.which(name)
    if not resolved:
        resolved = shutil.which(name + ".cmd")

    if resolved and resolved.upper().endswith((".CMD", ".BAT")):
        # Parse "node_modules path" from the .cmd body.
        # Typical npm .cmd tail line:
        #   ... & "%_prog%"  "%dp0%\node_modules\foo\bar.js" %*
        try:
            cmd_text = Path(resolved).read_text(encoding="utf-8", errors="replace")
            # Find the JS path after last '"' block on the GOTO-free final line
            import re
            m = re.search(r'"([^"]+\.js)"\s+%\*', cmd_text)
            if m:
                # Expand %dp0% → parent dir of the .cmd file
                # Use POSIX-style paths (forward slashes) so subprocess.Popen works under
                # MSYS2/Git-Bash where backslash paths fail CreateProcess.
                dp0_posix = Path(resolved).parent.as_posix() + "/"
                dp0_win   = str(Path(resolved).parent) + "\\"
                raw_js = m.group(1).replace("%dp0%", dp0_win).replace("%DP0%", dp0_win)
                js_path = Path(raw_js).as_posix()
                # Use shutil.which to get full POSIX path for node so CreateProcess
                # doesn't rely on bare 'node' being in the Windows-native PATH.
                node_resolved = shutil.which("node") or shutil.which("node.exe")
                node_bin = Path(node_resolved).as_posix() if node_resolved else "node"
                _debug(f"windows .cmd resolved: node={node_bin!r} js={js_path!r}")
                return [node_bin, js_path]
        except Exception as e:  # noqa: BLE001
            _debug(f"failed to parse .cmd ({e!r}), falling back to cmd /c")
        # Fallback: cmd.exe (simpler prompts without special chars will work)
        return ["cmd", "/c", name]

    if resolved:
        return [resolved]
    return [name]


def _build_argv(cli: str, extra_args: list[str], prompt: str) -> tuple[list[str], str]:
    """根据 cli 名构造真实命令行，返回 (argv, stdin_text)。

    设计原则：prompt 通过 stdin 传入（而非 argv），避免 Windows CreateProcess
    32 KiB 命令行长度上限导致长 prompt 被截断。

    - claude: `claude --stdin-prompt [flags...]`，prompt → stdin
    - codex:  `codex exec --full-auto [flags...] <prompt>`（仅 prompt 走 argv，
              codex prompt 通常较短且不支持 stdin 模式）

    CLI_TRACE_<NAME>_BIN 环境变量可覆盖可执行文件路径（测试用）。
    """
    if cli == "claude":
        bin_spec = os.environ.get("CLI_TRACE_CLAUDE_BIN", "claude")
        bin_argv = bin_spec.split("|")  # 测试专用：多 token argv 前缀
        if len(bin_argv) == 1:
            bin_argv = _resolve_bin_prefix(bin_argv[0])
        # 使用 stdin 模式：`claude -p -` 表示从 stdin 读取 prompt
        return [*bin_argv, "-p", "-", *extra_args], prompt
    if cli == "codex":
        bin_spec = os.environ.get("CLI_TRACE_CODEX_BIN", "codex")
        bin_argv = bin_spec.split("|")
        if len(bin_argv) == 1:
            bin_argv = _resolve_bin_prefix(bin_argv[0])
        # codex exec --full-auto [flags...] <prompt>（保持 argv 传递）
        return [*bin_argv, "exec", "--full-auto", *extra_args, prompt], ""
    raise ValueError(f"unknown cli: {cli}")


def _maybe_langsmith_wrap(cli: str, stage: str):
    """可选 LangSmith @traceable 包装，缺依赖或未启用时返回 None。"""
    if os.environ.get("AUTO_WORK_LANGSMITH") != "1":
        return None
    if not os.environ.get("LANGSMITH_API_KEY"):
        return None
    try:
        from langsmith import traceable  # type: ignore
    except ImportError:
        _debug("langsmith not installed; skipping")
        return None

    def _wrap(fn):
        return traceable(name=f"auto-work.{stage or 'unknown'}.{cli}")(fn)

    return _wrap


def _stream_subprocess(argv: list[str], stdin_text: str = "") -> tuple[int, int, str, int]:
    """启动子进程，行级转发 stdout，返回 (exit_code, stdout_bytes, stdout_tail, pid)。

    stderr 已合并到 stdout（subprocess.STDOUT），所以 CLI 的所有输出都进同一流。
    stdin_text 非空时通过 PIPE 写入子进程 stdin（用于 claude -p - 的 stdin 模式）。
    """
    proc = subprocess.Popen(
        argv,
        stdin=subprocess.PIPE if stdin_text else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,  # 行缓冲
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    # 写入 stdin（写完立即关闭，让 CLI 知道 EOF）
    if stdin_text and proc.stdin is not None:
        try:
            proc.stdin.write(stdin_text)
            proc.stdin.close()
        except BrokenPipeError:
            pass  # CLI exited early; proceed to read stdout

    # 信号转发：父进程收到 SIGTERM/SIGINT 时转给子进程
    def _forward(signum, _frame):
        try:
            proc.send_signal(signum)
        except Exception:
            pass

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(sig, _forward)
        except (ValueError, OSError):
            # 非主线程或 Windows 不支持时跳过
            pass

    tail_lines: deque[str] = deque()  # 保留尾部若干行，总字节 ≤ STDOUT_TAIL_BYTES
    tail_byte_count = 0
    total_bytes = 0
    assert proc.stdout is not None
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        line_bytes = len(line.encode("utf-8", errors="replace"))
        total_bytes += line_bytes
        tail_lines.append(line)
        tail_byte_count += line_bytes
        # 淘汰最旧的行，保持总字节 ≤ STDOUT_TAIL_BYTES
        while tail_byte_count > STDOUT_TAIL_BYTES and len(tail_lines) > 1:
            removed = tail_lines.popleft()
            tail_byte_count -= len(removed.encode("utf-8", errors="replace"))

    proc.wait()
    return proc.returncode, total_bytes, "".join(tail_lines), proc.pid


def _write_trace(root: Path, record: dict) -> None:
    try:
        path = _next_jsonl_path(root)
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception as e:  # noqa: BLE001
        _debug(f"trace write failed (swallowed): {e!r}")


def main(argv: list[str]) -> int:
    # Ensure stdout/stderr use UTF-8 on Windows (default may be GBK/cp936 which
    # cannot encode characters like ✓ U+2713 that Claude commonly outputs).
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    if len(argv) < 2:
        print("usage: cli_trace.py <claude|codex> [extra args...]", file=sys.stderr)
        return 2

    cli = argv[1]
    if cli not in ("claude", "codex"):
        print(f"cli_trace: unknown cli '{cli}'", file=sys.stderr)
        return 2
    extra_args = argv[2:]

    # 读 stdin 取 prompt
    prompt = sys.stdin.read()
    if not prompt:
        _debug("warning: empty stdin prompt")

    # 提取 model 信息（从 extra_args 解析 --model X 或 -m X）
    model = ""
    for i, a in enumerate(extra_args):
        if a in ("--model", "-m") and i + 1 < len(extra_args):
            model = extra_args[i + 1]
            break

    stage = os.environ.get("AUTO_WORK_STAGE", "")
    task = os.environ.get("AUTO_WORK_TASK", "")
    round_ = os.environ.get("AUTO_WORK_ROUND", "")
    feature_dir = os.environ.get("AUTO_WORK_FEATURE_DIR", "")

    sha = hashlib.sha256(prompt.encode("utf-8", errors="replace")).hexdigest()
    sha8 = sha[:8]
    ts_started = _dt.datetime.now().isoformat(timespec="milliseconds")

    root = _trace_root()
    prompt_rel = ""
    try:
        prompt_rel = _save_prompt(root, prompt, sha8, ts_started)
    except Exception as e:  # noqa: BLE001
        _debug(f"prompt save failed (swallowed): {e!r}")

    argv_real, stdin_text = _build_argv(cli, extra_args, prompt)
    _debug(f"exec: {cli} (stage={stage} task={task} round={round_} prompt_bytes={len(prompt)} stdin_mode={bool(stdin_text)})")

    t0 = time.monotonic()
    wrap = _maybe_langsmith_wrap(cli, stage)
    if wrap is not None:
        wrapped = wrap(_stream_subprocess)
        exit_code, stdout_bytes, tail, pid = wrapped(argv_real, stdin_text)
    else:
        exit_code, stdout_bytes, tail, pid = _stream_subprocess(argv_real, stdin_text)
    duration_ms = int((time.monotonic() - t0) * 1000)

    record = {
        "ts": ts_started,
        "stage": stage,
        "task": task,
        "round": round_,
        "cli": cli,
        "model": model,
        "prompt_file": prompt_rel,
        "prompt_sha256": sha,
        "prompt_bytes": len(prompt.encode("utf-8", errors="replace")),
        "exit_code": exit_code,
        "duration_ms": duration_ms,
        "stdout_bytes": stdout_bytes,
        "stdout_tail": tail,
        "feature_dir": feature_dir,
        "pid": pid,
    }
    _write_trace(root, record)
    _debug(f"done: exit={exit_code} duration_ms={duration_ms}")

    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
