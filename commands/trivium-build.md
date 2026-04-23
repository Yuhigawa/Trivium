---
description: Generate a development plan + pre-check from an approved spec, optionally execute it
argument-hint: "[--auto-execute] <spec text or path-to-spec.md>"
---

The user wants to turn a spec into a structured plan. The full input is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps`. If it fails, tell the user to start Docker and stop.

2. Detect the auto-execute flag:
   - If `$ARGUMENTS` starts with `--auto-execute` (or contains it as a standalone token), set `AUTO=1`, strip the token, and treat the rest as the spec input.
   - Otherwise `AUTO=0`.

3. Resolve the spec input (after stripping the flag):
   - If it is a path that exists, use it as-is.
   - Otherwise, write it to a temp file at `/tmp/trivium-spec-$$.md` and use that path.

4. Run (append `--auto-execute` only when `AUTO=1`):

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium build <spec-path> --path "$PWD" [--auto-execute]
```

5. Parse the output. The last line should be `TRIVIUM_PLAN_WRITTEN: <path>`.
   - If you see that marker: read the plan file, summarise the steps for the user (numbered list, one line each), and **show the pre-check notes** prominently if they are anything other than "No conflicts found.".
   - If the pre-check flagged revisions, ask the user: "Pre-check suggested revisions — do you want to revise the plan first, or proceed?" Wait for the answer.
   - Otherwise, proceed to step 6.

6. Decide whether to execute:
   - Check the plan front-matter for `auto_execute: true`.
   - If `auto_execute: true`: tell the user "Auto-execute habilitado — disparando `/trivium-execute` agora." and follow `commands/trivium-execute.md` using the plan path as input. Skip the prompt.
   - If `auto_execute: false`: ask the user "Quer que eu execute esse plano agora?" Wait for the answer.
     - If yes: follow `commands/trivium-execute.md` using the plan path as input.
     - If no: tell the user "OK — when you're ready, run `/trivium-execute <plan-path>`" and stop.

7. If the bash command failed (no `TRIVIUM_PLAN_WRITTEN:` marker), surface the stderr and stop.
