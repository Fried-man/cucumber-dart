# Compatibility kit conformance

This report lists every sample of the [Cucumber Compatibility Kit][cck] (CCK) and its result through each of
cucumber-dart's hosts, with the reason for each sample that is skipped.

- **Kit:** `@cucumber/compatibility-kit` 31.0.0 (49 samples), synced byte for byte into
  [`packages/cucumber_compatibility_kit/features/`](../packages/cucumber_compatibility_kit/features/). CI runs
  `tool/sync.dart --check` there, so the samples cannot drift from the pinned tarball.
- **Plan:** [design §10][design-10] and [ADR-0019](decisions/0019-compatibility-kit-conformance.md). The target of
  milestone M6, 47 of 49 samples ([design §14][design-14]), is met by both hosts.
- **Kept current by** [`packages/cucumber/test/compatibility_report_test.dart`][report-test], which fails when this
  report no longer lists the synced samples or the skip lists that the conformance tests use. The conformance tests
  fail when a sample that is not skipped does not pass, so "passes" below means "passes in CI".

## How a sample is checked

Each sample has Dart glue equivalent to its reference TypeScript step definitions
([`samples.dart`](../packages/cucumber_core/test/compatibility/samples.dart)), and its `.arguments.txt` is translated
into options (`--retry 2` becomes `retry: 2`, `--order reverse` becomes `order: 'reverse'`). The messages the host
emits are compared with the sample's `.ndjson` ([design §10][design-10]):

- IDs are remapped to canonical IDs in order of first appearance and compared exactly, so every reference must point
  at the right message.
- Timestamps, durations, `meta` (except `protocolVersion`), the URI and line of code source references, error
  messages, exception details and snippet code are ignored. Extra fields are tolerated.
- Everything else is compared per message type, including Gherkin locations, statuses, step match argument offsets
  and attachment bodies.
- Partial-order assertions check that nothing is referenced before it is emitted, that everything started is
  finished, and that nesting is respected.

| Host | Test | How it runs the samples |
|---|---|---|
| `SerialHost` (`cucumber_core`) | [`test/compatibility/compatibility_test.dart`](../packages/cucumber_core/test/compatibility/compatibility_test.dart) | In process, one `SuitePlan` per sample, with incrementing IDs |
| `dart test` host (`cucumber`) | [`test/compatibility_host_test.dart`](../packages/cucumber/test/compatibility_host_test.dart) | One `dart test` run of the fixture project [`fixtures/cck`](../packages/cucumber/fixtures/cck/), which declares each sample with `cucumber()` and writes its messages with the `message:` plugin. The test also checks that `package:test` saw the outcome that the messages report for each scenario |

## Summary

| Host | Passing | Skipped | Samples |
|---|---|---|---|
| `SerialHost` | 47 | 2 | 49 |
| `dart test` host | 47 | 2 | 49 |

## Skip lists

### `SerialHost`

| Sample | Reason |
|---|---|
| `markdown` | The source is Gherkin in Markdown (`markdown.feature.md`, media type `text/x.cucumber.gherkin+markdown`). The Dart port of cucumber/gherkin, [`cucumber_gherkin`][gherkin-dart] 42.0.1, only has the classic token matcher, while the upstream JavaScript parser also has a Markdown one ([`GherkinInMarkdownTokenMatcher`][gherkin-markdown]). Directories and globs accordingly only select `*.feature` files ([design §5.10][design-5-10]). Markdown support in `cucumber_gherkin` is on the upstream wishlist ([design §11][design-11]). |
| `test-run-exception` | The sample's argument is `--error`, a switch of fake-cucumber, the reference implementation that generates the kit's messages (now in the kit's [devkit][devkit]). It makes fake-cucumber throw outside step and hook code right after `testRunStarted`, and the sample expects only `testRunFinished` with `success: false` and the `exception`. cucumber-dart has no such switch, and glue cannot cause an error outside user code, because an error in a step or hook only fails that step or hook ([design §5.3][design-5-3], [§5.4][design-5-4]). `SuitePlan` reports internal errors the way the sample expects ([design §5.9][design-5-9]), but this sample cannot exercise it. |

### `dart test` host

The `dart test` host runs the same engine, so it skips the samples above. It skips no others: every sample that
passes through the `SerialHost` also passes through `dart test`, including `empty`, whose scenario has no steps.

## Results

| Sample | Arguments | `SerialHost` | `dart test` host |
|---|---|---|---|
| [`all-statuses`](../packages/cucumber_compatibility_kit/features/all-statuses/) |  | passes | passes |
| [`ambiguous`](../packages/cucumber_compatibility_kit/features/ambiguous/) |  | passes | passes |
| [`attachments`](../packages/cucumber_compatibility_kit/features/attachments/) |  | passes | passes |
| [`backgrounds`](../packages/cucumber_compatibility_kit/features/backgrounds/) |  | passes | passes |
| [`cdata`](../packages/cucumber_compatibility_kit/features/cdata/) |  | passes | passes |
| [`data-tables`](../packages/cucumber_compatibility_kit/features/data-tables/) |  | passes | passes |
| [`data-tables-doc-strings`](../packages/cucumber_compatibility_kit/features/data-tables-doc-strings/) |  | passes | passes |
| [`data-tables-with-expression`](../packages/cucumber_compatibility_kit/features/data-tables-with-expression/) |  | passes | passes |
| [`doc-strings`](../packages/cucumber_compatibility_kit/features/doc-strings/) |  | passes | passes |
| [`doc-strings-with-expression`](../packages/cucumber_compatibility_kit/features/doc-strings-with-expression/) |  | passes | passes |
| [`empty`](../packages/cucumber_compatibility_kit/features/empty/) |  | passes | passes |
| [`examples-tables`](../packages/cucumber_compatibility_kit/features/examples-tables/) |  | passes | passes |
| [`examples-tables-attachment`](../packages/cucumber_compatibility_kit/features/examples-tables-attachment/) |  | passes | passes |
| [`examples-tables-undefined`](../packages/cucumber_compatibility_kit/features/examples-tables-undefined/) |  | passes | passes |
| [`examples-tables-undefined-multiple`](../packages/cucumber_compatibility_kit/features/examples-tables-undefined-multiple/) |  | passes | passes |
| [`failedish-combinations`](../packages/cucumber_compatibility_kit/features/failedish-combinations/) |  | passes | passes |
| [`global-hooks`](../packages/cucumber_compatibility_kit/features/global-hooks/) |  | passes | passes |
| [`global-hooks-afterall-error`](../packages/cucumber_compatibility_kit/features/global-hooks-afterall-error/) |  | passes | passes |
| [`global-hooks-attachments`](../packages/cucumber_compatibility_kit/features/global-hooks-attachments/) |  | passes | passes |
| [`global-hooks-beforeall-error`](../packages/cucumber_compatibility_kit/features/global-hooks-beforeall-error/) |  | passes | passes |
| [`hooks`](../packages/cucumber_compatibility_kit/features/hooks/) |  | passes | passes |
| [`hooks-attachment`](../packages/cucumber_compatibility_kit/features/hooks-attachment/) |  | passes | passes |
| [`hooks-conditional`](../packages/cucumber_compatibility_kit/features/hooks-conditional/) |  | passes | passes |
| [`hooks-named`](../packages/cucumber_compatibility_kit/features/hooks-named/) |  | passes | passes |
| [`hooks-skipped`](../packages/cucumber_compatibility_kit/features/hooks-skipped/) |  | passes | passes |
| [`hooks-undefined`](../packages/cucumber_compatibility_kit/features/hooks-undefined/) |  | passes | passes |
| [`markdown`](../packages/cucumber_compatibility_kit/features/markdown/) |  | skipped | skipped |
| [`minimal`](../packages/cucumber_compatibility_kit/features/minimal/) |  | passes | passes |
| [`multiple-features`](../packages/cucumber_compatibility_kit/features/multiple-features/) |  | passes | passes |
| [`multiple-features-reversed`](../packages/cucumber_compatibility_kit/features/multiple-features-reversed/) | `--order reverse` | passes | passes |
| [`parameter-types`](../packages/cucumber_compatibility_kit/features/parameter-types/) |  | passes | passes |
| [`pending`](../packages/cucumber_compatibility_kit/features/pending/) |  | passes | passes |
| [`pending-exception`](../packages/cucumber_compatibility_kit/features/pending-exception/) |  | passes | passes |
| [`regular-expression`](../packages/cucumber_compatibility_kit/features/regular-expression/) |  | passes | passes |
| [`retry`](../packages/cucumber_compatibility_kit/features/retry/) | `--retry 2` | passes | passes |
| [`retry-ambiguous`](../packages/cucumber_compatibility_kit/features/retry-ambiguous/) | `--retry 2` | passes | passes |
| [`retry-pending`](../packages/cucumber_compatibility_kit/features/retry-pending/) | `--retry 2` | passes | passes |
| [`retry-undefined`](../packages/cucumber_compatibility_kit/features/retry-undefined/) | `--retry 2` | passes | passes |
| [`rules`](../packages/cucumber_compatibility_kit/features/rules/) |  | passes | passes |
| [`rules-backgrounds`](../packages/cucumber_compatibility_kit/features/rules-backgrounds/) |  | passes | passes |
| [`skipped`](../packages/cucumber_compatibility_kit/features/skipped/) |  | passes | passes |
| [`skipped-exception`](../packages/cucumber_compatibility_kit/features/skipped-exception/) |  | passes | passes |
| [`skipped-failing-hook`](../packages/cucumber_compatibility_kit/features/skipped-failing-hook/) |  | passes | passes |
| [`stack-traces`](../packages/cucumber_compatibility_kit/features/stack-traces/) |  | passes | passes |
| [`test-run-exception`](../packages/cucumber_compatibility_kit/features/test-run-exception/) | `--error` | skipped | skipped |
| [`undefined`](../packages/cucumber_compatibility_kit/features/undefined/) |  | passes | passes |
| [`undefined-multiple`](../packages/cucumber_compatibility_kit/features/undefined-multiple/) |  | passes | passes |
| [`unknown-parameter-type`](../packages/cucumber_compatibility_kit/features/unknown-parameter-type/) |  | passes | passes |
| [`unused-steps`](../packages/cucumber_compatibility_kit/features/unused-steps/) |  | passes | passes |

[cck]: https://github.com/cucumber/compatibility-kit
[devkit]: https://github.com/cucumber/compatibility-kit/tree/main/devkit
[gherkin-dart]: https://pub.dev/packages/cucumber_gherkin
[gherkin-markdown]: https://github.com/cucumber/gherkin/blob/main/javascript/src/GherkinInMarkdownTokenMatcher.ts
[report-test]: ../packages/cucumber/test/compatibility_report_test.dart
[design-5-3]: design.md#53-step-execution-rules
[design-5-4]: design.md#54-hook-semantics
[design-5-9]: design.md#59-errors-outside-steps
[design-5-10]: design.md#510-discovery-filtering-and-ordering
[design-10]: design.md#10-compatibility-kit-plan-adr-0019-proposed
[design-11]: design.md#11-gaps-in-the-hosted-cucumber_expressions-adr-0020
[design-14]: design.md#14-milestones
