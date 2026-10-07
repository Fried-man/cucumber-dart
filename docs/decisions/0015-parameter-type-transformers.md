# ADR-0015: Parameter type transformers checked at glue load

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.2

## Context

| Implementation | What a transformer gets |
|---|---|
| cucumber-js | Runs with `this` bound to the World, and may be async |
| cucumber-ruby | Runs in the World |
| cucumber-jvm | Context-free, synchronous methods |

In the vendored expressions library, a transformer is a synchronous `T Function(List<String?>)` with no context.

## Decision

- **Shape.** `ParameterType<T>(name, regexp, Function transformer, ...)`. The transformer is checked when glue loads,
  using the same rules as step bodies:
  - one `String?` parameter per capture group, or a single `String` when there are no groups;
  - optionally preceded by the World;
  - returning `FutureOr<T>`, which is awaited before the step runs.
- **Who calls the transformer.** The runner registers each parameter type with the expressions library using an
  identity transform, which returns the group values. The runner then calls the user's transformer itself, with the
  context available.

## Consequences

- Transformers can look things up in the World and can be async, matching cucumber-js and cucumber-ruby.
- The expressions library API stays unchanged for this purpose.
