---
name: 'C# rules'
description: 'C# coding rules for this solution (nullability, async, errors, logging without personal data, immutability). Applies to every .cs file.'
applyTo: '**/*.cs'
---
# C# rules

Analyzers and `.editorconfig` already enforce formatting and most style: do not restate or fight them.

- Nullable reference types are on. Do not silence warnings with `!`; model absence explicitly (nullable type, Try pattern, result type).
- Async all the way: no `.Result`, `.Wait()` or `async void` (except event handlers). Accept and forward a `CancellationToken` through every async call chain.
- Expected business failures use the solution's error/result type (see `docs/ai/project-context.md`). Exceptions are for the unexpected. Never swallow an exception; no `catch (Exception)` without rethrow or a documented reason.
- Logging uses message templates, never interpolation, and never personal data or secrets:
  - Good: `logger.LogInformation("Claim {ClaimId} registered", claimId);`
  - Bad: `logger.LogInformation($"Claim {claimId} registered for {insured.Name}");`
- Prefer immutability: `record` for DTOs and messages, `init` setters, `IReadOnlyList<T>` / `IReadOnlyCollection<T>` in public signatures.
- New classes are `sealed` unless designed for inheritance.
- Time comes from `TimeProvider` (or the solution's clock abstraction), never `DateTime.Now`; store UTC.
- Names come from the ubiquitous language (`docs/ai/glossary.md`); the code must read like the business rule.
- Small, intention-revealing methods. No dead code, no commented-out code, no TODO without a work item.
- Comments explain why, not what. Public APIs of shared libraries get XML doc comments.

## Project-specific
<!-- kit:project-specific - filled by /bootstrap from the golden examples (3-8 bullets): namespaces, primary constructors,
     result type, mapping approach, guard clauses library, collection expressions... -->
