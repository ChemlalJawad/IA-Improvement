---
name: ddd-modeling
description: Model the domain with DDD tactical patterns - aggregate boundaries and invariants, entities, value objects and strongly typed ids, domain events, domain services and repositories per aggregate - using the ubiquitous language of docs/ai/glossary.md. Use when creating or changing domain types or business rules.
---
# DDD modeling

## Before coding
- Name things with the glossary (`docs/ai/glossary.md`). A missing term is a question for the user, not an invention.
- Find the aggregate that owns the rule: which object must stay consistent in one transaction?

## Heuristics
- **Aggregate** = consistency boundary. Small. One root; outside code holds the root only and references other aggregates by id.
- **Invariants** are enforced inside the aggregate on every state change: constructor or factory validates creation, intention-revealing methods validate transitions (`claim.Approve(assessment)` instead of `claim.Status = Approved`).
- **Value objects** for concepts defined by their values (amount + currency, period, address, policy number): immutable, validated on creation, equality by value.
- **Strongly typed ids** when the solution uses them: no mixing of `Guid`s across aggregates.
- **Domain events** for facts in past tense (`ClaimApproved`) raised by the aggregate; handlers in the application layer react (notifications, other aggregates, integration events).
- **Domain service** only when a rule spans several aggregates and belongs to none.
- **Repositories** per aggregate root, defined as ports; they load and save whole aggregates.
- No persistence, HTTP, logging or time-of-day calls inside the domain (inject the clock through method parameters or the solution's abstraction).

## Example of intent (insurance flavor)
- Business rule BR-1 "a suspended policy cannot get new coverage" becomes:
  `policy.AddCoverage(coverage)` checks the status and returns or throws the solution's domain error; a unit test covers both paths.

## Tests
Pure unit tests per rule: valid transition, each invalid transition, boundary values. Build objects through factories or test data builders, never by setting private state.

## Smells
Public setters on aggregate state; validation duplicated in handlers; huge aggregates loaded for one field; domain types named after tables; `Manager` / `Helper` classes holding business rules.
