---
name: 'Domain layer (DDD)'
description: 'DDD rules for the Domain layer: aggregates protect invariants, value objects, domain events, no infrastructure dependencies, ubiquitous language.'
applyTo: '**/*.Domain/**/*.cs,**/Domain/**/*.cs'
---
# Domain layer rules

The domain is pure C#: no EF Core, ASP.NET Core, HTTP, SQL, Azure SDK, serializer or logging framework. If you need one, the code belongs in another layer (the guard blocks forbidden references and packages).

- Aggregates protect their invariants: private setters, state changes through intention-revealing methods (`policy.Suspend(reason)`), validation inside the aggregate. A caller can never put an aggregate in an invalid state.
- Create through constructors or static factory methods that validate. A private parameterless constructor only if the persistence framework needs it.
- Value objects are immutable and compared by value (record or the solution's base class). Use strongly typed ids if the solution does.
- Reference other aggregates by id, not by object. Keep aggregates small; one transaction changes one aggregate.
- Raise domain events for facts other parts react to (`ClaimRegistered`); the domain never calls infrastructure.
- No async I/O in the domain. Use a domain service only for logic that belongs to no single aggregate.
- Every type and member name comes from the glossary (`docs/ai/glossary.md`). Business rules `BR-n` of a spec map to aggregate methods with unit tests.

## Project-specific
<!-- kit:project-specific - base classes (Entity, AggregateRoot, ValueObject), id types, domain event dispatch,
     error/result type used by the domain, folder organisation (per aggregate?) -->
