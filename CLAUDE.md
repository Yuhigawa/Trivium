# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this project is

Trivium is an Elixir escript that gates and develops software tasks via isolated LLM agents. It ships as a Claude Code plugin and is invoked through slash commands (`/trivium-bug`, `/trivium-feature`, `/trivium-analysis`, `/trivium-build`, `/trivium-execute`, `/trivium-review`).

Two pipelines coexist:

1. **Gate (3-agent quorum)** — `Trivium.Orchestrator` runs `IdeaWriter` (with self-review), `TechnicalResearcher`, and `QA` in parallel. A task is approved only if all three score > 7. Used by `/trivium-bug|feature|analysis`.
2. **Build pipeline (Planner → PreChecker → execute → Reviewer)** — `Trivium.Build.Orchestrator` turns an approved spec into a plan file, validates it against existing code, and (after the user implements) reviews the diff. Used by `/trivium-build|execute|review`.

The pipelines are deliberately isolated: gate types live under `Trivium.Types`, build types under `Trivium.Build.Types`. **Do not rename or merge them** — the namespace boundary keeps the two flows independent.

## How to run things

Everything runs in Docker via `docker compose`. Service names:

```bash
docker compose run --rm test                    # full test suite (mix test)
docker compose run --rm test mix test <file>    # single test file
docker compose run --rm dev mix compile         # compile-only
docker compose run --rm dev                     # interactive iex
docker compose run --rm run                     # runs the prod escript (./trivium)
```

Do **not** suggest running `mix` directly on the host — Elixir is not assumed to be installed.

## Project layout

```
lib/trivium/
├── application.ex      # OTP supervisor
├── cli.ex              # escript entry; dispatches subcommands or falls through to legacy REPL/one-shot
├── repl.ex             # interactive loop (legacy mode)
├── orchestrator.ex     # gate orchestrator (3-agent quorum)
├── events.ex           # Registry pub/sub
├── renderer.ex         # IO.ANSI live output
├── report.ex           # final markdown report
├── config.ex           # Config.llm_client, Config.model_for/1
├── types.ex            # GATE types: Idea, Review, Attempt, Result, ProjectContext
├── llm/                # LLM clients: anthropic (HTTP), claude_cli (subprocess), mock (tests)
├── agents/             # GATE agents: agent (behaviour+helpers), idea_writer, technical_researcher, qa
└── build/              # BUILD pipeline (post-gate)
    ├── types.ex        # Plan, Step, PreCheck, Review — namespaced, do not collide with gate types
    ├── plan_io.ex      # encode/decode the plan markdown artefact
    ├── orchestrator.ex # Planner -> PreChecker -> write plan file
    └── agents/         # planner, pre_checker, reviewer
```

Slash commands live in `commands/*.md`. The plugin manifest is `.claude-plugin/plugin.json` (the version published to the marketplace) and `.claude-plugin/marketplace.json` (this repo as a self-hosted marketplace).

## Conventions

- **Tests use `Trivium.LLM.Mock`** keyed by `:role` opt. Pattern: `Mock.set_script(:role, [response])` then pass `llm_client: Mock` to the agent. See `test/trivium/agents/qa_test.exs` for the canonical setup. Tests are `async: false` because Mock is a global Agent.
- **Agents return `{:ok, struct}` or `{:error, reason}`.** Never raise from agent code — the orchestrator decides what to do with errors.
- **Build agents extract JSON from a fenced ```json block** in the LLM response (regex-based). Adjust the regex if you change the prompt's output contract; never the other way round.
- **Plan markdown format** (`docs/trivium/<date>-<slug>-plan.md`) has YAML-ish front-matter (`topic`, `created`, `base_ref`, `status`, `trivium_version`) plus `## Context`, `## Pre-check notes`, `## Steps` (GFM checkboxes), and an optional `## Review` (re-runs append `## Review (2)`). `Trivium.Build.PlanIO` is the only module that touches this format — never hand-roll markdown elsewhere.
- **`base_ref`** is captured at build time via `git rev-parse HEAD` and is the contract between `/trivium-build` and `/trivium-review`. The reviewer diffs `git diff <base_ref>..HEAD`.
- **Slash commands talk to the escript via the `TRIVIUM_PLAN_WRITTEN: <path>` marker** on stdout. Don't change that string; the slash command markdown depends on it.

## What to skip

- Don't add Elixir to the host or suggest the user does. Always Docker.
- Don't write JSON parsing for YAML — front-matter is intentionally a flat key:value map (see `Trivium.Build.PlanIO.parse_front_matter/1`).
- Don't add a Coder agent. The pipeline is intentionally human-in-the-loop at the implementation step (or `/trivium-execute` driven by Claude Code itself, not an internal agent).
- Don't extract a "shared LLM stub" for tests — `Trivium.LLM.Mock` already covers that need.

## Reference docs

- `docs/2026-04-21-project-mode-design.md` — original project-mode (gate against a real codebase) design
- `docs/2026-04-21-plan-build-review-design.md` — pipeline (build/execute/review) design
- `docs/2026-04-21-plan-build-review-plan.md` — the implementation plan that built the pipeline (TDD task-by-task)
