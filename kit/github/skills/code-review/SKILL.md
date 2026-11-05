---
name: code-review
description: Review code changes (working tree, branch against its base, or a pull request) against the spec, Clean Architecture and DDD rules, security and privacy, EF Core and performance, tests and conventions, and produce prioritized, actionable findings. Use before opening or completing a PR, after implementing a spec, or whenever a review is requested.
argument-hint: "[base branch | PR id | specs/NNN-slug]"
---
# Code review

## 1. Context (cheap first)
- `pwsh -NoProfile -File .github/skills/git-workflow/scripts/git-context.ps1 [-Base origin/<base>]`: commits, diffstat, working tree.
- The spec (`specs/NNN-slug/spec.md`) if the branch or PR references one: the acceptance criteria are the yardstick.
- For a PR in Azure DevOps: description, linked work items and existing comments through the MCP tools.
- Run the checks yourself: `dotnet-check.ps1 -Base origin/<base>` (build + tests affected since the base). Red = Blocker.

## 2. Review passes
Large diff (> ~400 changed lines): run passes as parallel `researcher` subagents (each with the diff paths and one checklist section) and merge their findings. Otherwise do them yourself, in this order:
1. **Intent**: every AC implemented and tested; no unrequested behavior.
2. **Architecture and DDD**: layering, invariants inside aggregates, thin handlers and endpoints, no domain leak to the API.
3. **Security and privacy**: authorization, input validation, injection, secrets, personal data in logs / errors / tests.
4. **Data access**: EF queries (tracking, N+1, projections), migrations (reviewed SQL, backward compatible), transactions.
5. **Reliability and performance**: async and cancellation, exceptions, resilience, allocations in hot paths.
6. **Tests**: meaningful assertions, deterministic, synthetic data, regression tests for fixes.
7. **Simplicity**: dead code, duplication, needless abstractions; propose simpler code when it is clearly simpler.
Details: [references/checklist.md](./references/checklist.md).

## 3. Report format
```
Verdict: Approve | Approve with comments | Request changes
Checks: BUILD ok/failed, TESTS x passed / y failed (command used)

| # | Severity | Location | Finding | Suggested fix |
|---|----------|----------|---------|---------------|
| 1 | Blocker  | src/...cs:42 | ... | ... |

What is good: 1-3 bullets.
Lessons to encode (0-3): <one-line rule> -> <target file>
```
Severities: **Blocker** (wrong behavior, security or data risk, red checks), **Major** (architecture break, missing test for an AC, likely bug), **Minor** (maintainability), **Nit** (optional). At most 15 findings; group duplicates.
Lessons to encode: when a finding is a mistake an agent will repeat (a team convention, a recurring pitfall), propose the one-line rule and where it belongs (`AGENTS.md` Learned rules, a layer instruction, a package digest note). The user decides; `/retro` applies them. This is how each review makes the next session better.

## Rules
- Evidence over opinion: quote the line, explain the consequence. Say "unsure" rather than inventing.
- No findings on what analyzers or formatters enforce.
- Review only; fixes go to the implementer (handoff "Fix the findings").
