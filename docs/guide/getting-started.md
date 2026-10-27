# Getting started

This page builds a small project that tests a belly: it growls when it has eaten enough cucumbers and waited long
enough. The finished project is [`packages/cucumber/fixtures/getting_started`](../../packages/cucumber/fixtures/getting_started/).

You need Dart 3.8 or later.

## Install

`cucumber` is not on pub.dev yet, because the packages it depends on are not published yet
([design §14.1](../design.md#141-publishing)). Until they are, depend on it from Git, and override those dependencies
with Git dependencies too:

<!-- checked: install -->
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

Then run `dart pub get`. The project will have these files:

<!-- files in: packages/cucumber/fixtures/getting_started -->
```text
features/belly.feature        the behaviour, in Gherkin
lib/belly.dart                the code under test
test/steps/belly_steps.dart   the step definitions
test/cucumber_test.dart       the entry file that dart test runs
cucumber.yaml                 the configuration (added later)
dart_test.yaml                package:test's configuration (added later)
```

## Write a feature

A feature file describes behaviour as scenarios made of steps. Put it in `features/`:

<!-- excerpt: packages/cucumber/fixtures/getting_started/features/belly.feature -->
```gherkin
Feature: Belly
  A belly growls when it has eaten enough cucumbers and waited.

  @smoke
  Scenario: a few cukes
    Given I have 42 cukes in my belly
    When I wait 1 hour
    Then my belly should growl

  Scenario: not enough cukes
    Given I have 3 cukes in my belly
    When I wait 2 hours
    Then my belly should not growl

  Scenario Outline: eating <count> cukes
    Given I have <count> cukes in my belly
    When I wait 1 hour
    Then my belly should <outcome>

    Examples:
      | count | outcome   |
      | 11    | growl     |
      | 10    | not growl |
```

The scenario outline runs once for each row of its examples, with `<count>` and `<outcome>` replaced by the row's
values. `@smoke` is a tag, which selects scenarios (see [Run part of it](#run-part-of-it)).

This is the code under test:

<!-- excerpt: packages/cucumber/fixtures/getting_started/lib/belly.dart -->
```dart
/// The code under test in the getting-started guide.
library;

/// A belly that growls when it has eaten enough cucumbers and waited.
class Belly {
  /// How many cucumbers it has eaten.
  int cukes = 0;

  /// How many hours it has waited.
  int hours = 0;

  /// Eats [count] cucumbers.
  void eat(int count) => cukes += count;

  /// Waits [hours] hours.
  void wait(int hours) => this.hours += hours;

  /// Whether it growls: after more than 10 cucumbers and at least an hour.
  bool get isGrowling => cukes > 10 && hours >= 1;
}
```

## Define the steps

Step definitions connect the steps' text to code. In cucumber-dart they are *glue values*, a plain list of `Given`,
`When` and `Then` values (and hooks and types, see [Writing glue](writing-glue.md)):

<!-- excerpt: packages/cucumber/fixtures/getting_started/test/steps/belly_steps.dart -->
```dart
import 'package:cucumber/cucumber.dart';
import 'package:cucumber_getting_started/belly.dart';
import 'package:test/test.dart';

/// Holds the state of one scenario. A new one is created for every scenario.
class BellyWorld extends World {
  final belly = Belly();
}

final bellyGlue = <Glue>[
  Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) {
    w.belly.eat(cukes);
  }),
  When('I wait {int} hour(s)', (BellyWorld w, int hours) {
    w.belly.wait(hours);
  }),
  Then('my belly should growl', (BellyWorld w) {
    expect(w.belly.isGrowling, isTrue);
  }),
  Then('my belly should not growl', (BellyWorld w) {
    expect(w.belly.isGrowling, isFalse);
  }),
];
```

- Each expression is a [Cucumber Expression](https://github.com/cucumber/cucumber-expressions#readme): `{int}` matches
  an integer and passes it to the body as an `int`, and `hour(s)` matches `hour` and `hours`. The keyword does not
  matter for matching: `Given` could match a step written with `When`.
- The body takes the step's parameters in order. It may take the World first: the object that holds the state of the
  scenario. Extending `World` is optional; it adds members such as `parameters` and `attach`.
- A step fails when its body throws, here when an `expect` fails. `package:test`'s matchers work as in any test.
- cucumber-dart checks the bodies when the glue loads: a body that takes the wrong number of parameters, or a
  parameter of the wrong type (a `String` for `{int}`), makes `dart test` report a load error that names the step
  definition.

## Declare the suite

An entry file in `test/` declares the suite. `dart test` runs it like any other test file:

<!-- excerpt: packages/cucumber/fixtures/getting_started/test/cucumber_test.dart -->
```dart
import 'package:cucumber/cucumber.dart';

import 'steps/belly_steps.dart';

void main() =>
    cucumber(features: ['features/'], world: BellyWorld.new, glue: bellyGlue);
```

`features` lists where the feature files are, relative to the package root (`features/` is the default). `world`
creates the World for each scenario. `cucumber()` declares the tests synchronously, so call it directly in `main()`.

## Run it

<!-- run in: packages/cucumber/fixtures/getting_started -->
```sh
dart test
```

Each scenario, and each example row of the outline, is a test, grouped by feature and outline:

<!-- output -->
```text
Belly a few cukes
Belly not enough cukes
Belly eating <count> cukes Examples Example #1.1: eating 11 cukes
Belly eating <count> cukes Examples Example #1.2: eating 10 cukes
+4: All tests passed!
```

IDEs show the same tree. You can run and debug a single scenario there, and they link each test to its line in the
feature file. [Running with `dart test`](package-test.md) explains the names and how outcomes are reported.

## Run part of it

`dart test`'s own options select tests by name or tag. Gherkin tags become `package:test` tags, without the `@`:

<!-- run in: packages/cucumber/fixtures/getting_started -->
```sh
dart test --name "a few cukes"
dart test --tags smoke
```

`CUCUMBER_*` environment variables configure Cucumber itself. For example, they select scenarios by line or with a
[tag expression](https://cucumber.io/docs/cucumber/api/#tag-expressions):

<!-- run in: packages/cucumber/fixtures/getting_started -->
```sh
CUCUMBER_FEATURES=features/belly.feature:10 dart test   # the scenario on line 10
CUCUMBER_FEATURES=features/belly.feature:22 dart test   # the first example row
CUCUMBER_FILTER_TAGS="not @smoke" dart test
```

The commands in this guide use POSIX shell syntax. In PowerShell, set the variable first, for example
`$env:CUCUMBER_FILTER_TAGS = "not @smoke"`, and remove it afterwards with `Remove-Item Env:CUCUMBER_FILTER_TAGS`.

## Configure the run

`cucumber.yaml` at the package root holds *profiles* of options. The `default` profile applies when no profile is
named:

<!-- excerpt: packages/cucumber/fixtures/getting_started/cucumber.yaml -->
```yaml
# Applies when no profile is named.
default:
  tags: not @wip
  plugins:
    - message:build/cucumber/messages.ndjson
    - html:build/cucumber/report.html
    - summary

# CUCUMBER_PROFILE=wip dart test
wip:
  tags: '@wip'
```

- `tags: not @wip` leaves out the scenarios tagged `@wip` (work in progress).
- `plugins` adds the reports: the [Cucumber Messages](https://github.com/cucumber/messages) as NDJSON, an HTML report,
  and a summary printed at the end of the run.
- `CUCUMBER_PROFILE=wip` selects the `wip` profile instead, which runs only the `@wip` scenarios.

Options in `cucumber.yaml` override the ones in code, and `CUCUMBER_*` variables override both. Tag expressions are
the exception: they are combined with `and`, so each source can only narrow the selection.
[Configuration](configuration.md) lists every option.

`package:test` warns about tags that `dart_test.yaml` does not declare, so declare the tags of the features there:

<!-- excerpt: packages/cucumber/fixtures/getting_started/dart_test.yaml -->
```yaml
tags:
  smoke:
  wip:
```

## Implement a new step

Start a new feature, tagged `@wip` so that the default run leaves it out while you work on it:

<!-- excerpt: packages/cucumber/fixtures/getting_started/features/singing.feature -->
```gherkin
@wip
Feature: Singing
  Scenario: a happy belly
    Given I have 20 cukes in my belly
    Then my belly should sing
```

Run it with the `wip` profile:

<!-- run in: packages/cucumber/fixtures/getting_started -->
```sh
CUCUMBER_PROFILE=wip dart test   # fails: a step is undefined
```

No step definition matches `my belly should sing`, so the step is *undefined* and the test fails. Its message
includes a snippet to start from:

<!-- output -->
```text
Undefined step in scenario "a happy belly" (features/singing.feature:3):
  Then my belly should sing (features/singing.feature:5)
Implement it with this snippet:
Then('my belly should sing', (BellyWorld world) {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),
```

Paste it into `bellyGlue` and implement it. Until it is implemented, `throw PendingException()` (or `pending()`)
marks the step as *pending*, which also fails the test. When the scenario passes, remove the `@wip` tag.

## Read the reports

With the `default` profile, a run prints the summary when it ends:

<!-- run in: packages/cucumber/fixtures/getting_started -->
```sh
dart test
```

<!-- output -->
```text
4 scenarios (4 passed)
12 steps (12 passed)
+4: All tests passed!
```

When something fails, the summary lists it with its steps, and it repeats the snippets for undefined steps. The run
also wrote the reports:

<!-- files in: packages/cucumber/fixtures/getting_started -->
```text
build/cucumber/messages.ndjson   one Cucumber Message per line
build/cucumber/report.html       open it in a browser
```

The HTML report is the one that the other Cucumber implementations produce. [Reports](reports.md) explains the
outputs, and how the reports of several test files and CI machines are merged.

## Next steps

- [Writing glue](writing-glue.md): parameter types, data tables, doc strings, hooks, attachments and more.
- [Configuration](configuration.md): every option, and how code, `cucumber.yaml` and `CUCUMBER_*` variables combine.
- [Running with `dart test`](package-test.md): what `dart test` and IDEs see.
- The [example project](../../packages/cucumber/example/) adds a custom parameter type, a typed data table, a doc
  string, a hook and a rule.
