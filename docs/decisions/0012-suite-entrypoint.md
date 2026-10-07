# ADR-0012: `cucumber()` entrypoint over `CucumberOptions` / `CucumberSuite`

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.8

## Context

Users need a one-line way to declare a suite in a test file. Advanced users also want to reuse and compose a
configuration across several entry files, for example to split features for parallelism.

## Decision

- **`cucumber<W>(...)`** is a function with named arguments. It is a convenience wrapper around
  `CucumberSuite<W>(CucumberOptions(...)).declare()`.
- **`CucumberOptions`** is an immutable value with `merge`.
- **Declaration is synchronous.** It covers parsing, loading glue, filtering, and declaring groups and tests.

## Consequences

- `void main() => cucumber(...)` covers the common case.
- Programmatic users get a composable options value.
- Synchronous declaration avoids the declare-after-`await` failures seen in `flutter_gherkin`.
