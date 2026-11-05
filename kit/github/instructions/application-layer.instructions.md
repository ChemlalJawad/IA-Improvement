---
name: 'Application layer'
description: 'Rules for use cases in the Application layer: one command or query per handler, validation at the boundary, thin orchestration, ports for infrastructure.'
applyTo: '**/*.Application/**/*.cs,**/Application/**/*.cs'
---
# Application layer rules

The application layer orchestrates use cases. Business rules live in the domain; technical details live in infrastructure.

- One use case = one command or query and one handler, shaped exactly like the golden example in `docs/ai/project-context.md`. Commands change state and return little; queries never change state.
- Validate input at the boundary with the solution's validation approach before touching the domain.
- Handler flow: load aggregate(s), call domain methods, persist, publish events. If a handler accumulates business conditionals, move them into the domain.
- Depend on abstractions (ports) declared here or in the domain: repositories, gateways, clock. Implementations live in Infrastructure.
- Never return domain entities to the presentation layer: map to DTOs. Queries may use optimized read paths if the solution does.
- Authorization, transactions, logging and validation pipelines already exist: reuse them, do not reimplement per handler.
- Forward the `CancellationToken` everywhere.

## Project-specific
<!-- kit:project-specific - mediator / dispatcher (MediatR, Wolverine, custom or internal package), pipeline behaviors,
     result type, mapping, folder layout (feature folders?) -->
