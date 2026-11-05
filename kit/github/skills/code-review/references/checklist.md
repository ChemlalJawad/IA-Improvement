# Review checklist (.NET, Clean Architecture, DDD, insurance context)

## Intent
- Each acceptance criterion (AC-n) is implemented and covered by a test; business rules (BR-n) live in the domain.
- No unrequested behavior, no scope creep, no leftover debug code.

## Architecture and DDD
- Dependencies point inward; no new project reference or package outside the rules (or an ADR exists).
- Aggregates guard their invariants (no public setters on state, intention-revealing methods, validation inside).
- Value objects immutable; aggregates reference each other by id; one aggregate changed per transaction.
- Handlers orchestrate only; endpoints only map HTTP to commands/queries; no domain entity in API contracts.
- Names follow the glossary; the code reads like the business rule.

## Security
- Every endpoint has an explicit authorization policy; resource-level checks where data belongs to a customer or broker.
- All input validated; no SQL built by concatenation; no `FromSqlRaw` with interpolated user input (use parameters / `FromSql`).
- No secrets in code, configuration, tests or logs; secrets from Key Vault / user-secrets.
- Errors return ProblemDetails without stack traces or internal details.
- No new external call without timeout and resilience; no TLS or certificate validation bypass.

## Privacy (GDPR)
- No personal data (names, national register numbers, IBAN, addresses, health data, claim descriptions) in logs, traces, exception messages or test data.
- Data minimization: only the fields needed are read, returned and stored; retention respected.
- Personal data exposed by an endpoint is intended and authorized.

## Data access (EF Core)
- Read queries: `AsNoTracking`, projection with `Select`, no N+1 (check loops calling the repository), pagination for lists.
- `CancellationToken` passed to every async EF call.
- Migrations generated (not hand-written), SQL reviewed, backward compatible with the running version (expand / contract),
  no data loss, indexes for new query patterns.
- No `SaveChanges` inside loops; transactions explicit when several aggregates must be consistent (or eventual consistency by events).

## Reliability and performance
- No sync-over-async (`.Result`, `.Wait()`), no `async void`; exceptions not swallowed.
- Resources disposed (`await using`); `HttpClient` from the factory; no static mutable state.
- Hot paths: no needless allocations, LINQ in tight loops, or reflection; caching only with invalidation strategy.
- Idempotency for message handlers and retried operations.

## Tests
- Tests fail for the right reason before the fix; assertions check behavior, not implementation.
- Deterministic (clock abstraction, no real network, no sleeps); synthetic data.
- Integration tests isolate their data; no order dependency between tests.
- Regression test for every bug fix.

## Operability
- Logs are structured, actionable, at the right level; correlation id flows.
- Configuration documented (new settings in appsettings + project-context.md); feature flags have an owner and removal plan.
- Pipeline impact understood (new step, new secret, new environment).
