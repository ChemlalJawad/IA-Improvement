# Specs (spec-driven development)

Every change bigger than a small fix goes through four short artifacts. They are the agents' long-term memory:
a fresh session can resume any feature from its folder alone, so you never have to re-explain anything.

| Phase | File | Answers | Skill (slash command) | Agent | Gate |
|---|---|---|---|---|---|
| 1. Specify | `spec.md` | WHAT and WHY: problem, scope, testable acceptance criteria | `/spec` | Planner | You approve the spec |
| 2. Plan | `plan.md` + `tasks.md` | HOW: design per layer, risks, test strategy, ordered tasks | `/spec-plan` | Planner | You approve the plan |
| 3. Implement | code + `tasks.md` progress | Tasks one by one, tests first, checks after each task | `/spec-implement` | Implementer | Quality gate (hooks) |
| 4. Review | review report | Correctness vs acceptance criteria, architecture, security, tests | `/code-review` | Reviewer | Blockers fixed, then PR |

The Conductor agent can drive all four phases with subagents and stops at both approval gates.

## Conventions
- Folder: `specs/NNN-short-slug/` (created by `/spec`, numbering is automatic).
- Each file starts with YAML front matter. `status:` drives the session-start reminder:
  `draft` -> `approved` -> `in-progress` -> `done` (or `cancelled`).
- Acceptance criteria are numbered `AC-n`, business rules `BR-n`, tasks `Tnnn`. Tasks and tests reference them.
- Unknowns are marked `[NEEDS CLARIFICATION: ...]` and must be resolved before approval.
- `tasks.md` ends with a progress log: one line per working session (what was done, checks, next step).
- Start a new chat session for each phase: the files carry the context, not the conversation.

## When to skip
Typo, one-line fix, dependency bump, pure refactor covered by tests: no spec. Use the Implementer directly
(or the Debugger for a bug) and keep the same verification discipline.

Templates live in `specs/_templates/`. Adapt them to your team once, not per feature.
