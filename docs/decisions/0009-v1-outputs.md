# ADR-0009: v1 outputs: NDJSON, HTML, summary and snippets

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §8

## Context

Every Cucumber output derives from the messages stream:

- **HTML.** `@cucumber/html-formatter` is a prebuilt JavaScript/CSS bundle. The Java, Ruby and .NET versions are thin
  wrappers that stream messages into a template.
- **JUnit and console output.** JUnit XML and the console formatters (`pretty-formatter`) depend on `cucumber/query`.
- **Who owns the console.** Under `dart test`, the test reporter owns the console.

## Decision

v1 ships three outputs:

- **NDJSON messages** (`message:<path>`), the canonical output.
- **HTML report** (`html:<path>`), from `cucumber_html_formatter`, which wraps the pinned upstream assets.
- **Summary and snippets** (`summary`), printed when the suite ends.
  - It counts scenarios and steps.
  - It lists non-passing scenarios with their locations.
  - It prints de-duplicated Dart snippets for undefined steps. The failure message of an undefined step's test also
    includes its snippets.

Later outputs: JUnit XML, legacy Cucumber JSON, pretty and progress console output, rerun files, and usage reports.

## Consequences

- HTML needs no query port.
- The summary and the report merge will use `cucumber_query`, which is planned for M5.
