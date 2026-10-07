# ADR-0003: Typed World as optional first parameter; optional `World` base; top-level attach/log/link

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.3, §4.4, §7.4

## Context

Other implementations share scenario state in different ways:

| Implementation | How scenario state is shared |
|---|---|
| cucumber-js | Binds `this` to a World per attempt |
| cucumber-ruby | Runs blocks in a World extended with modules |
| cucumber-jvm | Uses dependency injection |
| godog | Threads a `context.Context` through steps |

Dart closures can't rebind `this`. Zones give an equivalent of AsyncLocalStorage that survives `await`.

## Decision

- **One World type per suite.**
  - It is created by `world: W Function()` once per test-case attempt, so each retry gets a fresh World.
  - The default is a plain `World`.
- **World as optional first parameter.** Steps, hooks and parameter-type transformers may declare the World as their
  first parameter. It is checked when glue loads with reified type tests. Supertypes are accepted, so reusable step
  libraries can target interfaces, for example a future `FlutterWorld`.
- **`World` is an optional `abstract mixin class`.** It exposes `parameters`, `scenario`, `attach`, `log` and
  `link`, which resolve the active scenario through a zone value. Any class can be a World.
- **Top-level functions.** `attach()`, `log()` and `link()` work anywhere in scenario or test-run context.
- **Context objects.** Hooks can receive `Scenario`, `Step` or `TestRun` objects (design §4.4).

## Consequences

**Benefits:**
- Type-safe state without codegen.
- Helpers can attach output without passing the World around.

**Costs:**
- The top-level `log` clashes with `dart:math`'s `log`. Users `hide` or prefix one of them.
- World members throw `StateError` outside an active context.

## Alternatives considered

- **Zone accessor only** (`world<T>()`). Untyped lookups everywhere.
- **Typed DI container.** More machinery than v1 needs.
- **Mandatory `World` base class.**
- **JVM-style attach only on `Scenario`.**
