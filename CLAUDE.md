@AGENTS.md

## Parallel implementation workflow (Claude)

When a task splits into independent implementation pieces:

1. Work on a feature branch (never directly on `master`); commit any shared contract/spec there first so worktrees start from it.
2. Spawn at most **3** implementation subagents at once.
3. Every implementation subagent runs with **model `sonnet` (Sonnet 5.5), effort `medium`** — no other model/effort for implementation.
4. Each subagent works in **its own git worktree** (`isolation: "worktree"`), touches only its own files, and commits on its own branch.
5. After they finish: review each branch's diff, then merge the branches into the feature branch (resolve conflicts there), then verify the combined result.
