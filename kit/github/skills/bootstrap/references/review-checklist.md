# Human review after /bootstrap (10 minutes, before the first commit)

- [ ] `AGENTS.md`: no `{{...}}` left, commands correct (copy-paste one), under 120 lines
- [ ] `docs/ai/project-context.md`: facts correct; every golden example is really the file you want people to copy
- [ ] `.github/instructions/*-layer.instructions.md`: `applyTo` globs match the real folders; project-specific bullets are true
- [ ] `.github/kit/config.json`: layer rules match the intended dependencies; protected branches and base branch correct;
      internal package prefixes correct; quality gate test filter acceptable
- [ ] `docs/ai/packages/*.md`: purpose lines right; nothing confidential that must not be in the repository
- [ ] `docs/ai/glossary.md`: business terms FR / NL / EN for the main concepts
- [ ] `.vscode/mcp.json`: servers start (MCP: List Servers) and no secret is written in the file
- [ ] `test-hooks.ps1` all PASS and the latency is acceptable
- [ ] Try two scenarios from `docs/ai/evals/scenarios.md` (S1 and S6) in a fresh session
- [ ] Commit: `chore(ai): bootstrap AI kit context`, then share with the team (they get the same agents, skills and guardrails)
