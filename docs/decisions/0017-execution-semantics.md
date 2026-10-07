# ADR-0017: Execution semantics

- **Status:** Proposed
- **Date:** 2026-10-06
- **Design:** §5

## Context

The CCK reference implementation (fake-cucumber) and current cucumber-js, cucumber-jvm and cucumber-ruby define the
behaviour that users and tools rely on. These implementations disagree on some details:

| Topic | Who differs |
|---|---|
| Strict mode | cucumber-js still has `--no-strict`; cucumber-jvm and cucumber-ruby's main branch removed it |
| Dry run | Exit status on undefined steps differs between implementations |
| When `testCase` messages are emitted | cucumber-ruby emits each one just before it runs; the others emit them all up front |

## Decision (proposed)

- **Status and composition.**
  - Status severity is `UNKNOWN < PASSED < SKIPPED < PENDING < UNDEFINED < AMBIGUOUS < FAILED`.
  - A test case's status is the worst status of its steps, hook steps included.
- **Step rules** follow fake-cucumber exactly (design §5.3), including:
  - no suggestions after an explicit skip;
  - undefined and ambiguous steps reported even after a failure;
  - `After` hooks always run.
- **Run hooks.**
  - All `BeforeAll` hooks run even if one fails.
  - If any `BeforeAll` failed, no test case runs.
  - `AfterAll` hooks run in descending order, and all of them run.
- **Retry.** Only FAILED test cases are retried. Each attempt gets a fresh World.
- **Strict only.** PENDING, UNDEFINED, AMBIGUOUS and FAILED fail the run; SKIPPED passes. There is no non-strict
  mode.
- **Dry run.**
  - No user code runs.
  - Hooks and defined steps are SKIPPED.
  - The run fails on undefined or ambiguous steps (cucumber-jvm and cucumber-ruby behaviour).
- **Lazy `testCase` emission.** Each `testCase` is emitted just before its first `testCaseStarted`. This keeps
  reports consistent when `package:test` filters out tests.

## Consequences

- Behaviour matches the CCK and the direction the official implementations are moving in.
- Dry runs work as a "are all steps defined?" check in CI.
