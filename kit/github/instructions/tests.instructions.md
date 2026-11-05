---
name: 'Test rules'
description: 'How to write unit and integration tests in this solution: behavior-focused, deterministic, synthetic data, never weakened to get green.'
applyTo: '**/*Test*/**/*.cs,**/tests/**/*.cs'
---
# Test rules

- One behavior per test. Follow the naming convention of the existing tests (default `Method_Scenario_ExpectedResult`). Arrange / Act / Assert, visually separated.
- Test behavior through public APIs, not implementation details. Do not test private methods.
- Domain tests are pure unit tests: build aggregates through their factories or the test data builders; no mocks needed.
- Mock only your own abstractions at architectural boundaries (repositories, gateways, clock). Never mock the DbContext: use the integration test fixture.
- Deterministic tests: no `DateTime.Now`, unseeded `Random`, real network or `Thread.Sleep`. Use the fake clock and fixed data.
- Synthetic data only. Never real names, national register numbers, IBANs or addresses; use builders with obviously fake values.
- A failing test is information: never delete it, skip it or weaken its assertion to get green. If the expected behavior changed, ask first.
- Every bug fix comes with a regression test that fails before the fix.
- Integration tests reuse the existing fixture (WebApplicationFactory, Testcontainers...) and isolate or clean their data.
- Each acceptance criterion `AC-n` of a spec maps to at least one test; mention the AC in the test name or a short comment.

## Project-specific
<!-- kit:project-specific - framework (xUnit / NUnit / MSTest), assertion and mocking libraries, fixtures,
     traits/categories used by qualityGate.testFilter, test project naming -->
