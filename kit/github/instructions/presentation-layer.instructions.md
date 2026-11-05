---
name: 'Presentation layer (API / host)'
description: 'Rules for API endpoints and hosts: thin adapters to the application layer, ProblemDetails errors, versioned contracts, explicit authorization.'
applyTo: '**/*.Api/**/*.cs,**/*.WebApi/**/*.cs,**/*.Host/**/*.cs,**/*.Functions/**/*.cs,**/*.Worker/**/*.cs'
---
# Presentation layer rules

Thin adapters between HTTP (or triggers, messages) and the application layer.

- An endpoint only binds and validates the request, sends a command or query, and maps the result to HTTP. No business logic, no EF Core access.
- Follow the solution's endpoint style (minimal APIs or controllers, see `docs/ai/project-context.md`): grouping, naming, tags and OpenAPI metadata like the golden example.
- Errors are RFC 7807 ProblemDetails through the existing error handling. Never leak exception messages or stack traces.
- Request and response DTOs are stable, versioned contracts. Never expose domain entities. A breaking change needs a new version.
- Every endpoint has an explicit authorization policy (or a justified `AllowAnonymous`). Validate all input; no sensitive data in URLs or query strings.
- Correlation ids, logging and telemetry come from the existing middleware; no personal data in logs.
- `Program.cs` only wires things: call each layer's DI extension method.

## Project-specific
<!-- kit:project-specific - endpoint style, versioning scheme, authorization policies, OpenAPI conventions -->
