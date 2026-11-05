---
name: spec
description: Start spec-driven development for a feature or change - interview the user and write specs/NNN-slug/spec.md with the problem, scope, user stories, testable acceptance criteria, business rules, data and privacy, and open questions. Use when a request is bigger than a small fix, is ambiguous, or touches several layers.
argument-hint: "<feature title or work item id>"
---
# Spec: WHAT and WHY

A good spec is short, testable and free of implementation details. It is the contract the plan, the tests and the review refer to.

## Steps
1. **Gather context** without reading the whole codebase:
   - the work item (company or `ado` MCP tools) if one is referenced;
   - current behavior and related code through a `researcher` subagent (max 200 words, `path:line` evidence);
   - glossary terms (`docs/ai/glossary.md`) so the spec speaks the business language.
2. **Create the file**:
   ```
   pwsh -NoProfile -File .github/skills/spec/scripts/new-spec.ps1 -Title "<title>" -WorkItem "AB#1234"
   ```
3. **Draft** every section of `spec.md`. Write acceptance criteria as `AC-n` Given / When / Then, each observable from outside. Business rules as `BR-n`. Mark unknowns `[NEEDS CLARIFICATION: question]`.
4. **Interview** (one batch, max 5 questions): ask only what changes the spec, each question with a proposed default answer, so the user can reply "ok" or correct. Repeat at most once.
5. **Quality bar** before asking for approval:
   - every AC is testable and independent of the implementation;
   - out of scope is explicit; no `NEEDS CLARIFICATION` left;
   - data and privacy filled (personal data? GDPR? authorization?);
   - non-functional requirements are measurable or explicitly "none".
6. **Approval**: show the AC list and the open points in 10 lines max. Set `status: approved` only after the user agrees.
7. **Next**: recommend `/spec-plan specs/NNN-slug` in a NEW chat session (clean context; the file carries everything).

## Rules
- No class names, endpoints, tables or libraries in spec.md: that is the plan's job.
- Prefer fewer, sharper acceptance criteria over long lists. Three to eight is typical.
- If the request is actually a small fix, say so and skip the spec.
