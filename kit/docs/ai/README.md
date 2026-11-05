# docs/ai - context for AI agents

Agents load these files on demand (AGENTS.md links to them), so they must stay short, factual and current.

| File | Content | Written by | Budget |
|---|---|---|---|
| `project-context.md` | Solution map, layers, conventions with golden examples, commands, CI parity, tools | `/bootstrap`, then humans and `/retro` | <= 250 lines |
| `glossary.md` | Ubiquitous language FR / NL / EN mapped to code names | `/bootstrap` seeds, the team completes | as needed |
| `internal-packages.md` | Index of the company packages (intranet feed) | `inspect-package.ps1` (table) + humans | table only |
| `packages/<Id>.md` | Digest per internal package: API, usages, notes for agents | `inspect-package.ps1`; only "Notes for agents" is hand-written | generated |
| `learnings.md` | Log of lessons and where they were encoded | `/retro` | prune after 6 months |
| `evals/scenarios.md` | Regression scenarios to check the kit after changes | `/retro`, humans | 10-30 scenarios |

Rules
- Facts only, each backed by a file path or a person. No speculative guidance.
- Prefer pointing to a golden example file over pasting code.
- When code and these docs disagree, the code wins: fix the doc (or run `/bootstrap refresh`).
- Machine-local data (discovery output, hook logs, test results) lives in `.ai-local/`, which is never committed.
