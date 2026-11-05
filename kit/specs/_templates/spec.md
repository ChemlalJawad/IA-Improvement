---
id: "{{ID}}"
title: "{{TITLE_YAML}}"
status: draft
workItem: "{{WORKITEM}}"
created: {{DATE}}
owner: ""
---

# {{ID}} - {{TITLE}}

> WHAT and WHY only: no implementation details (they belong in plan.md).
> Mark every unknown with `[NEEDS CLARIFICATION: question]` and resolve it before approval.
> Status values: draft | approved | in-progress | done | cancelled

## Problem and context
Why is this needed? Who is affected? What happens today?

## Goals
- 

## Non-goals (out of scope)
- 

## Users and actors
- 

## User stories
- As a <role>, I want <capability> so that <benefit>.

## Acceptance criteria
Each criterion is observable and testable; each becomes at least one automated test.
- **AC-1** Given <context>, when <action>, then <observable outcome>.
- **AC-2** 

## Business rules and invariants
Use the glossary terms (docs/ai/glossary.md).
- **BR-1** 

## Data and privacy
- Data read or written (entities, fields):
- Personal data involved? GDPR category, retention, masking in logs:
- Authorization (who may do what):

## Non-functional requirements
- Performance (measurable, e.g. p95 < 300 ms at N req/s):
- Observability (logs, metrics, alerts):
- Resilience / availability:

## Dependencies and impacts
- Other teams, services, internal packages, API or message contracts:

## Open questions
- [NEEDS CLARIFICATION: ...]

## Approval checklist
- [ ] Every acceptance criterion is testable and agreed
- [ ] Out of scope is explicit
- [ ] Privacy and authorization reviewed
- [ ] No open `NEEDS CLARIFICATION` left
