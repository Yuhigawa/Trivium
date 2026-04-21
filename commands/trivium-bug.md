---
description: Run Trivium bug-fix evaluation — root-cause analysis + fix proposal, scored independently by 3 agents
argument-hint: "<bug description>"
---

The user wants to evaluate a bug-fix task with Trivium's 3-agent pipeline. The task description is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps` (if it fails, tell the user to start Docker and stop).

2. Invoke the Trivium wrapper from the plugin's repo. The binary handles mounting the target path into its container automatically:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium --path "$PWD" --type bug --task "$ARGUMENTS"
```

3. Report the result to the user:
   - If **APPROVED**: summarize the final idea (the proposed fix) and each agent's score.
   - If **REJECTED**: show the final report verbatim. The scores and justifications are what matters — don't paraphrase them into agreement. Let the user see where reviewers disagreed.
   - If **ERROR**: surface the error message clearly.

Do NOT start implementing the fix automatically, even on approval. Trivium's job is gating — the next step is always for the user to decide whether to proceed.
