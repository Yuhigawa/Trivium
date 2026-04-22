---
description: Generate a development plan + pre-check from an approved spec, optionally execute it
argument-hint: "<spec text or path-to-spec.md>"
---

The user wants to turn a spec into a structured plan. The spec input is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps`. If it fails, tell the user to start Docker and stop.

2. Resolve the spec input:
   - If `$ARGUMENTS` is a path that exists, use it as-is.
   - Otherwise, write `$ARGUMENTS` to a temp file at `/tmp/trivium-spec-$$.md` and use that path.

3. Run:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium build <spec-path> --path "$PWD"
```

4. Parse the output. The last line should be `TRIVIUM_PLAN_WRITTEN: <path>`.
   - If you see that marker: read the plan file, summarise the steps for the user (numbered list, one line each), and **show the pre-check notes** prominently if they are anything other than "No conflicts found.".
   - If the pre-check flagged revisions, ask the user: "Pre-check suggested revisions — do you want to revise the plan first, or proceed?" Wait for the answer.
   - Otherwise, proceed to step 5.

5. **Ask the user:** "Quer que eu execute esse plano agora?" Wait for the answer.
   - If yes: follow the instructions in `commands/trivium-execute.md` using the plan path as input.
   - If no: tell the user "OK — when you're ready, run `/trivium-execute <plan-path>`" and stop.

6. If the bash command failed (no `TRIVIUM_PLAN_WRITTEN:` marker), surface the stderr and stop.
