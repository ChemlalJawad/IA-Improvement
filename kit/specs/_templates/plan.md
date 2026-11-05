---
spec: "{{ID}}"
title: "{{TITLE_YAML}}"
status: draft
created: {{DATE}}
---

# Plan {{ID}} - {{TITLE}}

> HOW, grounded in the current code (cite file paths). The simplest design that satisfies every acceptance criterion.
> Status values: draft | approved

## Summary
Two to four sentences: the approach and the main design decision.

## Current state
What exists today (flows, files, golden examples to mirror), from research.

## Design
### Domain
- Aggregates, entities, value objects, domain events touched; where each invariant (BR-n) is enforced.
### Application
- Use cases (commands / queries), validation, orchestration, transaction boundaries.
### Infrastructure
- Persistence (EF configuration, migration), external adapters, internal packages used (link their digests).
### Presentation / API
- Endpoints, request/response contracts, versioning, authorization, errors (ProblemDetails).
### Cross-cutting
- Logging (no personal data), metrics, configuration, feature flags.

## Data and migrations
- Schema change, migration name, backward compatibility, data backfill, rollback.

## Test strategy
| AC / BR | Level | Test (class.method or file) |
|---|---|---|
| AC-1 | unit (domain) | |

## Risks and mitigations
- 

## Alternatives considered
- Option: why not. An architectural choice deserves an ADR in `docs/adr/`.

## Constitution check (AGENTS.md non-negotiables)
- [ ] Layering respected; no new project reference or package without approval
- [ ] Every AC has a test written first
- [ ] No secrets, no personal data in code, logs or tests
- [ ] Mirrors the golden examples (cited above)
- [ ] Simplest design: nothing speculative
