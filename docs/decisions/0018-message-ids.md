# ADR-0018: Deterministic IDs for static messages

- **Status:** Proposed
- **Date:** 2026-10-06
- **Design:** §7.2, §8.4

## Context

Each implementation generates message IDs differently:

| Implementation | ID scheme |
|---|---|
| cucumber-js, cucumber-ruby | Random UUIDs |
| cucumber-jvm | A pluggable `UuidGenerator` |
| The CCK | Incrementing IDs |

Merging report parts from several isolates (ADR-0016) is much simpler if the same feature file or glue gets the same
IDs in every isolate. The CCK harness normalises IDs anyway.

## Decision (proposed)

- **Static messages** get deterministic IDs:
  - Gherkin AST nodes and pickles: `<fnv64(uri)>-<n>`, with a counter per feature file. Parsing order is
    deterministic, so the IDs are too.
  - Glue (step definitions, hooks, parameter types): a hash of the source reference and pattern, plus the
    definition index.
- **Dynamic messages** (test run, test cases, test steps, starts) get UUID v4s.
- **Tests and the CCK** use an incrementing generator.

## Consequences

- Merging can de-duplicate shared sources and glue by ID.
- IDs are stable across runs, which can help tooling.
- This must be checked against the HTML formatter and the CCK before it is accepted.
