---
name: spec-plan
description: Turn an approved spec into a technical plan (plan.md) and an ordered, verifiable task list (tasks.md) that respects the Clean Architecture layers, the project's golden examples and the internal packages. Use after a spec is approved or when asked to plan an implementation.
argument-hint: "<specs/NNN-slug>"
---
# Spec plan: HOW, then tasks

## Steps
1. **Read** `spec.md` (must be `approved`; otherwise go back to the `spec` skill), `docs/ai/project-context.md` and the instructions of the layers involved.
2. **Research in parallel** with `researcher` subagents: the code paths that change, the closest existing feature (it gives the golden examples to mirror), the internal packages involved (their digests), the tests that exist.
3. **Create the files**:
   ```
   pwsh -NoProfile -File .github/skills/spec/scripts/new-spec.ps1 -Spec <NNN> -AddPlan
   ```
4. **Write plan.md**: design per layer (Domain, Application, Infrastructure, Presentation, cross-cutting), data and migrations, test strategy (table AC/BR -> test level -> test name), risks, alternatives (architectural choice -> ADR draft in `docs/adr/`), and the constitution check against AGENTS.md. Cite real file paths.
5. **Write tasks.md**:
   - phases follow the dependency direction (Domain -> Application -> Infrastructure -> API), tests first in each slice;
   - each task: id `Tnnn`, the `AC-n` it serves, the files, a verify command; small enough for one commit;
   - mark `[P]` only for tasks touching disjoint files; end with the checkpoint (build + tests + review).
6. **Self-review** with a `reviewer` subagent: "critique this plan for gaps against the ACs, risks, missing tests, over-engineering". Fix real issues.
7. **Approval**: present the plan summary and the task list briefly; set `status: approved` (plan) after agreement and `status: in-progress` (tasks) when implementation starts.
8. **Next**: recommend `/spec-implement specs/NNN-slug` in a NEW session, or the conductor agent for an autonomous run.

## Rules
- The simplest design that satisfies every AC; no speculative abstractions, no new library without approval.
- Every AC is covered by at least one test in the strategy; every task has a way to verify it.
- Respect the layer rules; an exception needs an ADR before the plan is approved.
