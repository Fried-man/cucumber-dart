# Reports

Every run emits [Cucumber Messages](https://github.com/cucumber/messages), the protocol that all official Cucumber
implementations share. The *plugins* turn them into reports. The examples come from
[`packages/cucumber/fixtures/guide`](../../packages/cucumber/fixtures/guide/).

## Outputs

| Plugin | Writes |
|---|---|
| `message:<path>` | The messages as NDJSON, one JSON object per line: the full record of the run, for tools |
| `html:<path>` | A standalone HTML report, made by [`@cucumber/html-formatter`](https://github.com/cucumber/html-formatter) as in the other Cucumber implementations |
| `summary` | Failures, warnings, counts, durations and snippets for undefined steps, printed when the suite ends |

Set them with the `plugins` option in code, in a `cucumber.yaml` profile, or in `CUCUMBER_PLUGIN` (comma-separated):

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
CUCUMBER_PLUGIN=summary dart test
CUCUMBER_PLUGIN=message:build/run.ndjson,summary dart test
```

Paths are relative to the package root. A report is written once a suite starts its run. A suite whose tests are all
filtered out writes nothing, and leaves the reports of an earlier run as they are.

## The summary

Each suite prints its summary when it ends. It follows cucumber-js's summary:

- the parameter types that step definitions use but no glue defines;
- `Failures:` every scenario whose final attempt failed or was pending, undefined or ambiguous, and every failed
  `BeforeAll` or `AfterAll` hook;
- `Warnings:` the attempts that were retried, and the skipped scenarios;
- for each scenario listed, its location, its steps with their statuses, and the errors of the steps that did not pass;
- the counts of scenarios and steps by status (final attempts only), the run's duration and the time spent in steps;
- snippets for the undefined steps.

In the guide's project, the checkout suite's summary lists the retried attempt and the skipped scenario:

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
dart test
```

<!-- output -->
```text
Warnings:
1) Scenario: Checkout - paying after the payment service restarted (attempt 1, retried) # features/checkout.feature:16
FAILED  Given the payment service restarts once # features/checkout.feature:17
Bad state: The payment service is restarting
2) Scenario: Checkout - paying in Swiss francs # features/checkout.feature:22
SKIPPED Given I pay in CHF # features/checkout.feature:23
Skipped: Payments in CHF are not supported yet
3 scenarios (1 skipped, 2 passed)
13 steps (3 skipped, 10 passed)
```

## Custom plugins

A `Plugin` receives each message, as an `Envelope` of
[`package:cucumber_messages`](https://pub.dev/packages/cucumber_messages), and is closed when the suite ends:

<!-- excerpt: packages/cucumber/fixtures/guide/test/support/scenario_counter.dart -->
```dart
import 'package:cucumber/cucumber.dart';
import 'package:cucumber_messages/cucumber_messages.dart' show Envelope;

/// Prints how many scenarios finished when the suite ends.
final class ScenarioCounter implements Plugin {
  int _finished = 0;

  @override
  void onMessage(Envelope envelope) {
    if (envelope.testCaseFinished case final finished?
        when !finished.willBeRetried) {
      _finished++;
    }
  }

  @override
  Future<void> close() async => print('$_finished scenarios finished');
}
```

Plugin instances can only be given in code, in the `plugins` option. They are kept when a profile or
`CUCUMBER_PLUGIN` sets the plugins:

<!-- excerpt: packages/cucumber/fixtures/guide/test/cart_test.dart -->
```dart
import 'package:cucumber/cucumber.dart';

import 'steps/shop_steps.dart';
import 'support/options.dart';
import 'support/scenario_counter.dart';

void main() => CucumberSuite<ShopWorld>(
  shopOptions.merge(
    CucumberOptions(
      features: ['features/cart.feature'],
      plugins: [ScenarioCounter()],
    ),
  ),
).declare();
```

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
dart test test/cart_test.dart
```

<!-- output -->
```text
6 scenarios finished
```

`CallbackPlugin` wraps a function, and `CollectingPlugin` keeps every message. `NdjsonPlugin(path)` and
`HtmlPlugin(path)` write the messages of their own suite only, unlike the `message:` and `html:` specifications,
whose reports are merged.

## Reports of several test files

`dart test` runs each test file in its own isolate, and each entry file is a suite with its own messages. The
`message:` and `html:` reports of a run are merged, so a run of several entry files leaves one report:

1. Each suite writes its messages to a *report part*, `build/.cucumber/parts/<runId>/<suiteId>.ndjson`. The run ID is
   the `dart test` process's ID (or `CUCUMBER_RUN_ID`), and the suite ID is the test file's path below `test/`,
   without `.dart` (or the `suiteName` option): `test/cart_test.dart` is `cart_test`.
2. When a suite ends, it merges the parts of the run and rewrites the reports. The last suite to end leaves the
   complete report. Each report is merged from the suites that configure it, so a suite with its own report file
   keeps its own report.
3. In the merged report, each scenario's `workerId` is its suite ID, so tools can tell the suites apart.

The summary is not merged: each suite prints its own. The parts of earlier runs are deleted once they have not
changed for an hour.

## Merging CI shards

CI can split a run across machines with `dart test --total-shards <n> --shard-index <i>`. Each machine then has the
report parts of its share in `build/.cucumber/parts/<runId>/`. `dart run cucumber:merge` merges the parts of every
machine into one report:

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
CUCUMBER_RUN_ID=shard-1 dart test --total-shards 2 --shard-index 0
CUCUMBER_RUN_ID=shard-2 dart test --total-shards 2 --shard-index 1
dart run cucumber:merge -p html:build/cucumber/report.html -p summary build/.cucumber/parts/shard-1 build/.cucumber/parts/shard-2
```

<!-- output -->
```text
9 scenarios (1 skipped, 8 passed)
Note: Suite ID "cart_test" is used by several report parts
```

Both shards ran some of the scenarios of both test files, so their parts have the same suite IDs. The merge keeps
the first and renames the others `cart_test#2` and so on, and says so on standard error.

| Argument | Meaning |
|---|---|
| `<input>...` | A directory of parts (the `*.ndjson` files directly in it, such as `build/.cucumber/parts/<runId>/`), an `.ndjson` part, or a glob of either, such as `'shards/*/parts/*'`. The CLI expands globs itself, so they also work where the shell does not expand them. |
| `-p`, `--plugin <spec>` | A report to write: `message:<path>`, `html:<path>` (relative to the current directory) or `summary` (printed). Repeatable. Without it, the summary is printed. |
| `-h`, `--help` | Prints the usage. |

| Exit code | Meaning |
|---|---|
| 0 | The merged run succeeded |
| 1 | The merged run failed, or no part finished |
| 2 | A usage error: invalid arguments, a missing or invalid input, or a report that cannot be written |

Give each run its own `CUCUMBER_RUN_ID`, such as the CI run's ID. A suite whose part already exists in the run's
directory writes a new part next to it, and both are merged, so reusing a run ID mixes the runs. For a package at the
root of its repository, a GitHub Actions workflow could look like this:

<!-- checked: workflow -->
```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        shard: [0, 1, 2]
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart test --total-shards 3 --shard-index ${{ matrix.shard }}
        env:
          CUCUMBER_RUN_ID: ${{ github.run_id }}-${{ github.run_attempt }}
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: cucumber-parts-${{ matrix.shard }}
          path: build/.cucumber/parts/
          include-hidden-files: true

  report:
    needs: test
    if: always()
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - uses: actions/download-artifact@v4
        with:
          pattern: cucumber-parts-*
          path: parts
      - run: dart run cucumber:merge -p html:report.html -p message:messages.ndjson 'parts/*/*'
      - uses: actions/upload-artifact@v4
        with:
          name: cucumber-report
          path: |
            report.html
            messages.ndjson
```

Each artifact is downloaded into its own directory, `parts/cucumber-parts-<shard>/<runId>/`, which the glob
`'parts/*/*'` matches. The merge job's exit code says whether the merged run succeeded.

## In code

`package:cucumber` exports the functions behind these reports, for tools that process messages:

- `mergeReportParts(parts)` merges the messages of several suites (`ReportPart`s) into one stream;
- `formatSummaryOf(envelopes)` formats the summary of a stream, and `formatSummary(query)` the summary of a
  [`cucumber_query`](../../packages/cucumber_query/) `Query`.
