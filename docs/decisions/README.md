# Decision log

These are architecture decision records (ADRs) for cucumber-dart. Each record covers one decision: its context, the
decision itself, its consequences, and the alternatives we considered. The overall design is in
[`../design.md`](../design.md).

| ADR | Title | Status |
|---|---|---|
| [0001](0001-runner-agnostic-core-with-package-test-host.md) | Runner-agnostic core with `package:test` as the primary host | Accepted |
| [0002](0002-glue-as-explicit-values.md) | Step definitions and hooks as explicit glue values; codegen later | Accepted |
| [0003](0003-typed-world-and-attachment-api.md) | Typed World as optional first parameter; optional `World` base; top-level attach/log/link | Accepted |
| [0004](0004-dart-first-flutter-ready-core.md) | Pure Dart first, Flutter-ready core | Accepted |
| [0005](0005-monorepo-and-in-repo-ports.md) | Monorepo layout, in-repo ports of shared libraries, later swap to published packages | Accepted |
| [0006](0006-vendored-cucumber-expressions.md) | Vendor the cucumber-expressions Dart port and fix it here | Accepted |
| [0007](0007-interim-tag-expressions.md) | Private interim tag-expression evaluator | Accepted |
| [0008](0008-pending-and-skipped-via-exceptions.md) | Pending and skipped signalled by exceptions and helpers | Accepted |
| [0009](0009-v1-outputs.md) | v1 outputs: NDJSON, HTML, summary and snippets | Accepted |
| [0010](0010-configuration-sources.md) | Configuration from code, `cucumber.yaml` profiles and `CUCUMBER_*` environment | Accepted |
| [0011](0011-typed-data-tables-and-doc-strings.md) | Typed DataTable and DocString conversion in v1 | Accepted |
| [0012](0012-suite-entrypoint.md) | `cucumber()` entrypoint over `CucumberOptions` / `CucumberSuite` | Accepted |
| [0013](0013-package-test-mapping.md) | `package:test` tree, names, locations, tags and outcomes | Accepted |
| [0014](0014-hook-ordering.md) | Hook ordering: definition order plus optional `order` | Accepted |
| [0015](0015-parameter-type-transformers.md) | Parameter type transformers checked at glue load | Accepted |
| [0016](0016-report-merging.md) | Per-isolate report parts with automatic merge and a merge CLI | Accepted |
| [0017](0017-execution-semantics.md) | Execution semantics | Proposed |
| [0018](0018-message-ids.md) | Deterministic IDs for static messages | Proposed |
| [0019](0019-compatibility-kit-conformance.md) | Compatibility kit conformance strategy | Proposed |

## Template

```markdown
# ADR-NNNN: Title

- **Status:** Proposed | Accepted | Superseded by ADR-XXXX
- **Date:** YYYY-MM-DD

## Context
## Decision
## Consequences
## Alternatives considered
```
