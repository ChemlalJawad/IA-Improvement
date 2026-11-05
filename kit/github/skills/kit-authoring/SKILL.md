---
name: kit-authoring
description: Rules, budgets and templates for creating or editing this repository's AI customizations - AGENTS.md, .instructions.md files, custom agents, skills, hooks and the kit config - so they stay effective, cheap in tokens and portable across Copilot harnesses (Local, Copilot, CLI). Use whenever you add or modify files under .github/agents, .github/skills, .github/instructions, .github/hooks, .github/kit or AGENTS.md.
---
# Authoring the AI kit

## Which customization for what
| Need | Use | Loaded |
|---|---|---|
| Facts and rules every task needs | `AGENTS.md` | always (keep tiny) |
| Rules for a layer or file type | `.github/instructions/*.instructions.md` with `applyTo` | when matching files are touched |
| A procedure, workflow or know-how | skill `.github/skills/<name>/SKILL.md` (+ scripts, references) | description always, body on demand |
| A role with its own tools and behavior | custom agent `.github/agents/<name>.agent.md` | when selected or used as subagent |
| Something that must ALWAYS happen or NEVER happen | hook + `.github/kit/config.json` | deterministic, every event |
| Mechanical, repeatable work | a script inside the skill | run on demand, compact output |

Prompt files are not used: they only run in the Local harness. Skills work in every harness and can be slash commands.

## Budgets
- AGENTS.md <= 120 lines; instruction file <= 60 lines; SKILL.md <= 150 lines (move details to `references/`); agent body <= 60 lines.
- Skill and agent descriptions: what it does AND when to use it, specific nouns (they decide when the model loads them).

## Formats (exact)
- **Skill**: folder name = `name` (lowercase letters, digits, hyphens, <= 64 chars), `description` <= 1024 chars. Optional: `argument-hint`, `user-invocable: false` (hide from the slash menu), `disable-model-invocation: true` (slash command only, for workflows with side effects such as bootstrap or retro). Reference files with relative Markdown links.
- **Instructions**: front matter `name`, `description`, `applyTo` (comma-separated globs relative to the repo root).
- **Agent**: `name` (lowercase, same as the file name), `description`, `tools` (aliases `read`, `edit`, `search`, `execute`, `agent`, `web`, `todo`, MCP `server/*`), `agents` (allowed subagents), `handoffs` (label, agent, prompt, send), `user-invocable`, `disable-model-invocation`, optional `model` (written by `configure-kit.ps1 -ApplyModels`). `agents`, `handoffs` and `argument-hint` only work in the Local harness; they are ignored elsewhere.
- **Hooks**: `.github/hooks/*.json`, PascalCase events (`SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`...), command entries with `powershell` (Windows) and `bash` fields and `timeoutSec`. Deny = exit code 2 + reason on stderr; ask/allow = JSON on stdout.

## Writing style
- Imperative, specific, one idea per line. Explain the why when it is not obvious.
- Show good vs bad examples; point to golden example files rather than pasting code.
- No rule that analyzers, formatters, the guard or the quality gate already enforce.
- No duplication between AGENTS.md, instructions and skills: link instead.

## Scripts
- Windows PowerShell 5.1 AND PowerShell 7 compatible; ASCII only (5.1 reads BOM-less files as ANSI).
- Dot-source `.github/kit/lib/KitCore.ps1` (and `KitDotnet.ps1`); compact, high-signal output; exit code 0/1.
- Hooks fail open on internal errors, read stdin JSON, write exactly one JSON object to stdout.

## Verify every change
- Hooks or config: `pwsh -NoProfile -File .github/hooks/scripts/test-hooks.ps1`.
- Behavior (agents, skills, instructions): re-run the related scenarios of `docs/ai/evals/scenarios.md` in a fresh session; add a scenario for every new rule that matters.
- Record the change in `docs/ai/learnings.md` when it comes from a lesson.
