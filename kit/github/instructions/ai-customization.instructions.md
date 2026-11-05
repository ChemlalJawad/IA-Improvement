---
name: 'Editing the AI kit'
description: 'Rules for editing AGENTS.md, agents, skills, instructions, hooks, kit config and docs/ai: token budgets, portability, verification.'
applyTo: 'AGENTS.md,.github/agents/**,.github/skills/**,.github/instructions/**,.github/hooks/**,.github/kit/**,docs/ai/**'
---
# Editing the AI kit

Load the `kit-authoring` skill and follow it. Essentials:

- Budgets: AGENTS.md <= 120 lines, an instruction file <= 60 lines, a SKILL.md <= 150 lines (details go to `references/`).
- Every rule must prevent a real, observed mistake. Prefer a golden example over a rule. Delete rules that no longer earn their tokens.
- Skills: `name` equals the folder name (lowercase, digits, hyphens); the description says what the skill does AND when to use it.
- Agents: least-privilege `tools`; a role description that lets other agents pick them as subagents.
- Scripts: compatible with Windows PowerShell 5.1 and PowerShell 7, ASCII only; hook scripts fail open.
- After changing hooks or `.github/kit/config.json`, run `.github/hooks/scripts/test-hooks.ps1`. After changing behavior, re-run the related scenarios in `docs/ai/evals/scenarios.md`.
