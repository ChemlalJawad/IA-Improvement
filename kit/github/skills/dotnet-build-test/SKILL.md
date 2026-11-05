---
name: dotnet-build-test
description: Build and test the .NET solution with compact, token-efficient output - deduplicated compiler errors, failed tests with their message and source location - and run only the test projects affected by the current changes. Use whenever you need to verify a change, reproduce a failure or check the build.
---
# Build and test (compact)

Raw `dotnet build` / `dotnet test` output is long and repetitive; it wastes context and hides the signal.
`dotnet-check.ps1` runs the same commands and returns only what matters.

## Commands
```
pwsh -NoProfile -File .github/skills/dotnet-build-test/scripts/dotnet-check.ps1
```
Default: build the solution, then run the test projects affected by the uncommitted changes (projects owning the changed files plus every project that references them).

| Need | Arguments |
|---|---|
| Build only | `-Build` |
| Tests only (builds what it needs) | `-Test` |
| All test projects | `-Test -Scope all` |
| One test or class | `-Test -Filter "FullyQualifiedName~OrderTests"` |
| Affected since the base branch (before a PR) | `-Base origin/develop` |
| Also check the layer rules | `-Architecture` |
| Machine-readable | `-Json` |
| In Azure Pipelines: annotate errors on the run and the PR | `-Ci` (automatic when `TF_BUILD` is set) |

## Reading the output
```
BUILD: FAILED - 2 error(s), 5 warning(s) [12.3s]
  src/Shop.Domain/Order.cs(42,13): CS0246 The type or namespace name 'Money' could not be found
TESTS: FAILED - 1 failed, 56 passed, 57 total in 2 project(s) (affected by current changes) [8.1s]
  x Shop.Domain.Tests.OrderTests.Cannot_add_line_to_closed_order
    Expected exception InvalidOperationException, but no exception was thrown.
    at tests/Shop.Domain.Tests/OrderTests.cs:31
RESULT: FAILED
```
Exit code 0 = everything requested passed.

## End-to-end check (API behavior)
Green tests do not prove an endpoint works. When a change alters API behavior, also exercise it:
1. Start the API in a background terminal on a free local port: `dotnet run --project <Api project> --urls http://localhost:5199`.
2. Call the endpoint (`Invoke-RestMethod`, `curl`, or the project's `.http` file) with synthetic data; check status code and payload.
3. Stop the process. Never call shared or production environments; ask when authentication is needed.

## Rules
- Verify after every meaningful change; quote the summary lines in your report.
- Fix the first compiler error first: later errors are often consequences.
- Do not introduce new warnings. If warnings are errors in this solution, treat them as errors.
- A test that fails once and passes on re-run is flaky: report it (test name, symptom), do not hide it.
- Integration tests that need infrastructure (database, containers) may be filtered by `qualityGate.testFilter`; run them explicitly when your change touches persistence.
- Use the raw `dotnet` commands only when you need something the script does not provide (e.g. `dotnet ef`, `dotnet run`).
