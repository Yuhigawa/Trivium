---
description: Review the diff against a Trivium plan and append findings to the plan file
argument-hint: "<path-to-plan.md>"
---

The user wants Trivium to review the implementation against a plan. The plan path is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps`. If it fails, tell the user to start Docker and stop.

2. Run:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium review "$ARGUMENTS"
```

3. Surface the output:
   - Exit code 0 → verdict `approved`. Show the verdict block + tell the user the plan file's `## Review` section was updated.
   - Exit code 2 → verdict `needs_work`. Show findings + improvements; remind the user the plan status is now `needs_work` and they can re-run the review after fixes (which will append `## Review (2)`).
   - Exit code 1 → error. Surface stderr.
