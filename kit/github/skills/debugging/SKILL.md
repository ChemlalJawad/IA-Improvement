---
name: debugging
description: Systematic debugging of failing tests, exceptions, wrong behavior, performance problems or flaky builds - reproduce first (ideally as a failing test), form and test hypotheses with evidence, fix the root cause, add a regression test. Use when something is broken and the cause is not obvious.
---
# Debugging

## Protocol
1. **Reproduce.** Turn the report into a failing automated test whenever possible (unit test for domain logic, integration test for persistence or API). Run it with `dotnet-check.ps1 -Test -Filter "FullyQualifiedName~<Test>"`. No reproduction, no fix: ask for missing details (input, environment, logs, correlation id).
2. **Read the evidence.** Full exception (inner exceptions included), the first stack frame in our code, recent changes (`git log -p -- <file>`), logs around the correlation id.
3. **Hypothesize.** Write two or three candidate causes. Pick the cheapest experiment that discriminates between them (a focused assertion, a temporary log line, a smaller input).
4. **Fix the root cause**, in the right layer (a domain rule bug is fixed in the domain, not patched in the endpoint).
5. **Prove it.** The reproduction test now passes; the affected tests stay green (`dotnet-check.ps1`). Remove temporary logging.
6. **Explain** in five lines: symptom, root cause (with evidence), fix, regression test, risk of side effects.

## Specific cases
- **Flaky test**: run it in a loop or in isolation; look for shared state, time (`DateTime.Now`), ordering, async without await, external dependencies. Fix the cause; never add retries or longer timeouts to hide it.
- **Works locally, fails in the pipeline**: compare configuration (Release vs Debug), culture and time zone, environment variables, file paths, SDK version (global.json). Hand over to the devops agent if it is pipeline-specific.
- **Performance**: measure before changing anything (stopwatch around the suspect, EF `ToQueryString()` and query logs, `dotnet-counters`, BenchmarkDotNet for hot code). Fix the biggest measured cost first, then measure again.
- **Internal package misbehaving**: read its digest and real usages (`internal-packages` skill) before assuming a bug in the package.

## Never
Shotgun edits, catch-all try/catch, weakening assertions, commenting out the failing test, "fixing" by changing expected values you do not understand.
