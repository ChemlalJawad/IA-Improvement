# AGENTS.md

<!-- kit:managed - Always-loaded context for every AI agent working in this repository (Copilot, Claude, Codex...).
     Budget: <= 120 lines. Every line is paid on every request: keep only what prevents real mistakes.
     {{...}} placeholders are filled by /bootstrap. New rules are added by /retro. -->

## Project
- {{PROJECT_SUMMARY: one sentence - what this service does and for whom}}
- Stack: .NET {{DOTNET_VERSION}}, Clean Architecture + DDD, Azure, Azure DevOps (repos + pipelines).
- Architecture map, conventions and golden examples: [docs/ai/project-context.md](docs/ai/project-context.md). Read it before writing code in an area you have not seen yet.
- Business vocabulary (FR / NL / EN): [docs/ai/glossary.md](docs/ai/glossary.md). Use these terms in code, tests and specs.

## Commands (from the repository root)
- Verify a change (build + tests affected by the change, compact output):
  `pwsh -NoProfile -File .github/skills/dotnet-build-test/scripts/dotnet-check.ps1`
- All tests: add `-Test -Scope all`. One test: `-Test -Filter "FullyQualifiedName~TestName"`.
- Raw commands: build `{{BUILD_COMMAND}}` | test `{{TEST_COMMAND}}` | run `{{RUN_COMMAND}}`
- Kit scripts need PowerShell 7 (`pwsh`). Without it use `powershell -NoProfile -ExecutionPolicy Bypass -File` (run /bootstrap to switch all commands automatically).

## How we work (non-negotiable)
1. **Explore, plan, implement, verify, review.** Anything bigger than a small fix starts with a spec in `specs/` (skills `spec`, `spec-plan`, `spec-implement`).
2. **Verify your own work.** Never say "done" without running the build and the relevant tests. Report what you ran and the result.
3. **Small steps.** One task at a time, the build stays green, diffs stay reviewable.
4. **Tests first** for behavior changes (red, green, refactor). Never delete, skip or weaken a test to get green: ask.
5. **Respect the layers:** Domain <- Application <- Infrastructure / Presentation. Never add a project reference or package that breaks the dependency rule; propose an ADR instead.
6. **Mirror existing code.** Before writing new code, open the golden example for that pattern (project-context.md) and follow it.
7. **Internal packages first.** Check [docs/ai/internal-packages.md](docs/ai/internal-packages.md) before writing infrastructure code or adding a library. Never guess an internal API. Never add a NuGet package without asking.
8. **No secrets, no personal data.** Secrets live in user-secrets, Key Vault or pipeline variable groups. Tests and examples use synthetic data only (GDPR: no real policyholders, claims, national register numbers or IBANs).
9. **Ask when it matters.** Ambiguous requirement or hard-to-reverse decision: ask. Otherwise proceed and state your assumptions.
10. **Keep context lean.** Delegate broad searches to the Researcher subagent, read files just in time, summarize long outputs, start a new session per task or spec phase. Independent tasks run in parallel, one git worktree each (`parallel-work` skill).

## Git and Azure DevOps
- Branches: `{{BRANCH_PATTERN}}` from `{{BASE_BRANCH}}`. Never commit on protected branches ({{PROTECTED_BRANCHES}}).
- Commits: Conventional Commits (`feat(scope): ...`), linked to the work item ({{WORK_ITEM_STYLE}}). Commit only when asked.
- Never push, force-push, complete a PR, queue a pipeline or change Azure resources without explicit approval. PRs are created as drafts.

## Where things are
- `specs/` specs, plans, task lists | `docs/adr/` architecture decisions | `docs/ai/` AI context (project context, glossary, internal packages, learnings, evals)
- `.github/agents` roles | `.github/skills` workflows and know-how | `.github/instructions` rules per file type | `.github/hooks` guardrails and quality gate | `.github/kit/config.json` kit settings
- Hooks enforce the guardrails. If a tool call is blocked or a quality gate fails, read the reason and fix the cause; never work around a guardrail.

## Learned rules
<!-- kit:learnings - one line per rule, added by /retro when a mistake must not happen again. Prune when obsolete. -->
