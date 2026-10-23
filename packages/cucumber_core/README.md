# cucumber_core

The runner-agnostic engine of [Cucumber for Dart][cucumber-dart]: the glue API (steps, hooks, parameter types, data
table and doc string types, World) and the engine that runs Gherkin pickles and emits [Cucumber Messages][messages].

**Most projects should depend on [`cucumber`][cucumber] instead.** It runs features with `dart test`, adds
configuration and reports, and re-exports this package's glue API, so test code never imports `cucumber_core`
directly.

Depend on `cucumber_core` to build a host: a runner for another test framework or a command-line runner, or the
future Flutter host. The engine is pure Dart. It does not use `dart:io`, `dart:mirrors`, Flutter or `package:test`,
and hosts provide the platform facts (clock, environment, feature file contents).

## Libraries

- `package:cucumber_core/cucumber_core.dart`: the glue API (`Given`, `When`, `Then`, hooks, `ParameterType`,
  `DataTableType`, `DocStringType`, `World`, `DataTable`, `DocString`, `pending`, `skip`, `attach`, `log`, `link`)
  and the `Plugin` interface.
- `package:cucumber_core/engine.dart`: the host API. `SuitePlan` parses features, loads glue, and filters and orders
  pickles into a tree that a host declares; `SerialHost` runs a plan directly.

## Usage

```dart
import 'package:cucumber_core/engine.dart';

class BellyWorld extends World {
  int cukes = 0;
}

final glue = <Glue>[
  Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) {
    w.cukes += cukes;
  }),
];

Future<void> main() async {
  final plan = SuitePlan.create(
    features: [
      const FeatureSource('features/belly.feature', '''
Feature: Belly
  Scenario: a few cukes
    Given I have 42 cukes in my belly
'''),
    ],
    glue: glue,
    world: BellyWorld.new,
    plugins: [CallbackPlugin((envelope) => print(envelope.toJson()))],
  );
  final result = await const SerialHost().run(plan);
  print('Success: ${result.success}');
}
```

[`example/cucumber_core_example.dart`](example/cucumber_core_example.dart) also prints each scenario's status and
the snippet for an undefined step.

## Conformance

The engine passes 47 of the 49 [Cucumber Compatibility Kit][cck] samples. `markdown` is skipped because
`cucumber_gherkin` has no Markdown support, and `test-run-exception` because it depends on a switch of the
reference implementation. The private tag-expression evaluator passes the shared
[cucumber/tag-expressions][tag-expressions] test data.

See the [design](https://github.com/Fried-man/cucumber-dart/blob/main/docs/design.md) for the execution semantics,
the messages and the mapping to hosts.

[cucumber-dart]: https://github.com/Fried-man/cucumber-dart
[cucumber]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber
[messages]: https://github.com/cucumber/messages
[cck]: https://github.com/cucumber/compatibility-kit
[tag-expressions]: https://github.com/cucumber/tag-expressions
