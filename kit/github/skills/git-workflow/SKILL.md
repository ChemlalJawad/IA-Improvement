---
name: git-workflow
description: Day-to-day git and pull request workflow for Azure Repos (or GitHub) - branch naming, clean Conventional Commits linked to work items, syncing with the base branch, and drafting or creating pull requests with a complete description. Use when creating a branch, committing, preparing or updating a pull request, or syncing a branch.
argument-hint: "[branch | commit | sync | pr]"
---
# Git and pull requests

Always start with the context script (branch, base, commits, diffstat, working tree, work item, PR link):
```
pwsh -NoProfile -File .github/skills/git-workflow/scripts/git-context.ps1
```

## Branch
- From the up-to-date base branch: `git fetch` then `git switch -c <pattern> origin/<base>`; pattern and base come from AGENTS.md (default `feature/<workitem>-<slug>`).
- Never commit on a protected branch (main, develop, release/*).

## Commit (only when the user asks)
1. Review what changed: `git status`, `git diff`. Stage intentionally (`git add <paths>`); never commit secrets, local settings, `.ai-local/` or build output.
2. Run `dotnet-check.ps1` first: do not commit a red build unless the user explicitly wants a WIP commit.
3. Message: Conventional Commits, imperative, the why in the body, work item reference:
   ```
   feat(claims): register broker declarations

   Brokers can declare a claim on behalf of the insured (AC-1..AC-3 of specs/012).

   AB#1234
   ```
   Follow the style of the recent commits shown by git-context.
4. Small, logical commits; one concern each.

## Sync with the base branch
- Your own branch: `git fetch` then `git rebase origin/<base>` (or merge if the team prefers; see `git.mergeStrategy` in the kit config). Shared branch: merge, never rebase.
- Conflicts: `merge-conflicts` skill. Then build + tests before continuing.
- After a rebase of an already pushed branch, the push needs `--force-with-lease`: only with the user's explicit approval.

## Pull request
1. Title: Conventional style summary. Description from `.azuredevops/pull_request_template.md`: summary, linked spec, work items, changes, how it was verified (exact commands and results), checklist.
2. Create it as a **draft**, after the user approves, in this order of preference:
   - MCP tools (`ado/*` or `company/*`);
   - `az repos pr create --draft ...` (the command is printed by git-context);
   - otherwise give the user the "Create PR (web)" link and the ready-to-paste description.
3. Reviewers, auto-complete, completion and branch deletion are human decisions.

## Never
Force-push a shared branch, push to a protected branch, rewrite published history without approval, bypass branch policies, complete a PR, delete a remote branch.
