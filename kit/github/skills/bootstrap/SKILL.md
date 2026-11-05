---
name: bootstrap
description: One-time setup that adapts this AI kit to the repository. Creates the solution from the company dotnet new template when the repo is empty, then discovers the architecture, conventions and internal NuGet packages and writes the project-specific context (AGENTS.md, docs/ai, instructions, layer rules, MCP servers, model routing). Also refreshes that context after template or package upgrades.
argument-hint: "[init | adapt | refresh]"
disable-model-invocation: true
---
# Bootstrap: adapt the kit to this repository

Goal: after this, any agent works here with accurate, minimal context and working guardrails.
Order of work: **scripts first** (cheap, deterministic), **then read** only what they point to, **ask last** (only what cannot be discovered).
Use the `context-engineer` role. Create a todo list with the steps of the chosen mode and keep it updated.
Commands below use `pwsh -NoProfile -File`; if PowerShell 7 is missing use `powershell -NoProfile -ExecutionPolicy Bypass -File` (step A2 switches all docs).

## 0. Choose the mode
- No `*.sln`, `*.slnx` or `*.csproj` in the repository: **INIT** (section B), then **ADAPT** (section C).
- `.github/kit/config.json` has `"bootstrap": { "status": "done" }`: **REFRESH** (section D), unless the user asked otherwise.
- Otherwise: **ADAPT**.

## A. Environment check (all modes, ~1 minute)
1. `pwsh -NoProfile -File .github/hooks/scripts/test-hooks.ps1` (or the `powershell` form). All PASS? Note the PreToolUse latency. On failures, see the troubleshooting section of the kit guide and tell the user; hooks are optional, the rest of the kit still works.
2. `... .github/skills/bootstrap/scripts/configure-kit.ps1 -Launcher auto -Show` (rewrites script commands in the docs if `pwsh` is missing).
3. `dotnet --info` (SDK), `git --version`, `dotnet nuget list source` (the intranet feed must be listed and enabled).

## B. INIT: create the solution from the company template
Follow [references/init-from-template.md](./references/init-from-template.md). Never use `--force` without explicit approval.

## C. ADAPT
1. **Discover**: `... .github/skills/project-discovery/scripts/discover-solution.ps1`, then read `.ai-local/discovery/discovery.md` (not the JSON).
2. **Baseline**: `... .github/skills/dotnet-build-test/scripts/dotnet-check.ps1 -Test -Scope all`. Record pre-existing failures under "Known issues" in project-context.md; do not fix them now.
3. **Internal packages**: confirm the prefixes suggested by discovery with the user and save them in `.github/kit/config.json` (`internalPackages.prefixes`, e.g. `["Contoso.*"]`). Then `... .github/skills/internal-packages/scripts/inspect-package.ps1 -AllInternal`.
4. **Conventions**: start one `researcher` subagent per area, in parallel: domain model, use cases (commands/queries/validation), persistence (EF, repositories, migrations), API (endpoints, errors, auth), cross-cutting (DI, logging, configuration), tests (unit, integration, data builders). Give each the golden-example candidates from discovery.md and ask for: conventions (bullets), the 1-2 best example files, anti-patterns seen. Max 200 words each.
5. **Write `docs/ai/project-context.md`** from its template (remove the `kit:status=template` marker). At most 250 lines, every convention with a golden example path, commands copied from what actually worked in step 2.
6. **AGENTS.md**: replace every `{{...}}` placeholder (project summary, .NET version, commands, branch pattern, base branch, protected branches, work item style). Stay under 120 lines.
7. **Instructions**: in `.github/instructions/*-layer.instructions.md`, set `applyTo` to the real project folders (from the discovery solution map) and fill each "Project-specific" section with 3-8 bullets from step 4. Delete instruction files for layers that do not exist. Same for `csharp` and `tests` project-specific sections.
8. **Kit config** (`.github/kit/config.json`): layer `projectPattern` values matching the real project names; `mayReference` matching the template's CURRENT reference graph (the template is the reference); `guard.protectedBranches` from the remote branches; `git.baseBranch`, `git.branchPattern`, `git.workItemStyle` from the history; `qualityGate.testFilter` to exclude tests that cannot run locally (ask), `bootstrap.solution`. Then re-run discovery: expect "Layer violations: none" and no project without a layer.
   Formatting: if discovery says formatting is enforced (CI runs `dotnet format` / CSharpier, or CSharpier is a local tool), run `configure-kit.ps1 -Format auto`: the quality gate then formats the changed files once per turn. Otherwise leave it `off` (formatting whole files of an unformatted codebase creates noisy diffs) unless the user wants it.
9. **Glossary**: seed `docs/ai/glossary.md` with the aggregates, entities, value objects and enums of the Domain project (code name + definition from code). Ask the user for the FR / NL business terms of the 5-10 most important ones; the rest can wait.
10. **MCP servers**: follow [references/mcp-setup.md](./references/mcp-setup.md) (company MCP, Azure DevOps, Microsoft Learn).
11. **Models**: follow [references/model-routing.md](./references/model-routing.md) (Auto or tiered routing; cost/quality trade-off).
12. **Package skills** (optional): for internal packages used in 3+ files or that shape the architecture (messaging, persistence, auth...), create `.github/skills/pkg-<short-name>/SKILL.md` with the `kit-authoring` rules: when to use, key types, do / don't, golden usages, link to the digest. At most 80 lines each.
13. **CI parity**: from the pipeline section of discovery.md, fill the "Commands and CI parity" table (local command for every pipeline step). If no pull request validation runs the layer rules, build and tests, tell the user about the kit's PR checks pipeline (`azure-pipelines` skill, section E); setting it up is their decision.
14. **Validate**: re-run `test-hooks.ps1` and `discover-solution.ps1`; `dotnet-check.ps1` must match the baseline.
15. **Finish**: `... configure-kit.ps1 -MarkBootstrapped -Solution <path-to.sln>`. Give the user the review checklist ([references/review-checklist.md](./references/review-checklist.md)) and propose the commit `chore(ai): bootstrap AI kit context`. Do not commit unless asked.

## D. REFRESH (after a template upgrade, new internal package versions, a big refactoring)
1. Re-run discovery and `inspect-package.ps1 -AllInternal` (digests keep their curated notes).
2. Compare with project-context.md and the config: update only what changed; keep human edits.
3. Re-check layer rules, instruction globs and CI parity. Log the refresh in `docs/ai/learnings.md`.

## Rules
- Never invent a convention: everything written must be backed by a file path or by the user.
- Never paste large files into the chat; summarize with paths.
- Ask before: installing a template or tool, changing nuget.config or feeds, editing pipelines, committing, pushing.
