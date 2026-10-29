# cucumber-dart guide

[Cucumber for Dart](../../packages/cucumber/) runs Gherkin `.feature` files as `dart test` tests, and
[`cucumber_flutter`](../../packages/cucumber_flutter/) runs them as Flutter widget tests. This guide is for
the people who write those features and their step definitions, and run them locally and on CI.

| Page | What it covers |
|---|---|
| [Getting started](getting-started.md) | Install the package, write a feature and its steps, run them, configure the run, implement undefined steps, read the reports |
| [Writing glue](writing-glue.md) | Steps, Cucumber Expressions and regular expressions, parameter types, data tables, doc strings, the World, hooks, attachments, pending and skipped steps, timeouts and retries |
| [Configuration](configuration.md) | Every option in code, in `cucumber.yaml` and in `CUCUMBER_*` variables, profiles, how the sources combine, and where features are found |
| [Reports](reports.md) | The NDJSON, HTML and summary outputs, custom plugins, reports merged across test files, and merging CI shards |
| [Running with `dart test`](package-test.md) | How features become tests, names, locations, tags, outcomes, filtering, IDEs, timeouts and sharding |
| [Widget tests with Flutter](flutter.md) | `cucumber_flutter`: features as Flutter widget tests, the `WidgetTester` in the World, Flutter errors, fake time, reports under `flutter test`, and what differs from `dart test` |

More documents:

- [Performance](../performance.md): timings on a large suite, and how to measure them.
- [Compatibility report](../compatibility.md): the Cucumber Compatibility Kit samples that pass, and why two are
  skipped.
- [Design](../design.md) and [decision log](../decisions/README.md): how cucumber-dart works and why.

The examples in this guide come from projects in this repository, which the tests run:
[`fixtures/getting_started`](../../packages/cucumber/fixtures/getting_started/) for the getting-started page,
[`cucumber_flutter`'s example app](../../packages/cucumber_flutter/example/) for the Flutter page, and
[`fixtures/guide`](../../packages/cucumber/fixtures/guide/) for the others.
[`test/docs_test.dart`](../../packages/cucumber/test/docs_test.dart) checks that each code block matches the file it
comes from, and runs each command shown.
