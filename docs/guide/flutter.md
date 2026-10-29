# Widget tests with Flutter

[`cucumber_flutter`](../../packages/cucumber_flutter/) runs `.feature` files as Flutter widget tests: each scenario
is a `testWidgets` test, and its steps drive the app through the test's `WidgetTester`. Everything else works as
with `dart test`: [glue](writing-glue.md), [configuration](configuration.md), [reports](reports.md), and how
features become [tests and groups](package-test.md#tests-and-groups). This page describes what is specific to
Flutter. The examples come from the [example app](../../packages/cucumber_flutter/example/), a small to-do list.

`cucumber_flutter` needs Flutter 3.44 or later. Widget tests run on the host, under `flutter test`; running features
on a device with `integration_test` is planned ([design §12](../design.md#12-flutter-roadmap-post-v1-adr-0004)).

## Install

`cucumber_flutter` is not on pub.dev yet. Depend on it from Git, and override the packages it depends on that are not
published either:

<!-- checked: flutter-install -->
```yaml
# pubspec.yaml
dev_dependencies:
  cucumber_flutter:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_flutter}
  flutter_test:
    sdk: flutter

# Until cucumber's dependencies are on pub.dev:
dependency_overrides:
  cucumber:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber}
  cucumber_core:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_core}
  cucumber_ci_environment:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_ci_environment}
  cucumber_html_formatter:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_html_formatter}
  cucumber_query:
    git: {url: https://github.com/Fried-man/cucumber-dart, path: packages/cucumber_query}
```

`package:cucumber_flutter/cucumber_flutter.dart` is the only Cucumber import a suite needs: it re-exports the API
of `package:cucumber`, except `cucumber()` and `CucumberSuite`.

## Write the steps

The features are plain Gherkin, in `features/` by default:

<!-- excerpt: packages/cucumber_flutter/example/features/todo.feature -->
```gherkin
Feature: To-do list
  Keep track of what is left to do.

  Background:
    Given the app is running

  Scenario: Adding an item
    When I add "Buy milk"
    Then the list shows:
      | Buy milk |
    And I see "1 item left"

  Scenario: Completing an item
    Given the list has:
      | Buy milk     |
      | Walk the dog |
    When I complete "Buy milk"
    Then I see "1 item left"

  @smoke
  Scenario: An empty item is not added
    When I add ""
    Then the list is empty

  Scenario Outline: Counting what is left
    When I add <count> items
    Then I see "<left>"

    Examples:
      | count | left         |
      | 1     | 1 item left  |
      | 3     | 3 items left |
```

The World extends `FlutterWorld`, whose `tester` is the `WidgetTester` of the running scenario. Steps use it as in
any widget test, with the finders and matchers of `flutter_test`:

<!-- excerpt: packages/cucumber_flutter/example/test/steps/todo_steps.dart -->
```dart
import 'package:cucumber_flutter/cucumber_flutter.dart';
import 'package:cucumber_flutter_example/main.dart';
import 'package:flutter/material.dart' hide DataTable;
import 'package:flutter_test/flutter_test.dart';

/// The state of one scenario attempt: FlutterWorld adds the WidgetTester.
class TodoWorld extends FlutterWorld {
  /// Types [title] into the field and taps the add button.
  Future<void> add(String title) async {
    await tester.enterText(find.byKey(const Key('new-todo')), title);
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
  }
}

final todoGlue = <Glue>[
  Given('the app is running', (TodoWorld w) async {
    await w.tester.pumpWidget(const TodoApp());
  }),
  Given('the list has:', (TodoWorld w, List<String> titles) async {
    for (final title in titles) {
      await w.add(title);
    }
  }),
  When('I add {string}', (TodoWorld w, String title) => w.add(title)),
  When('I add {int} items', (TodoWorld w, int count) async {
    for (var i = 1; i <= count; i++) {
      await w.add('Item $i');
    }
  }),
  When('I complete {string}', (TodoWorld w, String title) async {
    await w.tester.tap(find.widgetWithText(CheckboxListTile, title));
    await w.tester.pump();
  }),
  Then('the list shows:', (TodoWorld w, List<String> titles) {
    final tiles = w.tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect([for (final tile in tiles) (tile.title! as Text).data], titles);
  }),
  Then('the list is empty', (TodoWorld w) {
    expect(find.byType(CheckboxListTile), findsNothing);
  }),
  Then('I see {string}', (TodoWorld w, String text) {
    expect(find.text(text), findsOneWidget);
  }),
  After((TodoWorld w, Scenario s) {
    if (s.isFailed) w.log(w.tester.allWidgets.take(30).join('\n'));
  }),
];
```

Material has a `DataTable` widget, which clashes with Cucumber's `DataTable`: hide one of them, as above.

## Declare the suite

`cucumberWidgets` takes the same options as `cucumber` ([Configuration](configuration.md#options)):

<!-- excerpt: packages/cucumber_flutter/example/test/cucumber_test.dart -->
```dart
// Runs the features as widget tests: flutter test
import 'package:cucumber_flutter/cucumber_flutter.dart';

import 'steps/todo_steps.dart';

void main() => cucumberWidgets(
  features: ['features/'],
  world: TodoWorld.new,
  glue: todoGlue,
);
```

`CucumberWidgetSuite<W>(CucumberOptions(...)).declare()` is the same, for options shared between entry files
([Sharing glue between entry files](writing-glue.md#sharing-glue-between-entry-files)). Without a `world`, each
scenario attempt gets a `DefaultFlutterWorld`, and steps can take a `FlutterWorld`.

## Run it

<!-- run in: packages/cucumber_flutter/example -->
```sh
flutter test
```

<!-- output -->
```text
To-do list Adding an item
To-do list Completing an item
To-do list An empty item is not added
To-do list Counting what is left Examples Example #1.1
To-do list Counting what is left Examples Example #1.2
5 scenarios (5 passed)
17 steps (17 passed)
All tests passed!
```

`flutter test`'s options select scenarios as `dart test`'s do ([Tags](package-test.md#tags),
[Filtering](package-test.md#filtering)):

<!-- run in: packages/cucumber_flutter/example -->
```sh
flutter test --tags smoke
flutter test --plain-name "Adding an item"
```

## The World and the tester

- **Extend or mix in.** `class TodoWorld extends FlutterWorld` is the usual form. A World that already has a
  superclass mixes it in: `class TodoWorld extends AppState with FlutterWorld`. Either way the World also has the
  members of `World`: `parameters`, `scenario`, `attach`, `log` and `link`.
- **One tester per scenario.** Each scenario is one widget test, so its steps and its `Before`, `After`,
  `BeforeStep` and `AfterStep` hooks share one tester and one widget tree. The next scenario starts with an empty
  tree. With `retry`, every attempt gets a new World, but the same tester and the widget tree that the failed attempt
  left, so start each scenario with `pumpWidget`, as the `Background` above does.
- **Test-run hooks.** `BeforeAll` and `AfterAll` run outside the widget tests (in `setUpAll` and `tearDownAll`), so
  they have no tester: `tester` throws a `StateError` there.
- **Flutter errors fail the step.** Flutter catches the exceptions thrown while building, laying out or painting
  widgets, and reports them to the test. An exception reported during a step or hook fails that step or hook, with
  that exception, and the scenario's remaining steps are skipped.

## Fake time and real asynchronous work

`testWidgets` runs each test in a fake-async zone, and so do the steps:

- Timers and animations only advance when the step calls `tester.pump(duration)` or `tester.pumpAndSettle()`.
- A step's `timeout:` counts fake time, so it only expires while the step pumps.
- Real asynchronous work, such as reading a file or using a socket, does not complete in that zone. Wrap it in
  `tester.runAsync(...)`, as in any widget test. `attachFile` reads synchronously, so it works in steps.
- The scenario's test timeout is `testWidgets`' (`scenarioTimeout` changes it,
  [Configuration](configuration.md#timeouts)).

## Reports

The reports are those of `dart test` ([Reports](reports.md)), configured in code, in `cucumber.yaml` or with
`CUCUMBER_PLUGIN`:

<!-- excerpt: packages/cucumber_flutter/example/cucumber.yaml -->
```yaml
# Reports of flutter test, merged across the test files of a run.
default:
  plugins:
    - message:build/cucumber/messages.ndjson
    - html:build/cucumber/report.html
    - summary
```

<!-- files in: packages/cucumber_flutter/example -->
```text
build/cucumber/messages.ndjson
build/cucumber/report.html
```

`flutter test` runs each test file in its own process, not in isolates of one process as `dart test` does. The
`message:` and `html:` reports of the entry files of one run are still merged into one: when `CUCUMBER_RUN_ID` is not
set, the run is identified by the font configuration file that `flutter test` creates for each run and passes to
every test process. On CI, setting `CUCUMBER_RUN_ID` to the CI run's ID does not depend on that, and is needed
anyway to [merge the reports of shards](reports.md#merging-ci-shards) with `dart run cucumber:merge`.

## Differences from `dart test`

| | `dart test` (`cucumber`) | `flutter test` (`cucumberWidgets`) |
|---|---|---|
| Each scenario is a | `test` | `testWidgets` test, with a `WidgetTester` in the World |
| Test locations | The scenario's `.feature` line | `testWidgets` takes no location, so IDEs link a scenario to the `cucumberWidgets` call; features, rules, outlines and examples (the groups) keep their `.feature` lines |
| Errors reported by Flutter | n/a | Fail the step or hook during which they were reported |
| Time | Real | Fake, inside each scenario |
| Entry files run in | Isolates of one process | One process each; their reports are still merged |

Failure messages name the scenario's and the step's `.feature` lines in both cases. A Flutter project can also use
`cucumber()` from `package:cucumber` for features that need no widgets; its scenarios keep their locations.
