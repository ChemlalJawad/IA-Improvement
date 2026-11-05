---
name: project-discovery
description: Produce a compact map of the .NET repository - solution and projects, Clean Architecture layers and reference violations, NuGet packages (internal vs public), frameworks, test setup, Azure DevOps pipelines and golden example files per pattern. Use before architectural changes, when onboarding to an unfamiliar area, when project-context.md looks outdated, or during /bootstrap.
---
# Project discovery

One script gathers the facts in seconds; you read a ~150-line report instead of crawling the repository.

## Run
```
pwsh -NoProfile -File .github/skills/project-discovery/scripts/discover-solution.ps1
```
Outputs (machine-local, never committed):
- `.ai-local/discovery/discovery.md`: the compact report. Read this.
- `.ai-local/discovery/discovery.json`: the full data. Only query it for a specific detail (e.g. one project's packages).

## Read the report
- **Repository**: provider (Azure DevOps org/project/repo), default branch, branch prefixes, commit style, SDK pinning.
- **Solution and projects**: layer of each project (from `.github/kit/config.json` patterns), references. "Projects without layer" and "Layer violations" tell you whether the layer rules match reality.
- **Packages**: internal packages (intranet feed), unknown-origin packages (often internal too: confirm with the user), frameworks (MediatR, EF Core, xUnit...).
- **Conventions**: for each pattern (aggregate, command, handler, validator, EF configuration, endpoint, unit test...) the number of files and 1-3 golden example candidates (mid-sized files). Open one or two before writing similar code.
- **CI/CD**: per pipeline file: triggers, stages, templates, tasks, dotnet steps, variable groups, environments.
- **Hints**: what to fix in the kit configuration.

## Rules
- The report states facts, not quality: a "golden example candidate" still needs a human or agent judgment.
- Do not paste the report into the chat; quote only the lines that matter.
- Re-run after structural changes (new project, new layer, template upgrade).
