---
name: parallel-work
description: Run several agent sessions in parallel, one task per git worktree (its own folder and branch) - create, list and clean up worktrees safely and split work into independent tasks, the way Anthropic engineers keep several sessions running at once. Use when the user wants to work on several tasks or specs at the same time, try two approaches side by side, or start a task without disturbing the current working tree.
argument-hint: "[new <title> | list | remove <folder>]"
---
# Parallel work: one task, one worktree, one session

A session waiting for a build or a review should not block the next task. With one worktree per task, sessions never
touch each other's files, branches or bin/obj, and each worktree keeps its own `.ai-local` state (hook logs, gate cache).

## Commands
```
pwsh -NoProfile -File .github/skills/parallel-work/scripts/worktree.ps1 -New "<task title>" -WorkItem <id>
```
| Need | Arguments |
|---|---|
| New worktree and branch (team branch pattern, configured base branch, fetched first) | `-New "<title>" [-WorkItem 1234] [-Base origin/develop] [-Open]` |
| All worktrees: branch, uncommitted changes, last commit | `-List` |
| Remove a merged or abandoned one (refused while it has uncommitted changes) | `-Remove <folder> [-DeleteBranch]` |
| Forget worktrees whose folder was deleted by hand | `-Prune` |

New worktrees go to `<repo>.worktrees/<workitem>-<slug>`, next to the repository and outside its working tree.

## What to run in parallel
- Good: independent specs or bugs in different areas, a spike next to the real work, two designs to compare, a review or docs while a feature is implemented.
- Bad: tasks touching the same files or aggregate, two EF Core migrations at once (snapshot conflicts, see `ef-core`), a task that needs another one's result. Sequence those.
- 2-4 parallel sessions is plenty when a human reviews everything. Abandon a session that drifts instead of rescuing it.

## Steps
1. Agree with the user on which tasks are independent; propose a split (one spec each) when a big task has independent parts.
2. `worktree.ps1 -New` per task, then give the user the printed `code -n "<path>"` command (or pass `-Open`).
3. In each window: one chat session for one task (`/spec`, `/spec-implement specs/NNN-...`, or the implementer agent). Hooks and the quality gate run in each worktree.
4. Before the pull request: `dotnet-check.ps1 -Base origin/<base>` in that worktree, then the `git-workflow` skill.
5. After the merge: `worktree.ps1 -Remove <folder> -DeleteBranch` (never forces; with squash merges the branch is kept and you delete it yourself).

VS Code can also start a chat session in worktree isolation from the session picker. Use the script when you want team
branch names, one VS Code window per task and a clean-up routine.

## .NET specifics
- Each worktree builds on its own (bin/obj); the NuGet cache and user secrets are shared, nothing to copy. First build: `dotnet restore`.
- Two APIs cannot listen on the same port: in the second worktree use `dotnet run --urls http://localhost:<free port>`.
- Integration tests on one shared local database interfere: use one database name per worktree, or Testcontainers.
- Spec numbers can collide across parallel branches: renumber the later spec when merging.

## Never
Force-remove a worktree, delete an unmerged branch, or run destructive git commands in another session's worktree.
