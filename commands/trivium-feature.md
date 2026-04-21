---
description: Run Trivium feature evaluation — problem/solution/scope/criteria spec, scored independently by 3 agents
argument-hint: "<feature description>"
---

The user wants to evaluate a feature idea with Trivium's 3-agent pipeline. The feature description is in `$ARGUMENTS`.

Steps:

1. Confirm Docker is running: `docker ps` (if it fails, tell the user to start Docker and stop).

2. Invoke the Trivium wrapper:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/trivium --path "$PWD" --type feature --task "$ARGUMENTS"
```

3. Report the result:
   - **APPROVED**: show the feature spec (Problem, Solution, Scope, Out-of-scope, Success criteria) and each agent's score.
   - **REJECTED**: show the final report verbatim. Use the failing reviewers' justifications as the honest feedback — don't soften them.
   - **ERROR**: surface the error.

On approval, do NOT start implementing. Ask the user if they want to proceed with the spec or iterate further.
