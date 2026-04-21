---
description: Run Trivium code-analysis — findings, recommendations, risks (no implementation proposed)
argument-hint: "<what to analyze>"
---

The user wants an independent code analysis. Trivium produces findings — no solution proposed — evaluated by 3 agents. Task description is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps`.

2. Invoke the Trivium wrapper:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium --path "$PWD" --type analysis --task "$ARGUMENTS"
```

3. Report the output:
   - **APPROVED**: show the findings (Context, Findings, Recommendations, Risks, Next steps) and the agent scores.
   - **REJECTED**: show the full report. The rejection likely means findings were too vague, not grounded enough in the code, or missing coverage — surface that honestly.
   - **ERROR**: surface the error.

This mode deliberately does NOT produce an implementation plan. The output is input for further planning, not a build spec. If the user wants to implement something based on the findings, that's a separate `/trivium-feature` or normal conversation afterwards.
