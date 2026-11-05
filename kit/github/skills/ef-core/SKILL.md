---
name: ef-core
description: Work safely with Entity Framework Core - entity configurations, migrations (add, review SQL, resolve snapshot conflicts), query performance (tracking, projections, N+1, split queries) and the data access conventions of this solution. Use when changing persistence, adding a migration, resolving a migration conflict or investigating a slow query.
---
# EF Core

Project specifics (DbContext, migrations project, startup project) are in `docs/ai/project-context.md`.

## Mapping
- Fluent configuration in `IEntityTypeConfiguration<T>` classes next to the existing ones; no attributes on domain types.
- Value objects as owned types or value converters, following the existing pattern. Strongly typed ids with converters.
- Concurrency tokens where the existing aggregates use them.

## Migrations
1. Change the model, build.
2. Tools: `dotnet tool restore` (if the repo has a tool manifest), then
   `dotnet ef migrations add <PascalCaseName> --project <MigrationsProject> --startup-project <StartupProject>`.
3. Review the generated migration AND the SQL: `dotnet ef migrations script <PreviousMigration> <NewMigration> --idempotent --project ... --startup-project ...`.
   Look for data loss (drop or alter column), missing indexes for new queries, defaults for new non-nullable columns, long locks on big tables.
4. Backward compatible with the running version (expand / contract): add first, remove in a later release.
5. Never edit a migration that may have been applied anywhere; add a new one. Never hand-edit `*.Designer.cs` or the model snapshot.
6. `dotnet ef database update` only against a local database, never a shared environment (the guard asks for confirmation).

## Snapshot conflict after a merge or rebase
1. Keep the target branch's migrations and model snapshot (take their version of the snapshot).
2. Remove your own migration files (or `dotnet ef migrations remove` if it was the last one and not applied elsewhere).
3. Re-run `dotnet ef migrations add <SameName>` on top: the new migration and snapshot now include both changes.
4. Build, run the persistence tests, review the SQL again.

## Queries
- Reads: `AsNoTracking()`, `Select` projection to the DTO, pagination for lists, `CancellationToken` everywhere.
- Avoid N+1: no repository or lazy-load calls inside loops; `Include` deliberately, `AsSplitQuery()` for large graphs.
- Filters translate to SQL: no client-side evaluation on large sets; check the generated SQL (`ToQueryString()`) when unsure.
- Bulk changes: `ExecuteUpdateAsync` / `ExecuteDeleteAsync` when the existing code base uses them and domain events are not needed.
- Never build SQL by string interpolation: `FromSql($"...")` parameterizes, `FromSqlRaw` with user input does not.
