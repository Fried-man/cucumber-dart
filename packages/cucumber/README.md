# cucumber

Cucumber for Dart: run Gherkin `.feature` files as `dart test` tests, with Cucumber Expressions, hooks, typed data
tables and doc strings, and [Cucumber Messages][messages] reports (NDJSON, HTML and a console summary).

It is built on the official Cucumber components for Dart ([`cucumber_gherkin`][gherkin],
[`cucumber_messages`][messages] and [`cucumber_expressions`][expressions]) and is checked against the
[Cucumber Compatibility Kit][cck]: 47 of its 49 samples pass through `dart test` (see the
[compatibility report][compatibility]).

> **Status: pre-release.** `cucumber` is not on pub.dev yet, because it depends on packages that are not published
> yet (see [Publishing][publishing]). Until then, depend on it from Git, as shown below.

## Install

```yaml
# pubspec.yaml
dev_dependencies:
  cucumber:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber}
  test: ^1.31.0

# Until cucumber's dependencies are on pub.dev:
dependency_overrides:
  cucumber_core:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_core}
  cucumber_ci_environment:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_ci_environment}
  cucumber_html_formatter:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_html_formatter}
  cucumber_query:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_query}
```

## Quick start

Write a feature:

```gherkin
# features/belly.feature
Feature: Belly
  Scenario: a few cukes
    Given I have 42 cukes in my belly
    When I wait 1 hour
    Then my belly should growl
```

Define the steps as glue values, with a World that holds each scenario's state:

```dart
// test/steps/belly_steps.dart
import 'package:cucumber/cucumber.dart';
import 'package:test/test.dart';

class BellyWorld extends World {
  int cukes = 0;
  int hours = 0;
}

final bellyGlue = <Glue>[
  Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) {
    w.cukes += cukes;
  }),
  When('I wait {int} hour(s)', (BellyWorld w, int hours) {
    w.hours += hours;
  }),
  Then('my belly should growl', (BellyWorld w) {
    expect(w.cukes > 10 && w.hours >= 1, isTrue);
  }),
];
```

Declare the suite in a test file:

```dart
// test/cucumber_test.dart
import 'package:cucumber/cucumber.dart';

import 'steps/belly_steps.dart';

void main() => cucumber(
  features: ['features/'],
  world: BellyWorld.new,
  glue: bellyGlue,
);
```

And run it:

```sh
dart test
```

Each scenario (and each example row of a scenario outline) is a test, grouped by feature, rule and outline, so IDE
run and debug, `--name`, sharding and coverage work as for any other test. Gherkin tags become `package:test` tags
(declare them in `dart_test.yaml` to avoid warnings), and test locations point at the `.feature` lines. The `summary`
plugin prints the snippets for undefined steps.

The [example](https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber/example) is a complete project.

## Glue

| Glue | Purpose |
|---|---|
| `Given`, `When`, `Then` | Step definitions, with a Cucumber Expression (`String`) or a `RegExp` |
| `Before`, `After`, `BeforeStep`, `AfterStep` | Scenario and step hooks, with optional `tags`, `name` and `order` |
| `BeforeAll`, `AfterAll` | Test-run hooks |
| `ParameterType<T>` | Custom `{name}` parameters |
| `DataTableType<T>`, `DocStringType<T>` | Typed data table and doc string conversions |

Step and hook bodies may take the World as their first parameter, followed by the step's parameters and its data
table or doc string. The shapes and types are checked when the glue loads. `pending()` and `skip()` mark a step as
pending or skipped, and `attach`, `log` and `link` add attachments to the report.

## Configuration

Options come from code (`cucumber(...)` or `CucumberOptions`), from profiles in `cucumber.yaml` at the package root,
and from `CUCUMBER_*` environment variables, in increasing order of precedence:

```yaml
# cucumber.yaml
default:
  tags: not @wip
  plugins:
    - message:build/cucumber/messages.ndjson
    - html:build/cucumber/report.html
    - summary
ci:
  retry: 1
```

```sh
CUCUMBER_PROFILE=ci dart test
CUCUMBER_FILTER_TAGS=@smoke dart test
CUCUMBER_FEATURES=features/belly.feature:3 dart test
```

## Reports

- `message:<path>`: the Cucumber Messages as NDJSON.
- `html:<path>`: a standalone HTML report (`@cucumber/html-formatter`).
- `summary`: failures, warnings, counts, durations and snippets, printed when the suite ends.

When `dart test` runs several test files, their reports are merged into one. To merge the reports of CI shards,
collect each shard's `build/.cucumber/parts/<runId>/` directory and run:

```sh
dart run cucumber:merge -p html:build/cucumber/report.html shard-1/ shard-2/
```

## More

- [Design](https://github.com/Fried-man/cucumber-dart/blob/main/docs/design.md) and
  [decision log](https://github.com/Fried-man/cucumber-dart/tree/main/docs/decisions)
- [Compatibility report][compatibility]: every Cucumber Compatibility Kit sample, its result and the skip list
- [`cucumber_core`](https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber_core): the
  runner-agnostic engine that this package re-exports

[messages]: https://github.com/cucumber/messages
[gherkin]: https://github.com/cucumber/gherkin
[expressions]: https://pub.dev/packages/cucumber_expressions
[cck]: https://github.com/cucumber/compatibility-kit
[compatibility]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/compatibility.md
[publishing]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/design.md#141-publishing
