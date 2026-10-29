import 'dart:async';

import 'package:cucumber/cucumber.dart';
import 'package:flutter_test/flutter_test.dart';

/// The zone key of the [WidgetTester] of the running scenario.
final Object _testerKey = Object();

/// Runs [body] with [tester] as the scenario's [WidgetTester].
Future<void> runWithTester(WidgetTester tester, Future<void> Function() body) =>
    runZoned(body, zoneValues: {_testerKey: tester});

/// The [WidgetTester] of the running scenario, or `null` outside the
/// scenarios of a `cucumberWidgets` suite.
WidgetTester? get currentTester => Zone.current[_testerKey] as WidgetTester?;

/// Fails the running step or hook if Flutter reported an exception during
/// it: the exception taken from the [WidgetTester] is rethrown.
///
/// Outside a widget test, it does nothing.
void throwTakenException() {
  final exception = currentTester?.takeException();
  if (exception != null) throw exception as Object;
}

/// A World for widget tests: it gives steps and hooks the [WidgetTester] of
/// the running scenario (design §12).
///
/// Extend it, or mix it into a World that already has a superclass:
///
/// ```dart
/// class CounterWorld extends FlutterWorld {
///   Finder get count => find.byKey(const Key('count'));
/// }
///
/// final steps = <Glue>[
///   Given('the counter app is running', (CounterWorld w) async {
///     await w.tester.pumpWidget(const CounterApp());
///   }),
/// ];
/// ```
///
/// It has the same members as [World], which resolve the running scenario
/// through a zone value, so they work across `await`s.
abstract mixin class FlutterWorld implements World {
  static final World _world = DefaultWorld();

  /// The [WidgetTester] of the running scenario. Every attempt of a scenario
  /// (with `retry`) uses the same tester, and so the same widget tree.
  ///
  /// Throws a [StateError] outside the scenarios of a `cucumberWidgets`
  /// suite, for example in `BeforeAll` and `AfterAll` hooks.
  WidgetTester get tester =>
      currentTester ??
      (throw StateError(
        'FlutterWorld.tester can only be used while a scenario of a '
        'cucumberWidgets suite is running.',
      ));

  @override
  Map<String, Object?> get parameters => _world.parameters;

  @override
  Scenario get scenario => _world.scenario;

  @override
  void attach(Object data, {String? mediaType, String? fileName}) =>
      _world.attach(data, mediaType: mediaType, fileName: fileName);

  @override
  void log(String text) => _world.log(text);

  @override
  void link(String url, {String? title}) => _world.link(url, title: title);
}

/// The World of a `cucumberWidgets` suite without a `world` factory.
final class DefaultFlutterWorld with FlutterWorld {
  /// Creates a World.
  DefaultFlutterWorld();
}
