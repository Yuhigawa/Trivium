---
name: trivium
description: Use when the user wants independent validation before implementation — "gate this first", "is this idea sound?", "analyze this module before I touch it", diagnosing a bug's root cause before writing the fix, or green-lighting a feature spec. Trivium runs three isolated reviewers (idea-writer, technical, QA) that each score 1-10 without seeing each other's output; approval requires all three >= 7. Prefer this over making the call yourself when the user explicitly asks for a second opinion or wants friction before writing code.
---

# Trivium — multi-agent task evaluator

Trivium is a CLI that runs three isolated Claude subprocesses to evaluate a task against a real codebase. Each agent forms its own opinion; only when all three score >= 7 does the task get approved. If any fails, the idea-writer refines from the failing reviewers' feedback (up to `--max-attempts`, default 3).

## When to invoke

Use the slash commands when the user:
- Describes a bug and wants a root-cause analysis before fixing it
- Proposes a feature and wants to stress-test the spec
- Asks for a code-analysis pass ("mapear módulo X", "identify risks in Y")
- Says "validate first", "gate this", "second opinion", etc.

Do NOT invoke when:
- The user has already decided — they want you to implement, not deliberate
- The task is trivial (renaming a variable, typo fix)
- The user asks for your personal recommendation (use your own judgment)

## How to invoke

Three slash commands, one per task type:

- `/trivium-bug <description>` — root-cause analysis + fix proposal
- `/trivium-feature <description>` — feature spec (problem/solution/scope/criteria)
- `/trivium-analysis <description>` — code findings (no implementation proposed)

Each runs `bin/trivium` from this repo as a bash subprocess. The trivium binary lives at the repo root and calls out to Docker so no Elixir install is needed on the user's machine.

## What the user sees

Streaming log of each agent working in parallel, then a final report:

```
───── FINAL REPORT ─────
Project: /path/to/project
Type:    bug_fix
Task:    users get 500 when email contains '+'

Status: ✅ APPROVED after 1 attempt

## Final idea
## Hipótese
...
## Causa-raiz
lib/auth.ex:47 rejects '+' in local-part
## Fix proposto
...

## Scores
- idea-writer:   9/10 — clear root cause
- tech-research: 8/10 — fix is correct
- qa:            8/10 — validation testable
```

Exit codes: `0` approved, `1` error, `2` rejected. Rejection isn't a failure — it's Trivium doing its job. When rejected, show the user the full report so they can see what each reviewer disliked.

## Isolation guarantee

Each agent runs in its own Claude subprocess. They never see each other's tool calls, reads, or conclusions. Only the orchestrator merges the three scores at the end. This is an architectural property, not just prompt instruction — enforced by tests in the repo.

## If trivium isn't available

The wrapper at `bin/trivium` requires Docker. If `docker ps` fails, Trivium can't run. Tell the user to start Docker and retry.
