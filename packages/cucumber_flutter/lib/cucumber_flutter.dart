/// Cucumber for Flutter: runs Gherkin `.feature` files as Flutter widget
/// tests.
///
/// This is the only library a widget-test suite needs besides
/// `package:flutter_test`. It re-exports the glue API of `package:cucumber`
/// (steps, hooks, types, World, tables, attachments, reports) and adds
/// [cucumberWidgets], which declares each scenario with `testWidgets`, and
/// [FlutterWorld], which gives steps the scenario's `WidgetTester`.
///
/// Define the steps with a World that extends (or mixes in) [FlutterWorld]:
///
/// ```dart
/// // test/steps/counter_steps.dart
/// import 'package:cucumber_flutter/cucumber_flutter.dart';
/// import 'package:flutter/material.dart' hide DataTable;
/// import 'package:flutter_test/flutter_test.dart';
///
/// class CounterWorld extends FlutterWorld {}
///
/// final counterGlue = <Glue>[
///   Given('the counter shows {int}', (CounterWorld w, int count) async {
///     await w.tester.pumpWidget(MaterialApp(home: Text('$count')));
///   }),
///   When('I tap the {string} button', (CounterWorld w, String tooltip) async {
///     await w.tester.tap(find.byTooltip(tooltip));
///     await w.tester.pump();
///   }),
///   Then('I see {string}', (CounterWorld w, String text) {
///     expect(find.text(text), findsOneWidget);
///   }),
/// ];
/// ```
///
/// Then declare the suite in a test file and run `flutter test`:
///
/// ```dart
/// // test/cucumber_test.dart
/// import 'package:cucumber_flutter/cucumber_flutter.dart';
///
/// import 'steps/counter_steps.dart';
///
/// void main() => cucumberWidgets(
///   features: ['features/'],
///   world: CounterWorld.new,
///   glue: counterGlue,
/// );
/// ```
///
/// ## Suites
///
/// [cucumberWidgets] takes the options of `package:cucumber`'s `cucumber()`
/// and is shorthand for [CucumberWidgetSuite] with [CucumberOptions].
/// Configuration (`cucumber.yaml`, `CUCUMBER_*` variables), feature
/// discovery, the test groups, outcomes and reports work as under
/// `dart test`. Each scenario runs inside its own widget test:
///
/// - [FlutterWorld.tester] is the scenario's `WidgetTester`; without a
///   `world` factory, each attempt gets a [DefaultFlutterWorld];
/// - an exception that Flutter reports during a step or hook fails it;
/// - `BeforeAll` and `AfterAll` hooks run outside the widget tests, so they
///   have no tester.
///
/// `flutter_test` does not let tests declare their location, so IDEs link
/// each scenario to the `cucumberWidgets` call instead of its `.feature`
/// line. See the
/// [guide](https://github.com/Fried-man/cucumber-dart/blob/main/docs/guide/flutter.md)
/// for the other differences from `dart test`.
library;

export 'package:cucumber/cucumber.dart' hide CucumberSuite, cucumber;

export 'src/flutter_world.dart' show DefaultFlutterWorld, FlutterWorld;
export 'src/widget_suite.dart' show CucumberWidgetSuite, cucumberWidgets;
