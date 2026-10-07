# ADR-0002: Step definitions and hooks as explicit glue values; codegen later

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.2, §4.5, §13

## Context

`dart:mirrors` is unavailable on Flutter, AOT and the web. That leaves four options for defining steps:

1. registration in code;
2. global registration, as in cucumber-js;
3. annotations plus code generation, as in cucumber-java;
4. a per-scenario initializer, as in godog.

Several findings shaped the choice:

- **cucumber-jvm's lambda backend.** It had to re-create glue for every scenario and resolve lambda types through
  `Unsafe`. Its maintainers proposed a static DSL instead (cucumber-jvm #2279).
- **No side effects at load in Dart.** Dart has no module-level side effects, so global registration would still
  need explicit setup calls.
- **Reified generics.** Dart's generics survive to runtime, which allows checking a function's arity and parameter
  types when glue loads, without mirrors.

## Decision

- **Glue values.** Step definitions (`Given`/`When`/`Then`), hooks (`Before`, `After`, `BeforeStep`, `AfterStep`,
  `BeforeAll`, `AfterAll`), `ParameterType<T>`, `DataTableType<T>` and `DocStringType<T>` are immutable glue values.
  They are collected in ordered `List<Glue>`s and passed to the suite.
- **Checks at load.** Step, hook and transformer bodies are `Function`s. Their arity and parameter types are checked
  when the glue loads (design §4.5).
- **Source references.** Each value captures its location from `StackTrace.current` when it is constructed.
- **Later codegen.** A later `cucumber_builder` package will generate the same lists from annotations such as
  `@Given`.

## Consequences

**Benefits:**
- No global state, and definition order (and therefore IDs) is deterministic.
- Works on every platform.
- Glue values are easy to unit-test.

**Costs:**
- Closures passed as `Function` don't get parameter type inference, so users annotate types such as `(int n)`.
  Checks when glue loads catch mistakes early, and codegen will add compile-time checking.
- Glue must be listed explicitly; codegen will automate discovery later.

## Alternatives considered

- **Global DSL (cucumber-js style).** Hidden global state, and explicit setup calls are still needed.
- **Codegen only.** Forces `build_runner` on every user.
- **godog-style initializer.** Re-registers glue for every scenario and can't be checked up front.
