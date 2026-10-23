// Runs a feature through the engine with the SerialHost, the host that
// command-line runners and the compatibility kit harness use, and prints the
// result of each scenario.
//
//   dart run example/cucumber_core_example.dart
//
// Most projects do not use the engine directly: package:cucumber declares the
// scenarios as `dart test` tests and adds configuration and reports.
import 'package:cucumber_core/engine.dart';

/// The feature to run. Hosts usually read feature files from disk.
const bellyFeature = '''
Feature: Belly
  Scenario: a few cukes
    Given I have 42 cukes in my belly
    When I wait 1 hour
    Then my belly should growl

  Scenario: a song
    Given I have 3 cukes in my belly
    Then my belly should sing
''';

/// The World: fresh state for each scenario attempt.
class BellyWorld extends World {
  /// How many cucumbers have been eaten.
  int cukes = 0;

  /// How many hours have passed.
  int hours = 0;
}

/// The step definitions. `my belly should sing` is left undefined, so the
/// engine suggests a snippet for it.
final bellyGlue = <Glue>[
  Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) {
    w.cukes += cukes;
  }),
  When('I wait {int} hour(s)', (BellyWorld w, int hours) {
    w.hours += hours;
  }),
  Then('my belly should growl', (BellyWorld w) {
    if (w.cukes <= 10 || w.hours < 1) {
      throw StateError('Expected a growl after ${w.cukes} cukes');
    }
  }),
];

/// Plans and runs [bellyFeature]. [plugins] receive the Cucumber Messages.
Future<TestRunResult> runBellyFeature({List<Plugin> plugins = const []}) {
  final plan = SuitePlan.create(
    features: [const FeatureSource('features/belly.feature', bellyFeature)],
    glue: bellyGlue,
    world: BellyWorld.new,
    plugins: plugins,
  );
  return const SerialHost().run(plan);
}

Future<void> main() async {
  var messages = 0;
  final result = await runBellyFeature(
    plugins: [CallbackPlugin((_) => messages++)],
  );
  for (final testCase in result.testCases) {
    print('${testCase.status.name.toUpperCase()}: ${testCase.pickle.name}');
    for (final snippet in testCase.snippets) {
      print(snippet);
    }
  }
  print('Success: ${result.success} ($messages messages)');
}
