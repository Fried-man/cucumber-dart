# cucumber_flutter example

A small to-do app, [`lib/main.dart`](lib/main.dart), whose behaviour is described in
[`features/todo.feature`](features/todo.feature). `flutter test` runs each scenario as a widget test. The example
shows a World that extends `FlutterWorld`, steps that drive the app through its `WidgetTester`, a single-column data
table, a scenario outline, a tag, an `After` hook that logs the widget tree of a failed scenario, and the reports
configured in [`cucumber.yaml`](cucumber.yaml).

```sh
flutter test                  # every scenario, one widget test each
flutter test --tags smoke     # scenarios tagged @smoke
```

The reports are written to `build/cucumber/`: `messages.ndjson` (Cucumber Messages) and `report.html`.

The entry point, [`test/cucumber_test.dart`](test/cucumber_test.dart):

```dart
import 'package:cucumber_flutter/cucumber_flutter.dart';

import 'steps/todo_steps.dart';

void main() => cucumberWidgets(
  features: ['features/'],
  world: TodoWorld.new,
  glue: todoGlue,
);
```

The app has no platform folders, because widget tests do not need them; `flutter create .` adds them to run the app.

In this repository the example belongs to the pub workspace of `packages/cucumber_flutter`
(`resolution: workspace` in its `pubspec.yaml`). Outside the repository, remove that line and depend on
`cucumber_flutter` as described in the [package README](../README.md#install).
