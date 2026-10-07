# ADR-0001: Runner-agnostic core with `package:test` as the primary host

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §3, §6

## Context

The reference implementations host test execution in different ways:

| Implementation | How it runs |
|---|---|
| cucumber-js, cucumber-ruby | Their own CLI |
| cucumber-jvm | Its JUnit Platform engine is the strategic runner; a CLI also exists. Both share `CucumberExecutionContext`. |
| godog | Started as a CLI that hijacked `go test` builds. The CLI was deprecated in favour of plain `go test` with each scenario as a subtest. The maintainers' reason was that keeping parity with the toolchain (debugger, coverage, build tags) was not feasible. |

In Dart, `package:test` provides a lot for free:

- IDE run and debug
- coverage, sharding and tags
- `TestLocation` for navigation
- CI reporters

Flutter widget tests can only run under `flutter test`.

## Decision

- **`cucumber_core` is runner-agnostic.** It produces a `SuitePlan`, which a `TestHost` declares, and it runs test
  cases on request. A `SerialHost` runs plans directly; it is used by the CCK harness and a future CLI.
- **`package:cucumber` provides the primary host, built on `package:test`:**
  - Features, rules, outlines and examples become `group`s.
  - Each pickle becomes a `test`.
  - `BeforeAll`/`AfterAll` and run-level messages go in the root `setUpAll`/`tearDownAll`.
- **Cucumber reports are written to files.**
- **A CLI may come later,** but only as a thin facade over `dart test`, following godog's lesson.

## Consequences

**Benefits:**
- IDE support, debugger, coverage, sharding and CI integration come without extra work.
- `flutter_test` will follow the same model.

**Costs:**
- The `dart test` reporter owns the console. Cucumber prints a summary when the suite ends (ADR-0009).
- There is no parallelism inside a file, only across files/isolates. That needs report merging (ADR-0016).
- We cannot add command-line flags. Configuration comes from code, YAML and the environment (ADR-0010).

## Alternatives considered

- **Standalone CLI first.** Full control, but no IDE test tree, and Flutter widget tests would be impossible.
- **CLI and `package:test` host both in v1.** Too much surface to build and maintain before 1.0.
