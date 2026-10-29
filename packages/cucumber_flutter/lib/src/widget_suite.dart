import 'package:cucumber/cucumber.dart';
import 'package:cucumber/hosting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flutter_world.dart';

/// Declares a Cucumber suite as Flutter widget tests (design §12).
///
/// ```dart
/// // test/cucumber_test.dart  →  flutter test
/// import 'package:cucumber_flutter/cucumber_flutter.dart';
///
/// void main() => cucumberWidgets(
///   features: ['features/'],
///   world: CounterWorld.new,
///   glue: counterGlue,
/// );
/// ```
///
/// This is shorthand for
/// `CucumberWidgetSuite<W>(CucumberOptions(...)).declare()`; the options are
/// those of `cucumber()` in `package:cucumber` (see [CucumberOptions]), and
/// `cucumber.yaml` and `CUCUMBER_*` environment variables take precedence
/// over them in the same way.
void cucumberWidgets<W extends Object>({
  required List<Glue> glue,
  W Function()? world,
  List<String>? features,
  String? tags,
  List<String>? names,
  int? retry,
  String? order,
  bool? dryRun,
  Map<String, Object?>? worldParameters,
  List<Object>? plugins,
  String? suiteName,
  String? profile,
  bool? mapTags,
  Timeout? scenarioTimeout,
}) => CucumberWidgetSuite<W>(
  CucumberOptions(
    glue: glue,
    world: world,
    features: features,
    tags: tags,
    names: names,
    retry: retry,
    order: order,
    dryRun: dryRun,
    worldParameters: worldParameters,
    plugins: plugins,
    suiteName: suiteName,
    profile: profile,
    mapTags: mapTags,
    scenarioTimeout: scenarioTimeout,
  ),
).declare();

/// A Cucumber suite of widget tests whose World type is [W].
///
/// [W] is the type created by [CucumberOptions.world]; [cucumberWidgets]
/// infers it from its `world` argument. Without a `world`, each scenario
/// attempt gets a [DefaultFlutterWorld], and steps and hooks can take a
/// [FlutterWorld].
final class CucumberWidgetSuite<W extends Object> {
  /// Creates a suite with [options].
  CucumberWidgetSuite(this.options);

  /// The options given in code.
  final CucumberOptions options;

  /// Declares the suite in the current test scope, synchronously, so call it
  /// directly from `main()` (or a `group` body).
  ///
  /// It declares the same groups, `setUpAll` and `tearDownAll` as the
  /// `dart test` host of `package:cucumber`, and writes the same reports,
  /// but declares each scenario (or example row) with [testWidgets]:
  ///
  /// - steps and hooks run inside the widget test, so [FlutterWorld.tester]
  ///   gives them its [WidgetTester];
  /// - an exception that Flutter reports during a step or hook (for example,
  ///   while building a widget) fails that step or hook;
  /// - the test reports the scenario's final attempt, as under `dart test`.
  ///
  /// `testWidgets` does not take a location, so the scenarios' tests point
  /// at this call rather than at their `.feature` lines. Their groups keep
  /// their `.feature` locations.
  void declare() {
    if (options.world == null) {
      _declare<FlutterWorld>(DefaultFlutterWorld.new);
    } else {
      _declare<W>(null);
    }
  }

  void _declare<V extends Object>(V Function()? defaultWorld) =>
      declareCucumberSuite<V>(
        options,
        defaultWorld: defaultWorld,
        // testWidgets cannot take the scenario's location.
        declareScenario: (name, body, {required location, tags, timeout}) =>
            testWidgets(
              name,
              (tester) => runWithTester(tester, body),
              tags: tags,
              timeout: timeout,
            ),
        afterUserCode: throwTakenException,
      );
}
