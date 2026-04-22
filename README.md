# Trivium

Multi-agent task evaluator — three isolated reviewers decide independently whether a task is ready for development.

## Why

Most "agent" systems today are chains: one agent talks to the next, passing context and trying to reach consensus. That's convenient, but it introduces a subtle pathology — agents end up persuading each other. The later agent inherits the earlier one's framing, anchors on it, and rubber-stamps.

Trivium forces independence by architecture, not by prompt. Three roles — **idea-writer**, **technical-researcher**, and **QA** — evaluate the same task, each in its own BEAM process, each with its own fresh LLM conversation. They never see each other's output. Only the orchestrator does.

At the end, each returns a score from 1 to 10. If **all three** score above 7, the task is approved. Otherwise, the idea-writer gets only the failing reviewers' justifications and rewrites — up to three attempts.

## Architecture

```
user task
    │
    ▼
┌────────────────┐
│  Orchestrator  │  single owner of all outputs
└────┬───────────┘
     │  attempt N (1..max)
     ▼
┌──────────────┐
│ idea-writer  │  generates/refines the idea
└──────┬───────┘
       │ idea_vN
       ▼
 ╔══════════════════════════════╗
 ║        FAN-OUT (parallel)    ║
 ║  ┌──────┐  ┌──────┐  ┌─────┐ ║  each receives ONLY the idea
 ║  │ idea │  │ tech │  │ qa  │ ║  (self-review, technical, QA)
 ║  └───┬──┘  └───┬──┘  └──┬──┘ ║
 ║      └─────────┴────────┘    ║
 ╚═══════════════╦══════════════╝
                 ▼
          3 independent scores
                 │
         ┌───────┴───────┐
         │ all > 7 ?     │
         └───┬───────┬───┘
             │ yes   │ no
             ▼       ▼
        approved   next attempt
                   (idea-writer sees ONLY
                    failing justifications)
```

### Isolation guarantees

1. Each agent runs in a separate `Task` — no shared memory.
2. The orchestrator is the only process that sees all outputs.
3. Each LLM call is a fresh conversation — no cross-session history.
4. The idea-writer's refinement prompt contains justifications only from reviewers who **failed** the idea; approvers' opinions are never surfaced.
5. Enforced in tests: `test/trivium/orchestrator_test.exs` injects unique sentinels into QA and tech responses and asserts that neither ever appears in the other's input.

## Quick start

Everything runs in Docker — no Elixir/Erlang needed on the host.

### 1. Clone and build

```bash
git clone git@github.com:Yuhigawa/Trivium.git
cd Trivium
docker compose build dev
```

### 2. Pick an LLM backend

Edit `config/config.exs`:

```elixir
config :trivium,
  llm_client: Trivium.LLM.ClaudeCLI,   # or Trivium.LLM.Anthropic
  models: %{
    idea_writer: "claude-opus-4-7",
    technical_researcher: "claude-sonnet-4-6",
    qa: "claude-haiku-4-5-20251001"
  }
```

**Option A — `Trivium.LLM.ClaudeCLI`** (default):
Shells out to the `claude` binary installed on the host, reusing the user's Claude Code subscription. No API key needed. Slower (~15–25 s per call due to CLI overhead) but zero billing on Anthropic's API.

**Option B — `Trivium.LLM.Anthropic`**:
Direct HTTP to `api.anthropic.com` with streaming SSE. Fast. Requires `ANTHROPIC_API_KEY` in the environment.

### 3. Build the escript and run

```bash
docker compose run --rm dev sh -c "MIX_ENV=prod mix escript.build"
docker compose run --rm run
```

Trivium has two modes:

- **Idea mode (REPL)** — no project, just task text. You'll drop into a REPL:
  ```
  Trivium v0.1 — multi-agent task evaluator
  > build a rate-limiter middleware for a REST API
  ```
- **Project mode (one-shot)** — run against a real codebase. See below.

## Project mode

Run all three reviewers against a real codebase. Requires the `ClaudeCLI` backend so agents can use `Read`, `Grep`, and `Glob` tools on the project directory (read-only).

```bash
trivium \
  --path /path/to/project \
  --type <bug|feature|analysis> \
  --task "<description>"
```

All three flags are required together (or none — then REPL runs).

### Task types

| `--type` | idea-writer produces | tech reviews | qa reviews |
|---|---|---|---|
| `bug` / `bug_fix` | Hipótese / Causa-raiz / Fix / Validação / Critérios | Is the root-cause correct? Fix addresses it? Regression risk? | Is the fix testable? Validation robust? Can you write a failing test that passes post-fix? |
| `feature` | Problem / Solution / Scope / Out-of-scope / Success criteria | Viable in existing stack? Complexity? Integration risks? | Testable criteria? Edge cases? Scope well-bounded? |
| `analysis` | Context / Findings / Recommendations / Risks / Next steps | Technical depth, coverage of the right files, grounded claims | Actionable findings? Ambiguity? Gaps? |

Scoring is identical across types: each agent scores 1–10, all three must score above 7, refinement loop up to `--max-attempts` otherwise.

Exit codes:
- `0` — approved
- `1` — error (bad args, LLM failure, etc.)
- `2` — rejected (ran to completion, didn't pass)

### Example

```bash
$ trivium --path /srv/my-api --type bug --task "users get 500 on login when email has '+'"

Project: /srv/my-api
Type:    bug_fix
Task:    users get 500 on login when email has '+'

───── FINAL REPORT ─────
Status: ✅ APPROVED after 1 attempt

## Final idea

## Hipótese
Parser de e-mail em `lib/auth.ex` não trata `+` como válido no local-part.

## Causa-raiz
`lib/auth.ex:47` usa `Regex.run(~r/.../, email)` com regex restritivo que rejeita `+`.
...

## Scores

- idea-writer:   9/10 — root-cause backed by specific file/line
- tech-research: 8/10 — fix addresses the actual cause, not symptom
- qa:            8/10 — validation testable, regression plan clear
```

### From Claude Code

Since Trivium runs one-shot with predictable exit codes, you can call it from a coding session:

```
bash(trivium --path $PWD --type analysis --task "mapear módulos com alta dívida técnica")
```

Capture the output, feed it back as context for planning.

## Example output

```
[attempt 1/3]
[idea]  working... done (idea generated)
[tech]  working... done → score 8/10
[qa]    working... done → score 6/10
[idea]  working... done → score 8/10

✗ failed — refining

[attempt 2/3]
...

───── FINAL REPORT ─────
Status: ✅ APPROVED after 2 attempts

## Final idea

## Problem
APIs without rate limiting are vulnerable to abuse...

## Scores

- idea-writer:   9/10 — clear scoping, concrete criteria
- tech-research: 8/10 — viable with standard tools (token bucket, Redis)
- qa:            8/10 — testable criteria, edge cases covered
```

## Configuration

| Setting | Default | Flag / Env |
|---|---|---|
| Max refinement attempts | 3 | `--max-attempts N` |
| Streaming output | on | `--no-stream` to disable |
| LLM client | `ClaudeCLI` | `config/config.exs` |
| API key (for `Anthropic` client) | — | `ANTHROPIC_API_KEY` env |
| Approval threshold | `> 7` | `config/config.exs` (`approval_threshold`) |
| Model per role | Opus / Sonnet / Haiku | `config/config.exs` (`models`) |
| Project dir | — | `--path DIR` (requires `--type` + `--task`) |
| Task type | — | `--type bug\|feature\|analysis` |
| Task description | — | `--task "..."` |

## Claude Code plugin

Trivium ships as a Claude Code plugin. From any project, run the gates as slash commands — Trivium runs in Docker, so no Elixir install needed.

### Install

The repo ships its own marketplace manifest, so installation is two slash commands in any Claude Code session:

```
/plugin marketplace add Yuhigawa/Trivium
/plugin install trivium@trivium
```

After install, verify with `/plugin` — you should see `trivium@trivium: enabled`.

**Local development install** (when you have this repo cloned on your machine and want live edits to propagate):

```
/plugin marketplace add /absolute/path/to/Trivium
/plugin install trivium@trivium
```

### Requirements on the user's machine

The slash commands invoke `bin/trivium`, which runs the escript in Docker. So users need:

- Docker with Compose plugin
- A Claude Code subscription logged in on the host (`claude /login`) — the plugin bind-mounts `~/.claude` into the container to reuse the session

No Elixir / Erlang on the host. First-run builds the image and compiles the escript automatically.

### Commands

**Gate (3-agent quorum)** — score a task before committing to it:

- `/trivium-bug <description>` — root-cause analysis + fix proposal
- `/trivium-feature <description>` — problem/solution/scope spec
- `/trivium-analysis <description>` — findings-only pass (no solution proposed)

**Pipeline (build → execute → review)** — take an approved spec through plan, implementation, and review:

- `/trivium-build <spec or path>` — generate an ordered plan + pre-check, then ask if you want to execute it now
- `/trivium-execute <plan-path>` — implement the plan step by step, ticking each acceptance, and auto-trigger review when done
- `/trivium-review <plan-path>` — run the reviewer against `git diff <base_ref>..HEAD` and append findings to the plan

Each command runs against `$PWD` and invokes the `bin/trivium` wrapper in this repo, which handles Docker + dynamic path mounting automatically. If Docker isn't running, the command fails fast with a clear error.

### Pipeline mode (build → execute → review)

After a spec passes the gate (or any time you have a task ready to plan), `/trivium-build` produces a single durable artefact at `docs/trivium/<date>-<slug>-plan.md` in the target project. The plan has YAML front-matter (`base_ref`, `status`), a checklist of steps with acceptance criteria, and a `## Pre-check notes` section flagging conflicts with existing code. `/trivium-execute` walks the checklist and `/trivium-review` validates the resulting `git diff base_ref..HEAD` — the review verdict and findings are appended to the same file, preserving history across re-runs.

### Skill

The plugin also registers a `trivium` skill with auto-activation triggers — when the user says "gate this first", "get a second opinion", "mapear X", etc., Claude Code picks up Trivium as the right tool.

## Development

```bash
# Run tests (uses Trivium.LLM.Mock, no network)
docker compose run --rm test

# Interactive iex
docker compose run --rm dev

# Just compile
docker compose run --rm dev mix compile
```

### Project layout

```
lib/trivium/
├── application.ex          # supervisor (Registry + Task.Supervisor)
├── cli.ex                  # escript entry + Optimus arg parsing
├── repl.ex                 # interactive loop
├── orchestrator.ex         # the heart — coordinates attempts
├── events.ex               # Registry-based pub/sub
├── renderer.ex             # live colored stdout (IO.ANSI)
├── report.ex               # final markdown report
├── config.ex               # app-config accessors
├── types.ex                # Idea, Review, Attempt, Result structs
├── llm/
│   ├── client.ex           # behaviour
│   ├── anthropic.ex        # HTTP + SSE streaming
│   ├── claude_cli.ex       # subprocess to `claude -p`
│   └── mock.ex             # deterministic, for tests
└── agents/
    ├── agent.ex            # behaviour + JSON review parser
    ├── idea_writer.ex      # generates + self-reviews
    ├── technical_researcher.ex
    └── qa.ex
```

## License

MIT
