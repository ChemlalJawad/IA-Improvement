---
name: merge-conflicts
description: Resolve git merge, rebase or cherry-pick conflicts safely - understand the intent of both sides, regenerate generated files (EF Core model snapshot, lock files, designers) instead of hand-merging, verify with build and tests, and report every decision. Use when git reports conflicts or a pull request cannot be merged.
---
# Merge conflicts

## 1. Map the situation
```
pwsh -NoProfile -File .github/skills/merge-conflicts/scripts/conflict-report.ps1
```
It shows the operation (merge, rebase, cherry-pick), which side is "ours" and "theirs", each conflicted file with its hunks and a handling hint, and the commits involved.
**Rebase warning**: during a rebase "ours" is the branch you rebase onto and "theirs" is your own commit.

## 2. Resolve file by file
For each file:
1. Understand both intents: the commit messages (`git log --merge`), the base version (`git show :1:<file>`), each side (`:2:` ours, `:3:` theirs). Read the linked specs or work items if needed.
2. Apply the strategy for the file type:

| File | Strategy |
|---|---|
| Source code | Combine both intents. Keep both behaviors when compatible; if they contradict, ask the user. Never pick a side blindly. |
| Tests | Usually keep both sides' tests, then fix names and fixtures. |
| `*.csproj`, `Directory.Packages.props` | Union of references; higher version wins for patch/minor, ask for a major bump; check the layer rules. |
| EF Core model snapshot / migrations | Do not hand-merge the snapshot: take the target side, then re-create your migration (`ef-core` skill). |
| Generated files (`*.Designer.cs`, `*.g.cs`, `packages.lock.json`) | Take either side, then regenerate (build, restore, tool). |
| Pipelines YAML | Keep both changes, validate the YAML (`azure-pipelines` skill). |
| Docs and specs | Merge text; keep both decisions or ask. |

3. Remove every marker; `git diff --check` must report nothing.

## 3. Verify and report
- `dotnet-check.ps1` (build + affected tests). A conflict resolution that does not build is not resolved.
- Report: per file, the decision and why (one line each), plus the checks result.
- Ask the user before `git merge --continue`, `git rebase --continue` or `git cherry-pick --continue`. If it goes badly, `--abort` restores the previous state.

## Never
`git checkout --ours/--theirs .` on the whole tree, deleting a side's code to make it compile, committing with markers, force-pushing without approval.
