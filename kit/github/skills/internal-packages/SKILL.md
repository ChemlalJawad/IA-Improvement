---
name: internal-packages
description: Look up and correctly use company-internal NuGet packages from the intranet feed (public API, conventions, real usages in this solution). Use when code references an internal namespace or type you do not know, before writing infrastructure or cross-cutting code an internal package may already provide, or after an internal package upgrade.
---
# Internal packages

Internal packages are invisible to public documentation and to model training data. Never guess their API.

## Lookup order (stop at the first sufficient answer)
1. `docs/ai/internal-packages.md`: index (purpose, version, who uses it, digest link).
2. `docs/ai/packages/<PackageId>.md`: digest with the most used types, real usage lines in this solution, public API, and curated "Notes for agents".
3. Existing usages: search the solution for the type or namespace and mirror the most recent, idiomatic usage.
4. Regenerate or create a digest from the local NuGet cache (works offline after `dotnet restore`):
   ```
   pwsh -NoProfile -File .github/skills/internal-packages/scripts/inspect-package.ps1 -PackageId <Id>
   ```
   `-ListOnly` shows every package with its origin (internal / unknown / public); `-AllInternal` refreshes all digests.
   With PowerShell 7 the digest lists the full public API (assembly metadata); with Windows PowerShell 5.1 it relies on the XML documentation.
5. The company MCP server, if it exposes internal documentation.
6. Ask the user. Then write the answer into the digest's "Notes for agents" section so nobody has to ask again.

## Rules
- Prefer an internal package over a new third-party library or hand-written plumbing for the same concern.
- Respect the versions managed centrally (Directory.Packages.props). An upgrade is a decision: ask, read the release notes, run all tests.
- Never edit nuget.config, add feeds or store credentials (the guard asks or blocks).
- When you learn a non-obvious rule (lifetime, required configuration, pitfall, preferred overload), add one line to the digest's "Notes for agents" section; it survives regeneration.
- If the digest is wrong or outdated (version differs from the solution), regenerate it before relying on it.
