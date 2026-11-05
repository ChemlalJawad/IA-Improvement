---
name: 'Infrastructure layer'
description: 'Rules for adapters in the Infrastructure layer: EF Core configuration and queries, migrations, HTTP clients, options, secrets, internal packages.'
applyTo: '**/*.Infrastructure*/**/*.cs,**/*.Persistence*/**/*.cs,**/Infrastructure/**/*.cs'
---
# Infrastructure layer rules

Adapters for persistence, messaging and external services. No business rules here.

- Implement the ports declared in Application or Domain and register them in this layer's DI extension method, like the existing ones.
- EF Core mapping uses `IEntityTypeConfiguration<T>` (Fluent API); the domain never carries persistence attributes. The DbContext holds no business logic.
- Migrations are generated with `dotnet ef migrations add`, reviewed through the SQL script, and never edited once applied anywhere (ef-core skill).
- Reads: `AsNoTracking()`, project with `Select` to what is needed, avoid N+1 (deliberate `Include` or split queries), always pass the `CancellationToken`.
- HTTP: typed clients through `IHttpClientFactory` with the standard resilience pipeline and explicit timeouts; never `new HttpClient()`.
- Configuration through the options pattern, validated at startup. Secrets come from Key Vault or user-secrets, never from committed files.
- Cross-cutting concerns (messaging, logging, auth, storage...) use the internal packages as documented in `docs/ai/packages/`.
- Translate infrastructure exceptions into the solution's errors at the boundary; log context, never personal data.

## Project-specific
<!-- kit:project-specific - DbContext, migrations project + startup project for dotnet ef, messaging package,
     resilience setup, caching -->
