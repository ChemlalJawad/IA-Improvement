---
name: 'Spec files'
description: 'How to write spec.md, plan.md and tasks.md in specs/ (spec-driven development).'
applyTo: 'specs/**/*.md'
---
# Spec files

- `spec.md` = WHAT and WHY (no implementation). `plan.md` = HOW, grounded in code paths. `tasks.md` = ordered, verifiable steps. Never mix them.
- Keep the YAML front matter and `status:` current: draft, approved, in-progress, done, cancelled.
- Acceptance criteria `AC-n` are testable (Given / When / Then). Business rules `BR-n` use glossary terms.
- Unknowns are written `[NEEDS CLARIFICATION: question]`; never invent an answer.
- In `tasks.md`, tick tasks as they complete and append one progress-log line per session: date - done - checks - next.
- Be concise: agents re-read these files in every phase.
