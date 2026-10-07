# ADR-0019: Compatibility kit conformance strategy

- **Status:** Proposed
- **Date:** 2026-10-06
- **Design:** §10

## Context

CCK v31 has 49 samples. Each one has a feature file, an expected `.ndjson`, and reference step definitions in
TypeScript. The first-party harnesses differ in how strict they are:

| Harness | How it compares | Samples skipped |
|---|---|---|
| cucumber-js | Deep-compares after removing ignored keys | 5 |
| cucumber-jvm | Compares leaf by leaf, per message type, in relative order | About 10 |
| cucumber-ruby | Compares only key sets | — |

No Dart package of the CCK exists.

## Decision (proposed)

- **Samples.**
  - They are synced byte-for-byte from the pinned npm tarball `@cucumber/compatibility-kit@31.0.0` into
    `packages/cucumber_compatibility_kit/features/`, with the SHA-512 integrity verified.
  - The sync is done by `tool/sync.dart`, and CI runs `tool/sync.dart --check` to catch drift.
  - The samples are marked `-text` in `.gitattributes`.
- **Harness.**
  - Each sample has Dart glue equivalent to its reference `.ts` file.
  - It runs through the core `SerialHost` with incrementing IDs.
  - A subset also runs through the `dart test` host.
- **Normalisation:**
  - IDs are remapped to canonical IDs in order of first appearance, then compared exactly. This also checks that
    references point at the right messages.
  - Timestamps and durations are ignored.
  - For `meta`, only `protocolVersion` is checked.
  - The URI and line of code source references are ignored.
  - Error messages and stack traces are ignored.
  - Snippets are checked separately against Dart golden files.
  - Everything else is compared, including `stepMatchArguments` group offsets.
- **Order.** Message sequences are compared per type, plus partial-order assertions.
- **Extra fields** are tolerated.
- **Initial skips:**
  - `markdown`: no Gherkin-in-Markdown support in `cucumber_gherkin`;
  - `test-run-exception`: depends on fake-cucumber's `--error` switch.

## Consequences

- A stricter check than any first-party harness, with a published target of 47 out of 49 samples.
- The sample package and its sync tool are the starting point for an upstream `compatibility-kit/dart` package.
