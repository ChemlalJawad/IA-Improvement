---
name: clean-architecture
description: Implement a use case or feature slice end-to-end in this Clean Architecture solution - domain model, application command or query with validation, infrastructure persistence or adapter, API endpoint, dependency injection and tests - following the project's conventions and golden examples. Use when adding or changing a feature that spans several layers.
---
# Clean Architecture feature slice

The project-specific shape of each piece is in `docs/ai/project-context.md` (golden examples). This skill gives the order and the checks.

## Dependency rule
Domain <- Application <- Infrastructure and Presentation. Inner layers never reference outer ones; the guard and the
quality gate enforce the rules of `.github/kit/config.json`. Need an exception? Write an ADR first.

## Recipe (inside-out, tests first)
1. **Domain**: behavior on the aggregate (method + invariant), value objects, domain event if others react. Unit tests first. (`ddd-modeling` skill)
2. **Application**: command or query + handler + validator, shaped exactly like the golden example. Ports (interfaces) for what the handler needs from outside. Handler tests with fakes of your own ports.
3. **Infrastructure**: implement the ports (repository, gateway, message publisher) with the internal packages where they apply; EF configuration and migration if the model changed (`ef-core` skill); register in the layer's DI extension.
4. **Presentation**: endpoint (minimal API or controller, as the solution does), request/response contracts, authorization policy, ProblemDetails mapping, OpenAPI metadata.
5. **Integration test** through the existing fixture for the happy path and the main failure.
6. **Verify**: `dotnet-check.ps1 -Architecture` (build, affected tests, layer rules).

## Checks before saying done
- [ ] The business rule lives in the domain, not in the handler or endpoint.
- [ ] Every new type mirrors its golden example (naming, folder, base class, registration).
- [ ] Validation at the boundary; errors use the solution's result/error type and map to ProblemDetails.
- [ ] `CancellationToken` flows from the endpoint to the database call.
- [ ] No domain entity leaves the application layer; DTOs are versioned contracts.
- [ ] Logs carry ids, never personal data.
- [ ] Each acceptance criterion has a test.

## Common mistakes
- Anemic domain: setters on aggregates and rules in handlers.
- Handler doing infrastructure work (raw SQL, HTTP calls) instead of using a port.
- New abstraction "for later": add it when a second use appears.
- Forgetting DI registration, or registering with the wrong lifetime (copy the golden example).
