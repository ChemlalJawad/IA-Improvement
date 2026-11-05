# Model routing: quality per euro

Three strategies; ask the user which one (default: Auto). What counts is the cost of a finished, correct change,
not the price per request: a weaker model that needs two extra correction rounds is the expensive one.

## Auto (adaptive) - default, zero maintenance
Agents have no `model:` line; the user picks **Auto** (or a model) in the chat model picker and Copilot chooses per request.
Set `models.mode` to `auto` in `.github/kit/config.json` and run `configure-kit.ps1 -ApplyModels` (removes any `model:` line).

## Tiered (recommended when models and their cost multipliers are known)
| Tier | Work | Agents | Typical choice (use the exact names of your picker) |
|---|---|---|---|
| reasoning | specs, plans, architecture, reviews, hard bugs | planner, reviewer, debugger | strongest model available (Claude Opus class, top GPT class) |
| balanced | implementation, devops, bootstrap, orchestration | implementer, devops, context-engineer, conductor | Claude Sonnet class |
| fast | search and summaries for other agents | researcher | Claude Haiku class or a low-multiplier mini model |

Why: the expensive part of agentic work is wasted iterations. A strong model on planning and review prevents rework
(Anthropic's own teams use their best model for planning), while exploration subagents only need speed. The reviewer on a
different model family than the implementer catches more.

Steps:
1. Ask the user to open the model picker (or "Manage Models") and copy the exact names available in their organization,
   with their premium-request multipliers if shown.
2. Fill `.github/kit/config.json`: `models.mode = "tiered"`, `models.tiers.reasoning|balanced|fast` = ordered lists
   (first = preferred, next = fallback). The VS Code format is `Model name (vendor)`, e.g. `Claude Sonnet 4.5 (copilot)`.
3. `pwsh -NoProfile -File .github/skills/bootstrap/scripts/configure-kit.ps1 -ApplyModels`
4. Check: select each agent in the chat; the picker shows its model. If a name is wrong, the agent falls back to the
   picker model; fix the name and re-run.

## Max quality (when the premium budget allows)
The creator of Claude Code uses the strongest model (Opus class, extended thinking) for all coding: slower per answer,
faster overall because it needs less steering. Same here: `models.mode = "tiered"` with the strongest model in both
`reasoning` and `balanced`, a fast model for `researcher` only, then `-ApplyModels`. Watch the premium-request usage for
a week; drop `balanced` back to the Sonnet class if the budget does not follow.

## Cost hygiene (whatever the strategy)
- One task per session; a new session per spec phase (the spec files carry the context).
- Researcher subagents for broad reading; compact script outputs (dotnet-check, discovery, git-context).
- The quality gate only runs when code changed and caches results; `qualityGate.maxBlocks` caps extra turns.
- Use VS Code's model comparison on a few eval scenarios (docs/ai/evals) before changing a tier.
