---
spec: "{{ID}}"
title: "{{TITLE_YAML}}"
status: draft
created: {{DATE}}
---

# Tasks {{ID}} - {{TITLE}}

Rules: one task = one small verifiable step (about one commit). Tests first. `[P]` = can run in parallel (disjoint files).
Tick the box and add a progress-log line as you go: a fresh session must be able to resume from this file alone.
Status values: draft | in-progress | done

## Phase 1 - Domain
- [ ] T001 [AC-1] Failing unit test for <behavior> (`tests/...`) - verify: `dotnet-check.ps1 -Test -Filter "FullyQualifiedName~..."`
- [ ] T002 [AC-1] Implement <behavior> in the aggregate (`src/...`) - verify: test green

## Phase 2 - Application
- [ ] T003 [AC-1] ...

## Phase 3 - Infrastructure
- [ ] T004 ...

## Phase 4 - API
- [ ] T005 ...

## Checkpoint
- [ ] Build + affected tests green (`dotnet-check.ps1`)
- [ ] Code review done (`/code-review`), Blocker and Major findings fixed
- [ ] Spec status set to done

## Progress log
<!-- One line per working session: date - what was done - checks result - next step or blocker. -->
- {{DATE}} - task list created
