# AI Auto-Coding Workflow

> 中文文档请点击查看：[README_CN.md](./README_CN.md)

A full-cycle AI development workflow system built on Claude Code + Codex, covering everything from requirement research to code commit.

---

## Quick Start

```bash
# Fully automated requirement implementation
/auto-work implement user avatar upload feature

# With manual checkpoints
/manual-work refactor user authentication module

# Generate plan only, develop after confirmation
/feature:plan add WebSocket real-time push

# Technology selection research
/research:do evaluate Redis Streams vs Kafka for task queue

# Bug fix
/bug:fix fix memory leak in concurrent scenarios
```

---

## AI Workflow System

This repository contains a complete AI development workflow covering the full cycle from requirement research to code commit. All workflows are driven by Claude Code, with Codex serving as the adversarial reviewer.

### Execution Modes

| Mode | Trigger | Execution | Review Quality |
|------|---------|-----------|----------------|
| **ROUTE_MODE_A** | Both claude CLI + codex CLI available | Bash subprocess orchestration | Highest (cross-model review) |
| **ROUTE_MODE_B** | Agent tool only | Agent delegation orchestration | Good (Agent proxy review) |

---

### `/auto-work` — Fully Automated Workflow

No human intervention required. Fully automated from requirement to code commit.

**Stages:**

1. **Requirement Classification** — Classified into S / M / L by complexity; L-level tasks are automatically split into multiple M-level tasks
2. **Technical Research** (on demand) — Calls `/research:loop` for technology selection
3. **Plan Generation** — Calls `/feature:plan` to iteratively generate `plan.md`
4. **Task Decomposition** — Splits plan into atomic `tasks/task-N.md` (≤3 files / ≤100 lines each)
5. **Development Loop** — Calls `/feature:develop` for coding + review iterations
6. **Acceptance Gate** — Mandatory compile + test pass; HTTP endpoints require three artifacts (route registration + route test + smoke test)
7. **Documentation Update** — Updates architecture docs / version docs
8. **Commit & Push** — Calls `/git:commit` + `/git:push`

**Convergence Criteria:** Critical = 0, High ≤ 2, or auto-escalate complexity level after max iterations.

**Triple-Check Convergence:**
- Claude (executor) codes → Codex (reviewer) finds blind spots → Claude fixes → loop until convergence

#### Core Advantages

**1. Zero Context Pollution**

Each stage runs in an isolated process (`claude -p` subprocess or Agent), with inter-stage handoffs via persisted files (`feature.md → plan.md → task-N.md`) rather than shared memory. This eliminates hallucination drift and attention decay caused by context accumulation in long conversations — every subtask starts with a fresh, precise context.

**2. Cross-Model Adversarial Review (Triple-Check)**

The executor (Claude) and reviewer (Codex) are different models with inherent cognitive differences. Claude's implementation blind spots are precisely what Codex excels at finding:

- Concurrency races, goroutine leaks, lock granularity errors
- Unreleased resources, connection pool exhaustion
- Boundary conditions, missing error paths
- Constitution compliance (test coverage, log levels, error layering)

Single-model self-review misses systematic issues due to shared biases; dual-model adversarial review exposes them.

**3. Mechanical Gates, Not Subjective Judgment**

Code must pass hard gates before entering Review:

```
Compile → Unit Tests → Integration Tests (on interface changes) → Smoke Tests
```

These are machine verifications, not AI self-assessments. Gate failures halt immediately — no entering the review loop with compile errors, eliminating "commit now, fix later" technical debt.

**4. Atomic Commits, Traceable Changes**

Task decomposition enforces single-responsibility commits (≤3 files / ≤100 lines). Benefits:

- Each commit passes CI independently
- Precise `git bisect` for root cause isolation
- Fine-grained review scope — reviewers won't be overwhelmed by large PRs
- Prevents "mega commits" mixing good code with problematic code

**5. Context Self-Repair Mechanism**

When a Review identifies recurring issues across multiple iterations, auto-work doesn't just fix the code — it triggers context repair: writing project-level constraints into `.ai/` (shared source of truth) and Claude-specific rules into `.claude/`. This means **the same class of errors won't recur in future workflows** — the workflow continuously improves with use.

**6. Adaptive Complexity**

S / M / L classification is not a static label. L-level tasks are automatically split into multiple M-level tasks executed serially; M-level tasks can auto-escalate and re-plan if scope exceeds expectations mid-iteration. This allows a single `/auto-work` call to handle anything from a single-function change to a cross-module refactor.

**7. Accumulated Experience Assets**

After each workflow execution, context repairs, Review findings, and architectural decisions are persisted to `.ai/` and `.claude/`. The repository itself becomes a continuously growing engineering knowledge base — subsequent workflows automatically inherit this experience rather than starting from scratch.

---

### `/manual-work` — Manual Checkpoint Workflow

Produces the same output as auto-work, but pauses at key milestones for user confirmation.

**Checkpoints:**

| Stage | Review Content |
|-------|----------------|
| Stage 0 | Requirement classification confirmation |
| Stage 0-B | Research results confirmation (if applicable) |
| Stage 1 | feature.md requirements document confirmation |
| **Stage 2** | **Plan / architecture confirmation (most important)** |
| Stage 4-C | Acceptance results confirmation |
| Stage 6 | Push confirmation |

Users can enter `AUTOPILOT=true` at any checkpoint to skip all subsequent confirmations and switch to fully automated mode.

---

### `/feature:plan` — Plan Creation Workflow

Iteratively generates `plan.md` until quality converges.

**Flow:** Odd rounds generate/fix plan → Even rounds Codex reviews → Loop (max 20 rounds)

**`plan.md` Output Includes:**
- Data model design
- API interface specifications
- Implementation flow
- Test strategy
- Risk assessment

**Convergence Condition:** Critical = 0 and Important ≤ 2

---

### `/feature:develop` — Feature Development Workflow

Implements tasks one by one from the task list, with independent coding + review loops per task.

**Per-Task Loop:**
1. Code implementation
2. Compile verification (fast-fail gate)
3. Codex review (max 2 rounds)
4. Auto-fix compile / test failures (max 2 rounds)
5. Mandatory gate: unit tests + integration tests (on interface changes) + smoke tests
6. Context repair (if systematic gaps found, update `.ai/`)
7. Git commit (one atomic commit per task)

---

### `/research:do` — Technical Research Workflow

Provides technology selection rationale for design decisions.

**Flow:**
1. Define research scope
2. **Parallel web search** (3 Agent shards): mainstream solutions / practical experience / comparison articles
3. **Project context search**: scan existing repository implementations
4. Generate structured `research-result.md`
5. Confirm conclusions with user

**Report Structure:** Problem definition → Industry solution overview → Comparison table → Practical experience → Project fit analysis → Recommendation

---

### `/bug:fix` — Bug Fix Workflow

Root cause analysis → minimal fix → Codex review → experience consolidation.

**Stages:**
1. Locate the issue (logs, call chain, hypothesis verification)
2. Minimal fix + compile verification + testing
3. Mandatory Codex review (`codex exec --full-auto`)
4. Git commit + update `.ai/` if systematic issue found

---

### `/git:commit` — Standardized Commit Workflow

- Claude determines staging scope (automatically skips sensitive files)
- Generates standardized commit message: `<type>(<scope>): <description>`
- Codex executes `git add` + `git commit`
- Creates new commit on hook failure — no `--amend`

---

### `/git:push` — Safe Push Workflow

- Verifies no uncommitted changes; blocks force-push to main branch
- Security check (no secret leaks)
- Codex executes `git push`; automatically adds `-u origin <branch>` when no tracking branch exists

---

## Dual-Model Collaboration Architecture

```
User Requirement
      │
      ▼
Claude (Executor)
  ├── Code implementation
  ├── Fix issues
  └── Generate tests
        │
        ▼
  Codex (Reviewer)
  ├── Adversarial review
  ├── Find blind spots (concurrency safety, resource leaks, edge cases)
  └── Verify fixes
        │
        ▼
  Converged (Critical=0, High≤2)
        │
        ▼
  Git Commit
```

---

## Workflow Directory Structure

| Directory | Responsibility |
|-----------|----------------|
| `.ai/` | Cross-Agent shared knowledge layer (source of truth) |
| `.claude/` | Claude Code dedicated runtime layer |
| `.codex/` | Codex runtime layer |

### `.ai/` (Cross-Agent Shared Layer)

| File | Content |
|------|---------|
| `constitution.md` | Core engineering principles (simplicity first, observability, low coupling, test-first, etc.) |
| `constitution/` | Module-specific detailed rules (concurrency, test acceptance, cross-module communication, etc.) |
| `context/project.md` | Project tech stack, directory semantics, key constraints |
| `context/reviewer-brief.md` | Review execution standards, issue classification, status definitions, resolution conditions |

### `.claude/` (Claude Code Dedicated Runtime Layer)

| Directory | Content |
|-----------|---------|
| `commands/` | Workflow definitions (auto-work, manual-work, feature series, research, bug fix, git) |
| `constitution.md` | Claude-specific coding standards |
| `guides/` | Topical rules (context repair, cancellation semantics, trace debugging, etc.) |
| `rules/` | Context repair, error handling, and other rule files |
| `skills/` | Claude native skill definitions |

---

## Core Principles Summary

1. **Simplicity First** — Implement only what requirements explicitly ask; no speculative design
2. **Test-Driven** — New features and bug fixes start from failing tests
3. **Atomic Commits** — One commit per task, ≤3 files / ≤100 lines
4. **Mechanical Gates** — Compile + tests must pass before Review (cheap checks first)
5. **Document-Driven Handoff** — Stages communicate only via persisted files (feature.md → plan.md → task-N.md)
6. **Context Repair** — Systematic errors update `.ai/`, not just the code
