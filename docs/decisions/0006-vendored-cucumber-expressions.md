# ADR-0006: Vendor the cucumber-expressions Dart port and fix it here

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §11

## Context

The Dart port of Cucumber Expressions lives on the `feature/dart_implementation` branch of
[Fried-man/cucumber-expressions](https://github.com/Fried-man/cucumber-expressions), and is intended to be merged
into `cucumber/cucumber-expressions`. The runner needs three changes to it (design §11):

1. offsets for every group, which the CCK `stepMatchArguments` require;
2. non-nullable built-in parameter types, for the reified type checks;
3. access to an expression's parameter types before matching.

## Decision

- **Copy the source.** `dart/` from that branch, pinned at commit
  `9b047a995c1db17616bbde9333c5f97e180b0351` (2026-07-23), is copied into `packages/cucumber_expressions/`. The repository's
  shared `testdata/` is copied into `packages/cucumber_expressions/testdata/`.
- **Keep the upstream layout.** Files and layout stay as upstream has them, so the back-port is the diff against the
  pinned commit.
- **Local modifications made while vendoring:**
  - `pubspec.yaml`:
    - SDK constraint raised to `^3.8.0`;
    - `resolution: workspace` added;
    - dev dependencies aligned with the workspace (`lints ^6.0.0`, `test ^1.31.0`);
    - `publish_to: none` added.
  - `test/support/test_data_dir.dart`: also looks for in-package `testdata/`, falling back to `../testdata` as
    upstream does.
- **Fix in place.** The design §11 changes are made in this package, with conformance tests.
- **Back-porting** to the fork and the official repository is handled by the repository owner.

## Consequences

- The runner can depend on the fixes straight away.
- Every change to this package must stay compatible with the upstream API and test data.
- Keep the list above up to date when vendored files change.
