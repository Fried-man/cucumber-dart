# ADR-0007: Private interim tag-expression evaluator

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.2, §5.10, §9

## Context

There is no Dart implementation of `cucumber/tag-expressions` yet, and building the official one is out of scope for
now. Several features still need tag expressions:

- tagged hooks (`Before(tags: '@x')`);
- `--tags`-style filtering;
- the CCK samples `hooks-conditional` and `hooks-skipped`.

The JavaScript implementation is about 250 lines. The shared test data has three files:

| File | What it covers |
|---|---|
| `parsing.yml` | Expected canonical forms |
| `evaluations.yml` | Expressions evaluated against sets of tags |
| `errors.yml` | Exact error messages |

## Decision

- **A private port.** The JavaScript evaluator is ported as private code under `cucumber_core/lib/src/`. It is not
  exported.
- **Tests.** It is tested against the upstream `testdata/*.yml`, copied into the package's tests.
- **Replacement.** When an official Dart `tag-expressions` package exists, it replaces this code.

## Consequences

- Hook tags, filtering and the CCK work in v1, with the official grammar, precedence and error messages.
- No public API is added, so the later swap is not a breaking change.
