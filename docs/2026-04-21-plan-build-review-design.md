# Trivium plan → build → review pipeline

**Status**: Draft
**Date**: 2026-04-21
**Owner**: Yuhigawa

## Problem

Trivium today is a *gate*: the three-agent quorum (`IdeaWriter`,
`TechnicalResearcher`, `QA`) scores a task and returns `:approved` or
`:rejected`. After approval the loop ends — there is no pipeline step that
(a) turns the spec into a concrete, ordered development plan, (b) checks the
plan against the existing codebase before coding starts, or (c) reviews the
resulting code against the plan and pre-existing business rules.

Users who pass the gate still have to hand-carry the spec into a separate
implementation session, manage the plan themselves, and rely on ad-hoc review.
That is the gap this feature closes.

## Goals

- Extend Trivium with three new commands that form a linear pipeline after
  gate approval: **build → execute → review**.
- Keep Trivium's philosophy of being a *validator / orchestrator*, not a code
  executor. Humans (and Claude Code) still write the code; Trivium produces
  and audits the plan.
- Produce a single durable artefact — a plan file — that is human-readable,
  Elixir-parseable, and Claude-executable.
- Automate the handoff chain: `/trivium-build` optionally dispatches
  `/trivium-execute`, which automatically dispatches `/trivium-review` on
  completion.

## Non-goals

- Autonomous end-to-end coding (no "Coder" agent).
- Parallel execution of multiple plans.
- Automatic rollback of code on review failure.
- Git hook integration (post-commit auto-review) — out of scope for v1.
- Replacing the existing `/trivium-feature` / `/trivium-bug` /
  `/trivium-analysis` gates. The new pipeline is additive.

## End-to-end flow

```
┌─ /trivium-feature (exists) ───────────────────┐
│  3-agent gate → :approved                     │
└───────────────┬───────────────────────────────┘
                │ approved (or user enters /trivium-build directly)
                ▼
┌─ /trivium-build <spec-or-input> ──────────────┐
│  1. Planner agent: generate ordered steps     │
│     with acceptance criteria                  │
│  2. PreChecker agent: read relevant existing  │
│     code, flag conflicts, suggest plan edits  │
│  3. Write docs/trivium/<date>-<slug>-plan.md  │
│     (YAML front-matter + checklist + notes)   │
│  4. Claude asks the user: "Execute now?"      │
└───────────────┬───────────────────────────────┘
        yes     │     no
                ▼     └──► user invokes /trivium-execute later
┌─ /trivium-execute <plan-path> ────────────────┐
│  Claude Code loads plan → TODOs →             │
│  implements step by step, ticking [x]         │
│  On completion: auto-invoke /trivium-review   │
└───────────────┬───────────────────────────────┘
                ▼
┌─ /trivium-review <plan-path> ─────────────────┐
│  Reviewer agent reads plan + base_ref         │
│  git diff base_ref..HEAD                      │
│  Validates business-rule preservation,        │
│  plan adherence, improvement suggestions      │
│  Appends ## Review section, updates status    │
└───────────────────────────────────────────────┘
```

## Components

### New Elixir modules

- `lib/trivium/agents/planner.ex` — input: spec text (plus optional
  `ProjectContext`); output: `%Plan{steps: [%Step{}], base_ref, topic}`. Uses
  the existing `Trivium.LLM.ClaudeCLI` client.
- `lib/trivium/agents/pre_checker.ex` — input: `%Plan{}` + `ProjectContext`;
  reads files the plan touches, flags collisions, proposes edits. Output:
  `%PreCheck{verdict: :ok | :revise, notes: [...], suggested_changes: [...]}`.
- `lib/trivium/agents/reviewer.ex` — input: `%Plan{}` + diff string; output:
  `%Review{verdict: :approved | :needs_work, findings: [...]}`.
- `lib/trivium/build_orchestrator.ex` — sequential coordinator for
  Planner → PreChecker → plan file write. No parallelism; straightforward
  pipeline.
- `lib/trivium/plan.ex` — encode/decode the plan markdown artefact
  (front-matter + steps + status mutations).

### New types in `lib/trivium/types.ex`

- `%Plan{topic, base_ref, steps, status, pre_check_notes, created_at}`
- `%Step{index, title, files, acceptance, notes, done?}`
- `%PreCheck{verdict, notes, suggested_changes}`
- `%Review{verdict, findings, improvements}`

### CLI additions

`lib/trivium/cli.ex` gains two subcommands:

- `trivium build <input>` — reads input (string, path, or stdin), runs
  `BuildOrchestrator`, writes plan file, prints trailing
  `TRIVIUM_PLAN_WRITTEN: <path>` marker.
- `trivium review <plan-path>` — loads the plan, computes
  `git diff <base_ref>..HEAD`, runs `Reviewer`, appends `## Review` to the
  plan, updates status.

### Slash commands (in `commands/`)

- `trivium-build.md` — wraps `bin/trivium build`, parses the
  `TRIVIUM_PLAN_WRITTEN:` marker, summarises the plan to the user, then asks
  "Execute this plan now?". On yes, follows the `trivium-execute.md`
  instructions inline with that path.
- `trivium-execute.md` — instructs Claude to: set `status: in_progress`,
  convert the checklist to TODOs, implement step by step (ticking `[x]` in
  the file), set `status: review_pending` on completion, then invoke
  `/trivium-review <plan-path>`.
- `trivium-review.md` — wraps `bin/trivium review`, renders the review
  output, surfaces the verdict.

### Reused infrastructure

- `Trivium.LLM.ClaudeCLI` — LLM client (no change).
- `Trivium.LLM.Mock` — extended to cover new agent prompts in tests.
- `ProjectContext` — passed through to Planner / PreChecker.
- `bin/trivium` — existing escript wrapper; no change.

## Plan artefact format

**Path**: `docs/trivium/YYYY-MM-DD-<slug>-plan.md`

```markdown
---
topic: "Add X to Y"
created: 2026-04-21T15:30:00Z
base_ref: a1b2c3d4
status: draft
trivium_version: 0.1.0
---

# Plan: Add X to Y

## Context
<2-3 lines summarising the spec / input>

## Pre-check notes
<PreChecker output: conflicts with existing code, applied suggestions,
 warnings for the implementer>

## Steps

- [ ] **1. <short title>**
      **Files**: `lib/foo/bar.ex`
      **Acceptance**: <verifiable criterion>
      **Notes**: <optional>

- [ ] **2. <short title>**
      ...

## Review
<written by /trivium-review; empty until review runs>
```

### Design decisions

1. **YAML front-matter**. `base_ref` is captured via `git rev-parse HEAD` at
   build time. `status` transitions: `draft → in_progress → review_pending →
   approved | needs_work`.
2. **GFM checkboxes** for steps. `/trivium-execute` ticks `[x]` as it
   completes each one, giving visible progress.
3. **Acceptance criterion per step** — the reviewer uses these to verify the
   diff actually delivers what was promised.
4. **Review section is appended, not overwritten**. Re-running review adds
   `## Review (2)`, preserving history.
5. **No YAML dep**. `String.split("---")` + regex is enough for the
   front-matter; keeps dependencies minimal.

## Handoff mechanics

`/trivium-build`:

1. Slash command runs `bin/trivium build "$ARGUMENTS"`.
2. Trivium runs Planner → PreChecker → writes plan.
3. Trivium emits final line: `TRIVIUM_PLAN_WRITTEN: <path>`.
4. The slash command markdown instructs Claude: on seeing that marker, read
   the file, summarise the steps, and ask the user "Execute this plan now?".
   If yes, follow `trivium-execute.md` with the path; if no, end.

`/trivium-execute <plan-path>`:

1. Markdown instructs Claude to:
   - Update front-matter `status: in_progress` via `Edit`.
   - Create a TODO per step with TaskCreate.
   - Implement step by step, ticking `[x]` in the file.
   - On completion, set `status: review_pending`.
   - Invoke `/trivium-review <plan-path>` (via bash or Skill).

`/trivium-review <plan-path>`:

1. Slash command runs `bin/trivium review <plan-path>`.
2. Trivium reads plan, extracts `base_ref`, shells out `git diff
   <base_ref>..HEAD`, passes plan + diff to Reviewer.
3. Appends `## Review` to the plan, updates status to `approved` or
   `needs_work`.
4. Prints verdict.

**Why structured markers?** Claude Code sees bash stdout as raw text; a
machine-readable trailer (`TRIVIUM_PLAN_WRITTEN:`) lets the slash command
reliably detect success and pick up the path without relying on the LLM to
interpret free-form output.

## Error handling

### `/trivium-build`
- Planner or LLM error → Trivium exits non-zero, no file written.
- PreChecker returns `:revise` → plan is still written, `status: draft`, the
  `## Pre-check notes` section surfaces the suggestions; the slash command
  warns the user and asks whether to revise before executing.
- No `base_ref` (uninitialised repo, etc.) → fatal abort with a clear
  message. Review cannot function without a base ref.

### `/trivium-execute`
- Step fails mid-implementation → Claude sets `status: needs_work`, leaves
  the step unchecked, appends a note, does **not** trigger review, reports
  to the user.
- User interrupts → `status: in_progress` with partial `[x]`. Re-running
  `/trivium-execute` on the same file resumes, skipping completed steps.
- Plan already `status: approved` → Claude warns and asks whether to
  re-execute.

### `/trivium-review`
- `git diff base_ref..HEAD` is empty → review aborts with "nothing to
  review"; status is untouched.
- Reviewer returns `:needs_work` → status becomes `needs_work`, findings
  appear in `## Review`, CLI exits non-zero.
- `base_ref` missing in git (rebased away) → abort with "base_ref lost;
  rebuild the plan".

### Explicitly out of scope
- Parallel plan execution.
- Sub-plans / plan merging.
- Automatic code rollback on review failure (human decision).

## Testing strategy

Follows existing `test/trivium/` layout, using `Trivium.LLM.Mock`.

### Unit
- `planner_test.exs` — structured input → `%Plan{}`, step parsing.
- `pre_checker_test.exs` — verdicts `:ok` and `:revise`, suggested changes
  surfacing.
- `reviewer_test.exs` — verdicts `:approved` and `:needs_work`, findings
  structure.
- `plan_test.exs` — round-trip serialize / parse of the markdown artefact;
  status mutation helpers.

### Integration
- `build_orchestrator_test.exs` — `build/2` with mocks, verifies file
  contents end-to-end.
- `cli_test.exs` — new subcommands `build` and `review`, exit codes, the
  `TRIVIUM_PLAN_WRITTEN:` marker emission.

### Manual (not CI)
- Slash-command markdown behaviour — exercised by running the commands in
  a Claude Code session against a sample repo.
- Real Claude CLI integration — covered by existing mock-based tests; live
  runs are smoke-tested manually.

## Open questions

None outstanding at spec time. Questions raised during brainstorming were
resolved:

- Who writes the code? **Human / Claude Code, not a Trivium agent.**
- How does the review get the diff? **`git diff base_ref..HEAD`, with
  `base_ref` captured in the plan front-matter at build time.**
- How is the review triggered? **Automatically at the end of
  `/trivium-execute`.**
- Pre-check and review are single agents or a 3-agent quorum? **Single
  agents each.**
