---
name: spec-implement
description: Implement the tasks of a spec's tasks.md one at a time with test-first discipline, running build and tests after each task, ticking checkboxes and keeping a progress log so work can resume in a fresh session. Use when executing an approved plan.
argument-hint: "<specs/NNN-slug> [task ids]"
---
# Spec implement: one verified task at a time

This is the long-running harness: progress lives in `tasks.md` and in git, not in the conversation.

## Start of every session
1. Read `tasks.md` (status, unchecked tasks, last progress-log lines) and the relevant part of `plan.md`.
2. `pwsh -NoProfile -File .github/skills/git-workflow/scripts/git-context.ps1`: right branch (not protected), clean or expected working tree.
3. `pwsh -NoProfile -File .github/skills/dotnet-build-test/scripts/dotnet-check.ps1 -Build`: green baseline. If red before you start, report it and stop.
4. Set `status: in-progress` in tasks.md if it is not already.

## Loop (per task, in order)
1. Read only the files the task names plus the golden example of the pattern (project-context.md).
2. **Red**: write or adapt the test for the AC; run only that test (`dotnet-check.ps1 -Test -Filter "FullyQualifiedName~<Test>"`); it must fail for the expected reason.
3. **Green**: the minimal production code that makes it pass, following the layer instructions.
4. **Refactor**: names from the glossary, no duplication; then `dotnet-check.ps1` (build + affected tests).
5. Tick the task. Append a progress-log line: `YYYY-MM-DD - T00n done - checks green - next: T00m`.
6. Commit only if the user asked for commits per task (git-workflow skill); otherwise suggest a commit at each phase checkpoint.

`[P]` tasks may be delegated to parallel subagents only when they touch disjoint files; review their diffs before ticking.

## When things go wrong
- Same error twice: stop guessing. Re-read the error, check the golden example, ask a `researcher` subagent, or ask the user.
- The plan is wrong or incomplete: do not improvise a redesign. Write the problem in the progress log and propose a plan update.
- Context is getting long (many files read, long outputs): write a precise progress-log line and suggest continuing in a new session.

## End
All tasks ticked: full `dotnet-check.ps1`, checkpoint boxes, `status: done` in tasks.md, then hand over to review (`/code-review` or the reviewer agent). Never leave the branch red at the end of a session.
