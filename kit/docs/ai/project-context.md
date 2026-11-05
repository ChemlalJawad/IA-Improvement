# Project context

<!-- kit:status=template - /bootstrap replaces this template with facts discovered in the repository.
     Budget: <= 250 lines. Facts only, each backed by a file path. No code dumps: point to golden examples. -->

## Purpose
{{What the service does, its main users, its bounded context(s) and the upstream/downstream systems.}}

## Solution map
| Layer | Project | Path | Responsibility |
|---|---|---|---|
| Domain | | | |
| Application | | | |
| Infrastructure | | | |
| Presentation | | | |
| Tests | | | |

Dependency rule (mirrors `architecture.layers` in `.github/kit/config.json`): {{in words}}

## Conventions and golden examples
Read the example before writing the same kind of code. "Convention" is one line; the example shows the details.

| Pattern | Convention | Golden example |
|---|---|---|
| Aggregate / entity | | |
| Value object / strongly typed id | | |
| Domain event | | |
| Command + handler | | |
| Query + handler | | |
| Validation | | |
| Errors / result type | | |
| Repository / persistence | | |
| EF Core configuration | | |
| API endpoint | | |
| DI registration | | |
| Logging / telemetry | | |
| Unit test | | |
| Integration test | | |

## Internal packages
The few that shape the architecture (full list: [internal-packages.md](internal-packages.md)).

## Commands and CI parity
| Purpose | Local command | Pipeline equivalent |
|---|---|---|
| Restore (intranet feed) | | |
| Build | | |
| Tests | | |
| Format / analyzers | | |
| Run locally | | |

## Configuration and environments
{{appsettings layering, user-secrets id, Key Vault, feature flags, environments (dev / test / acc / prod)}}

## Tools and MCP servers
| Need | Use |
|---|---|
| .NET and Azure documentation | `microsoft-learn` MCP server |
| Work items, pull requests, pipelines, build logs | {{company MCP or ado}} |
| Internal documentation, internal package docs | {{company MCP if available}} |

## Known issues and pitfalls
- 
