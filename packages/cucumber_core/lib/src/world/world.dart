import 'context.dart';
import 'scenario.dart';

/// Scenario state shared by steps and hooks (design §4.3, ADR-0003).
///
/// The suite creates a new World for every scenario attempt. Steps, hooks and
/// parameter type transformers receive it as their optional first parameter.
/// Any class can be the World; extending or mixing in this class only adds
/// these convenience members:
///
/// ```dart
/// class BellyWorld extends World {
///   final belly = Belly();
/// }
/// ```
///
/// The members resolve the running scenario through a zone value, so they work
/// across `await`s inside steps, hooks and transformers. Elsewhere they throw a
/// [StateError].
abstract mixin class World {
  /// The world parameters: a deep copy for the current attempt.
  Map<String, Object?> get parameters =>
      _scenarioContext('World.parameters').parameters;

  /// The scenario currently running.
  Scenario get scenario => _scenarioContext('World.scenario').scenario;

  /// Attaches [data] (a `String` or a `List<int>`) to the current step.
  void attach(Object data, {String? mediaType, String? fileName}) =>
      requireContext(
        'World.attach',
      ).attach(data, mediaType: mediaType, fileName: fileName);

  /// Attaches [text] as a log message to the current step.
  void log(String text) => requireContext('World.log').log(text);

  /// Attaches a link to [url] to the current step.
  void link(String url, {String? title}) =>
      requireContext('World.link').link(url, title: title);
}

/// The World used when a suite does not specify one.
final class DefaultWorld with World {
  /// Creates a World.
  DefaultWorld();
}

/// Implemented by the context of a running scenario attempt.
abstract class ScenarioExecutionContext extends ExecutionContext {
  /// The scenario.
  Scenario get scenario;

  /// The world parameters for this attempt.
  Map<String, Object?> get parameters;
}

ScenarioExecutionContext _scenarioContext(String member) {
  final context = currentContext;
  if (context is ScenarioExecutionContext) return context;
  throw StateError('$member can only be used while a scenario is running.');
}

/// Attaches [data] to the current step or test-run hook.
///
/// [data] is a `String` (attached as-is, `text/plain` by default) or a
/// `List<int>` (Base64-encoded, `application/octet-stream` by default).
///
/// Throws a [StateError] outside a scenario or test-run hook.
void attach(Object data, {String? mediaType, String? fileName}) =>
    requireContext(
      'attach()',
    ).attach(data, mediaType: mediaType, fileName: fileName);

/// Attaches [text] as a log message to the current step or test-run hook.
///
/// This clashes with `log` from `dart:math`; use `import 'dart:math' hide log;`
/// or a prefix.
void log(String text) => requireContext('log()').log(text);

/// Attaches a link to [url], with an optional [title], to the current step or
/// test-run hook.
void link(String url, {String? title}) =>
    requireContext('link()').link(url, title: title);
