---
description: Execute a Trivium plan step by step, then auto-trigger review
argument-hint: "<path-to-plan.md>"
---

The user wants to execute a Trivium plan. The plan path is in `$ARGUMENTS`.

Steps:

1. Read the plan file at `$ARGUMENTS` with the Read tool.

2. Check the front-matter `status:` field:
   - `draft` or `in_progress`: proceed.
   - `approved`: ask "This plan is already approved. Re-execute?" — only proceed on yes.
   - `review_pending` or `needs_work`: warn the user and ask whether to re-execute.

3. Update the front-matter to `status: in_progress` using the Edit tool (replace the line `status: <whatever>` with `status: in_progress`).

4. Convert the unchecked steps (lines starting `- [ ] **N.`) into TODOs with TaskCreate, one TODO per step, using the step title as the TODO content.

5. For each step in order:
   a. Mark the TODO as `in_progress`.
   b. Implement the step — read the listed `**Files**`, write code, run any tests implied by `**Acceptance**`.
   c. When the step's acceptance criterion is met, mark the checkbox `[x]` in the plan file (Edit: change `- [ ] **N.` to `- [x] **N.`).
   d. Mark the TODO as `completed`.
   e. If a step fails: append a `**Failure note:**` line below the step in the plan file, set front-matter `status: needs_work`, leave the checkbox `[ ]`, do NOT proceed to the review, and report to the user.

6. After all steps are `[x]`:
   a. Update front-matter `status: review_pending`.
   b. Run `/trivium-review $ARGUMENTS` by following the instructions in `commands/trivium-review.md`.

7. Surface the review verdict to the user.
