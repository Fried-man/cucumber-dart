# cucumber_flutter

Cucumber for Flutter: run Gherkin `.feature` files as Flutter widget tests. Steps get the scenario's `WidgetTester`
through the World, and the reports are the [Cucumber Messages][messages] reports of [`cucumber`][cucumber]
(NDJSON, HTML and a console summary).

> **Status: pre-release.** `cucumber_flutter` is not on pub.dev, because `cucumber` and its dependencies are not
> published yet (see [Publishing][publishing]). Until then, depend on it from Git, as shown below. It needs
> Flutter 3.44 or later.

The [Flutter page of the guide][guide] explains how to write and run widget-test features, and what differs from
`dart test`. Everything else in the [guide][guide-home] (glue, configuration, reports) applies as well.

## Install

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

## Quick start

Write a feature, `features/todo.feature`:

```gherkin
Feature: To-do list
  Scenario: Adding an item
    Given the app is running
    When I add "Buy milk"
    Then I see "1 item left"
```

Define the steps with a World that extends `FlutterWorld`, whose `tester` is the scenario's `WidgetTester`:

```dart
// test/steps/todo_steps.dart
import 'package:cucumber_flutter/cucumber_flutter.dart';
import 'package:flutter/material.dart' hide DataTable;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/main.dart';

class TodoWorld extends FlutterWorld {}

final todoGlue = <Glue>[
  Given('the app is running', (TodoWorld w) async {
    await w.tester.pumpWidget(const TodoApp());
  }),
  When('I add {string}', (TodoWorld w, String title) async {
    await w.tester.enterText(find.byType(TextField), title);
    await w.tester.tap(find.byTooltip('Add'));
    await w.tester.pump();
  }),
  Then('I see {string}', (TodoWorld w, String text) {
    expect(find.text(text), findsOneWidget);
  }),
];
```

Declare the suite in a test file:

```dart
// test/cucumber_test.dart
import 'package:cucumber_flutter/cucumber_flutter.dart';

import 'steps/todo_steps.dart';

void main() => cucumberWidgets(
  features: ['features/'],
  world: TodoWorld.new,
  glue: todoGlue,
);
```

And run it:

```sh
flutter test
```

Each scenario is a widget test. The [example app][example] is a complete project.

## What it reuses

`package:cucumber_flutter/cucumber_flutter.dart` re-exports the API of `package:cucumber` (except its `cucumber()`
and `CucumberSuite`), so steps, hooks, parameter types, data tables, doc strings, attachments and plugins are the
same. `cucumberWidgets` takes the same options as `cucumber`, and reads `cucumber.yaml` and `CUCUMBER_*` variables
in the same way. The `message:` and `html:` reports of the test files of one `flutter test` run are merged into one.

## Differences from `dart test`

- **Locations.** `testWidgets` takes no location, so IDEs link a scenario to the `cucumberWidgets` call, not to its
  `.feature` line. Features, rules, outlines and examples (the groups) keep their `.feature` locations.
- **Flutter errors.** An exception that Flutter reports during a step or hook (for example while building a widget)
  fails that step or hook.
- **One tester per scenario.** Retries of a scenario use the same `WidgetTester` and widget tree.
- **Fake time.** Steps run in `testWidgets`' fake-async zone, so step timeouts count fake time, and real
  asynchronous work (files, sockets) needs `tester.runAsync`.
- **`BeforeAll` and `AfterAll`** run outside the widget tests and have no tester.

[cucumber]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber
[example]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber_flutter/example
[guide]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/guide/flutter.md
[guide-home]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/guide/README.md
[messages]: https://github.com/cucumber/messages
[publishing]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/design.md#141-publishing
