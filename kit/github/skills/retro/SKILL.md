---
name: retro
description: Continuous improvement loop - analyze the current session, the hook logs and review feedback, extract the lessons, and propose precise updates to AGENTS.md, instructions, skills, agents, glossary, package notes or eval scenarios. Use at the end of a task or PR, after a frustrating session, or weekly.
argument-hint: "[days of logs to analyze, default 7]"
disable-model-invocation: true
---
# Retro: make the next session better than this one

"Every time the agent gets something wrong, encode the fix so it never happens again" - but every rule must earn its tokens.

## 1. Gather evidence (5 minutes)
- Hook logs: `pwsh -NoProfile -File .github/skills/retro/scripts/summarize-logs.ps1 -Days 7` (denied/asked commands, quality-gate failures, recurring diagnostics).
- This session: where did the user correct the agent? Which attempts failed? What did the agent have to discover the hard way?
- Review feedback: comments on the latest PRs (MCP tools) and Reviewer findings.
- Recent entries of `docs/ai/learnings.md` (do not re-learn an already encoded lesson).
- If unclear, ask the user two quick questions: "What frustrated you?" and "What should the agent have known?"

## 2. Turn each lesson into the right artifact
| Lesson type | Where it goes | Form |
|---|---|---|
| Critical, applies everywhere | `AGENTS.md` "Learned rules" | one line, imperative, with the why |
| Specific to a layer or file type | `.github/instructions/<x>.instructions.md` | one bullet, ideally with a good/bad example |
| A procedure or recurring workflow | a skill (new or updated) | steps + verification |
| Role behavior | `.github/agents/<role>.agent.md` | one rule |
| A convention best shown by code | `docs/ai/project-context.md` golden example | file path |
| Internal package know-how | `docs/ai/packages/<Id>.md` "Notes for agents" | one line |
| Business vocabulary | `docs/ai/glossary.md` | one row |
| Must be enforced, not suggested | `.github/kit/config.json` (guard rule, layer rule) or a test | rule + test-hooks.ps1 |
| Regression risk | `docs/ai/evals/scenarios.md` | one scenario with pass criteria |
| Bug that escaped review, or an incident | `docs/ai/evals/scenarios.md` (+ `code-review` checklist if the reviewer should have caught it) | a "planted bug" scenario reproducing it, with the PR or work item link |
| One-off, not generalizable | `docs/ai/learnings.md` only | one row |

## 3. Propose, then apply
- Show a short table: lesson, target file, exact change (diff-sized). Prefer editing or replacing an existing rule over adding one.
- Prune in the same pass: remove rules that are obsolete, duplicated, or never prevented anything. Respect the budgets (kit-authoring skill).
- Apply after the user agrees. Append one row per lesson to `docs/ai/learnings.md` (date, context, lesson, encoded in).
- If a guard or config changed: run `test-hooks.ps1`. If behavior changed: name the eval scenarios to re-run.
- Suggest the commit `chore(ai): retro <date>` (team-shared improvements are the point).
