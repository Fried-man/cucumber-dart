# ADR-0011: Typed DataTable and DocString conversion in v1

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §4.2, §4.5, §4.6

## Context

| Implementation | What it offers |
|---|---|
| cucumber-js | String-only tables: `raw`, `rows`, `hashes`, `rowsHash`, `transpose` |
| cucumber-ruby | Adds header mapping and `diff!` |
| cucumber-jvm | Typed conversion through registries: entry, row, cell and table transformers; `DocStringType`; conversion driven by the step parameter's type; `diff` |

Many JVM users consider typed conversion part of what "full Cucumber" means.

## Decision

v1 ships cucumber-jvm-style typed conversion.

- **Registries:**
  - `DataTableType<T>.entry`, `.row`, `.cell` and `.table`, with an optional `replaceWithEmptyString` marker;
  - `DocStringType<T>`, with an optional content type.
- **`DataTable` API:**
  - `raw`, `cell`, `row`, `column`, `rows`, `columns`, `transpose`;
  - typed `asList<T>()`, `asLists<T>()`, `asMaps<K,V>()`, `asMap<K,V>()` and `convert<T>()`;
  - `diff`.
  - Calls without type arguments return strings.
- **Conversion by parameter type.** A step parameter's declared type (`DataTable`, `List<List<String>>`, `List<T>`,
  `T`, `DocString`, `String`, …) selects the conversion, using reified type checks.
- **Empty cells.** `raw` keeps them as `''`. Typed conversion to a nullable type turns `''` into `null`, following
  cucumber-jvm.

## Consequences

- A richer API than cucumber-js or cucumber-ruby.
- There is no reflection-based default entry transformer like cucumber-jvm's Jackson-backed one, so users register
  their types. A future codegen package may generate those registrations.
