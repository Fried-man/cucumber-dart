# cucumber example

A complete project that runs [`features/belly.feature`](features/belly.feature) with `dart test`. It shows a typed
World, Cucumber Expressions with a custom parameter type, a typed data table, a doc string with an attachment, a
named hook, a rule, a scenario outline with two examples tables, tags, and the reports configured in
[`cucumber.yaml`](cucumber.yaml).

```sh
dart test                                # every scenario except @wip, one test each
dart test --tags smoke                   # scenarios tagged @smoke
CUCUMBER_FILTER_TAGS=@smoke dart test    # the same, selected by Cucumber
CUCUMBER_PROFILE=wip dart test           # only @wip: its step is undefined, so it fails and the summary suggests a snippet
```

`CUCUMBER_FILTER_TAGS` narrows the selection of the active profiles (the tag expressions are combined with `and`),
so `@wip` scenarios, which the `default` profile leaves out, are selected with the `wip` profile.

The reports are written to `build/cucumber/`: `messages.ndjson` (Cucumber Messages) and `report.html`.

The entry point, [`test/cucumber_test.dart`](test/cucumber_test.dart):

```dart
import 'package:cucumber/cucumber.dart';

import 'steps/belly_steps.dart';

void main() => cucumber(
  features: ['features/'],
  world: BellyWorld.new,
  glue: bellyGlue,
  worldParameters: {'greeting': 'Hi'},
);
```

An excerpt of the glue, [`test/steps/belly_steps.dart`](test/steps/belly_steps.dart):

```dart
class BellyWorld extends World {
  final belly = Belly();
}

final bellyGlue = <Glue>[
  ParameterType<Color>(
    'color',
    r'red|green|blue',
    (String name) => Color.values.byName(name),
  ),
  DataTableType<CukeOrder>.entry(
    (entry) => CukeOrder(
      Color.values.byName(entry['color']!),
      int.parse(entry['count']!),
    ),
  ),

  Before((BellyWorld w, Scenario s) {
    w.log('${w.parameters['greeting'] ?? 'Hello'}, ${s.name}!');
  }, name: 'greet'),

  Given('I have {int} {color} cukes in my belly', (
    BellyWorld w,
    int cukes,
    Color color,
  ) {
    w.belly.eat(cukes, color);
  }),
  Given('I eat these cukes:', (BellyWorld w, List<CukeOrder> orders) {
    for (final order in orders) {
      w.belly.eat(order.count, order.color);
    }
  }),
  Then('my belly should growl', (BellyWorld w) {
    expect(w.belly.isGrowling, isTrue);
  }),
  Then('the meal plan notes are:', (BellyWorld w, DocString notes) {
    w.attach(notes.content, mediaType: 'text/markdown');
  }),
];
```

In this repository the example is a pub workspace member (`resolution: workspace` in its `pubspec.yaml`). Outside
the repository, remove that line and depend on `cucumber` as described in the
[package README](../README.md#install).
