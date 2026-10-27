# cucumber-dart

Cucumber for Dart: run Gherkin `.feature` files as `dart test` tests, with Cucumber Expressions, hooks, typed data
tables and doc strings, and [Cucumber Messages](https://github.com/cucumber/messages) reports (NDJSON, HTML and a
console summary). 47 of the 49 [Cucumber Compatibility Kit](https://github.com/cucumber/compatibility-kit) samples
pass ([compatibility report](docs/compatibility.md)).

**Start with the [guide](docs/guide/README.md)**: [getting started](docs/guide/getting-started.md),
[writing glue](docs/guide/writing-glue.md), [configuration](docs/guide/configuration.md),
[reports](docs/guide/reports.md) and [running with `dart test`](docs/guide/package-test.md).

## Packages

| Package | What it is |
|---|---|
| [`cucumber`](packages/cucumber/) | What test suites depend on: the `dart test` host, configuration, reports and the merge CLI |
| [`cucumber_core`](packages/cucumber_core/) | The runner-agnostic engine and glue API, for building other hosts |
| [`cucumber_query`](packages/cucumber_query/) | A port of [cucumber/query](https://github.com/cucumber/query) |
| [`cucumber_html_formatter`](packages/cucumber_html_formatter/) | The HTML report of [cucumber/html-formatter](https://github.com/cucumber/html-formatter) |
| [`cucumber_ci_environment`](packages/cucumber_ci_environment/) | A port of [cucumber/ci-environment](https://github.com/cucumber/ci-environment) |
| [`cucumber_compatibility_kit`](packages/cucumber_compatibility_kit/) | The Compatibility Kit's samples |

The packages are not on pub.dev yet ([design §14.1](docs/design.md#141-publishing)).
[`packages/cucumber/README.md`](packages/cucumber/README.md#install) shows how to depend on them from Git.

## More

- [Design](docs/design.md) and [decision log](docs/decisions/README.md)
- [Performance](docs/performance.md): timings on a large suite, and how to measure them
