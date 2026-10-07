# ADR-0014: Hook ordering: definition order plus optional `order`

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.2, §5.2

## Context

| Implementation | Hook order |
|---|---|
| cucumber-js, cucumber-ruby | Definition order; after-hooks run in reverse definition order, which the CCK expects for `After` and `AfterAll` |
| cucumber-jvm | An `order` attribute: lower values run first for before-hooks, higher values run first for after-hooks |

Reusable step libraries need a way to position their hooks relative to the user's own.

## Decision

- **Sorting.** Hooks are stably sorted by `(order, definition index)`, with `order` defaulting to 0.
- **Direction:**
  - `Before`, `BeforeStep` and `BeforeAll` run in ascending order.
  - `After`, `AfterStep` and `AfterAll` run in descending order.
  - With no `order` given, this is definition order for before-hooks and reverse definition order for after-hooks.

## Consequences

- The default behaviour matches cucumber-js and the CCK.
- Libraries can still control where their hooks run.
