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

You'll drop into a REPL:

```
Trivium v0.1 — multi-agent task evaluator
Type your task. Ctrl+D or `exit` to quit.

> build a rate-limiter middleware for a REST API
```

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
