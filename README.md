# AI Auto-Work

> 中文文档请点击查看：[README_CN.md](./README_CN.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude](https://img.shields.io/badge/Powered%20by-Claude%20Code-blueviolet)](https://claude.ai/code)
[![Codex](https://img.shields.io/badge/Review%20by-Codex-blue)](https://openai.com/codex)
[![Workflow](https://img.shields.io/badge/Workflow-Auto%20%7C%20Manual-green)](#workflows)

**AI-driven full-cycle software development workflow** — from requirement research to code commit, powered by Claude Code + Codex dual-model collaboration.

Automatically completes the full pipeline: **Requirement Research → Research Review → Planning → Plan Review → Development → Development Review**, capable of autonomously handling medium to large-scale engineering projects.

---

## What is AI Auto-Work?

AI Auto-Work is an **agentic coding workflow system** that orchestrates large language models (LLMs) to complete real-world software engineering tasks end-to-end. It uses Claude as the executor and Codex as the adversarial reviewer, forming a **Triple-Check convergence loop** that delivers production-quality code with minimal human intervention.

### Key Capabilities

- **Autonomous full-cycle development** — S/M/L complexity classification with automatic task decomposition
- **Cross-model adversarial review** — Claude builds, Codex audits; different models surface different blind spots
- **Zero context pollution** — each stage runs in an isolated process, handoff via persisted files only
- **Mechanical quality gates** — compile + test must pass before any review cycle begins
- **Self-improving context** — systematic errors update shared knowledge base (`.ai/`), not just the code
- **Atomic commits** — one task, one commit (≤3 files / ≤100 lines), always bisectable

---

## Quick Start

```bash
# Fast path for small direct changes
/fast-auto-work v0.2.0 fix-login-button align login button loading state

# Fully automated: research → plan → code → review → commit
/auto-work implement user avatar upload feature

# With human checkpoints at key milestones
/manual-work refactor user authentication module

# Generate implementation plan only
/feature:plan add WebSocket real-time push

# Technology selection research
/research:do evaluate Redis Streams vs Kafka for task queue

# Bug fix with root cause analysis
/bug:fix fix memory leak in concurrent scenarios
```

---

## How It Works

```
User Requirement
      │
      ▼
Claude (Executor)        ← Coding, fixing, testing
      │
      ▼
  Quality Gate           ← Compile + Unit Tests + Smoke Tests (mandatory)
      │
      ▼
Codex (Reviewer)         ← Adversarial review: concurrency, leaks, edge cases
      │
      ▼
  Converged?             ← Critical = 0, High ≤ 2
  ├── No  → Claude fixes → loop
  └── Yes → Git Commit
```

---

## Workflows

### `/auto-work` — Fully Automated Workflow

No human intervention required. Handles the complete cycle from raw requirement to committed code.

**Stages:**

| # | Stage | Description |
|---|-------|-------------|
| 1 | Requirement Classification | S / M / L complexity; L auto-splits into multiple M tasks |
| 2 | Technical Research | `/research:loop` for technology selection (on demand) |
| 3 | Plan Generation | Iterative `plan.md` via `/feature:plan` |
| 4 | Task Decomposition | Atomic `tasks/task-N.md` (≤3 files / ≤100 lines) |
| 5 | Development Loop | `/feature:develop` coding + review iterations |
| 6 | Acceptance Gate | Compile + tests + HTTP endpoint triple-check |
| 7 | Documentation | Architecture docs / version docs updated |
| 8 | Commit & Push | `/git:commit` + `/git:push` |

**Convergence:** Critical = 0, High ≤ 2 — or auto-escalate complexity after max iterations.

---

### `/fast-auto-work` — Fast Path for Small Changes

Optimized for direct small changes: bug fixes, narrow extensions, and low-risk edits on top of existing patterns.

**Use it when:**

- the change is expected to stay within `<= 3` implementation files
- the module already has an established implementation pattern
- you want code + build/test verification quickly, without full research / planning artifacts

**It intentionally skips:**

- research loop
- `feature.md`, `plan.md`, `tasks/task-*.md`
- formal acceptance report, module docs, and auto-push

**Still preserved:**

- compile gate
- relevant test gate
- automatic escalation when the diff exits fast-path scope

**Typical output:**

- `Docs/Version/{version_id}/{feature_name}/classification.txt`
- `Docs/Version/{version_id}/{feature_name}/fast-auto-work-log.md`
- `Docs/Version/{version_id}/{feature_name}/fast-auto-work-escalation.md` when the request exceeds the fast path
- `Docs/Version/{version_id}/{feature_name}/fast-auto-work-artifacts/`

**Example:**

```bash
/fast-auto-work v0.2.0 fix-auth-toast stabilize duplicate toast handling
```

Use `/auto-work` or `/manual-work` instead for cross-module work, contract changes, new system design, or anything that requires formal planning and acceptance.

---

### `/manual-work` — Manual Checkpoint Workflow

Same output as auto-work, pauses at key milestones for human confirmation.

| Checkpoint | What You Review |
|-----------|-----------------|
| Stage 0 | Requirement classification |
| Stage 0-B | Research results (if applicable) |
| Stage 1 | `feature.md` requirements document |
| **Stage 2** | **Plan / architecture (most critical)** |
| Stage 4-C | Acceptance results |
| Stage 6 | Push confirmation |

Type `AUTOPILOT=true` at any checkpoint to switch to fully automated mode.

---

### `/feature:plan` — Plan Creation

Iteratively generates `plan.md` until quality converges (max 20 rounds).

- Odd rounds: generate / fix plan
- Even rounds: Codex review
- **Convergence:** Critical = 0, Important ≤ 2

Output includes: data model design, API specs, implementation flow, test strategy, risk assessment.

---

### `/feature:develop` — Feature Development

Implements tasks sequentially, each with its own coding + review loop.

**Per-task cycle:**
1. Code implementation
2. Compile check (fast-fail gate)
3. Codex review (max 2 rounds)
4. Auto-fix failures (max 2 rounds)
5. Gate: unit + integration + smoke tests
6. Context repair if systematic gaps found
7. Atomic git commit

---

### `/research:do` — Technical Research

Parallel web search (3 agent shards) + project codebase scan → structured `research-result.md`.

**Report:** Problem definition → Industry solutions → Comparison table → Practical experience → Project fit → Recommendation

---

### `/bug:fix` — Bug Fix

Root cause analysis → minimal fix → Codex review → experience consolidation into `.ai/`.

---

### `/git:commit` + `/git:push` — Safe Git Operations

- Standardized commit format: `<type>(<scope>): <description>`
- Auto-skips sensitive files
- Blocks force-push to main
- Security scan before push

---

## Why Dual-Model?

Single-model self-review misses systematic issues due to shared cognitive biases. Claude and Codex have different training distributions — what Claude overlooks, Codex tends to catch:

| Issue Type | Claude (Executor) | Codex (Reviewer) |
|------------|-------------------|------------------|
| Concurrency races | May miss | Flags |
| Goroutine leaks | May miss | Flags |
| Resource exhaustion | May miss | Flags |
| Boundary conditions | May miss | Flags |
| Constitution compliance | Self-blind | Independent check |

---

## Execution Modes

| Mode | Condition | Method | Review Quality |
|------|-----------|--------|----------------|
| **ROUTE_MODE_A** | claude CLI + codex CLI both available | Bash subprocess orchestration | Highest (true cross-model) |
| **ROUTE_MODE_B** | Agent tool only | Agent delegation | Good (proxy review) |

---

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `.ai/` | Cross-agent shared knowledge layer (source of truth) |
| `.ai/constitution.md` | Core engineering principles |
| `.ai/constitution/` | Module-specific rules (concurrency, testing, cross-module) |
| `.ai/context/project.md` | Project tech stack and constraints |
| `.claude/` | Claude Code runtime layer |
| `.claude/commands/` | Workflow definitions |
| `.claude/skills/` | Claude skill definitions |
| `.claude/guides/` | Topical rules and guides |

---

## Core Principles

| Principle | Rule |
|-----------|------|
| **Simplicity First** | Implement only what requirements explicitly ask |
| **Test-Driven** | New features and bug fixes start from failing tests |
| **Atomic Commits** | One task = one commit (≤3 files / ≤100 lines) |
| **Mechanical Gates** | Compile + tests must pass before review |
| **Document-Driven Handoff** | `feature.md → plan.md → task-N.md` only |
| **Context Repair** | Systematic errors update `.ai/`, not just the code |

---

## Frequently Asked Questions

**Q: What makes this different from GitHub Copilot or Cursor?**
A: Those tools assist individual developers with inline suggestions. AI Auto-Work orchestrates complete end-to-end development cycles — from requirement analysis through architecture planning, implementation, multi-round adversarial review, and commit — autonomously, for medium to large features.

**Q: Can it handle large codebases?**
A: Yes. Each task runs in an isolated process with a fresh context window, so context accumulation is not a limitation. L-level tasks auto-split into sequential M-level tasks to handle arbitrary scope.

**Q: What languages and frameworks are supported?**
A: The workflow system itself is language-agnostic. The included constitution and context files are configured for Go, TypeScript, Python, and GDScript, but the workflow commands can be adapted to any stack.

**Q: Does it require both Claude and Codex?**
A: No. ROUTE_MODE_B runs with Claude only (Agent tool), providing good review quality. ROUTE_MODE_A requires both Claude CLI and Codex CLI for highest-quality cross-model adversarial review.

**Q: How does context repair work?**
A: When Codex identifies a recurring class of issue (not a one-off mistake), the workflow writes the constraint into `.ai/` — the shared knowledge base loaded at the start of every future run. The same class of error won't recur.

---

## Usage Tips

- Prefer `/fast-auto-work` for direct small edits, but switch to `/auto-work` as soon as the change touches routing, contracts, architecture files, or multiple top-level domains.
- Keep the workspace clean before running `/fast-auto-work`. It aborts by default on a dirty worktree; `FAST_AUTO_WORK_ALLOW_DIRTY=1` is for debugging only and disables auto-commit.
- Put stable requirement context in `Docs/Version/{version_id}/{feature_name}/idea.md`, then add only the delta in the command arguments. The fast path merges both inputs.
- Let the fast path fail closed. If it detects out-of-scope changes, it writes an escalation file and points back to `/auto-work` or `/manual-work` instead of guessing.
- Use `FAST_AUTO_WORK_COMMIT=1` only when you explicitly want a local commit after gates pass. Default behavior is verification without auto-commit.
- Tune `CLAUDE_MODEL_CODE`, `FAST_AUTO_WORK_CLI_TIMEOUT`, and `FAST_AUTO_WORK_PREFLIGHT_TTL` when you need a different model, longer single-call timeout, or shorter preflight cache.

---

## Related Projects

- [Claude Code](https://claude.ai/code) — Anthropic's AI coding CLI
- [OpenAI Codex](https://openai.com/codex) — OpenAI's code-focused model
- [Anthropic](https://anthropic.com) — Claude model provider

---

## License

MIT License — see [LICENSE](LICENSE) for details.
