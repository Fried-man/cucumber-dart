import '../status.dart';

/// The scenario currently running (design §4.4).
///
/// `Before` and `After` hooks can receive it, and `World.scenario` returns it.
abstract interface class Scenario {
  /// The pickle ID.
  String get id;

  /// The scenario name (with outline parameters substituted).
  String get name;

  /// The feature file URI.
  String get uri;

  /// The line of the scenario, or of the example row for outlines.
  int get line;

  /// The tags, including inherited ones, with their `@`.
  List<String> get tags;

  /// The Gherkin language of the feature file.
  String get language;

  /// The attempt number, starting at 0 (see retries).
  int get attempt;

  /// The most severe status so far. In `After` hooks, this is the scenario's
  /// status before the hook.
  Status get status;

  /// Whether a step or hook has failed so far.
  bool get isFailed;

  /// The error of the first failed step or hook, if any.
  Object? get error;

  /// Attaches [data] (a `String` or a `List<int>`) to the current step.
  void attach(Object data, {String? mediaType, String? fileName});

  /// Attaches [text] as a log message to the current step.
  void log(String text);

  /// Attaches a link to [url] to the current step.
  void link(String url, {String? title});
}

/// The step around which a `BeforeStep` or `AfterStep` hook runs.
abstract interface class Step {
  /// The scenario the step belongs to.
  Scenario get scenario;

  /// The step text (with outline parameters substituted).
  String get text;

  /// The keyword, such as `'Given '`.
  String get keyword;

  /// The line of the step.
  int get line;

  /// The step's status. In `AfterStep` hooks, this is the step's result.
  Status get status;

  /// The step's error, if it failed.
  Object? get error;
}

/// The test run, which `BeforeAll` and `AfterAll` hooks can receive.
abstract interface class TestRun {
  /// The world parameters. `BeforeAll` hooks may change them; every scenario
  /// attempt gets a deep copy.
  Map<String, Object?> get parameters;

  /// Attaches [data] to the current test-run hook.
  void attach(Object data, {String? mediaType, String? fileName});

  /// Attaches [text] as a log message to the current test-run hook.
  void log(String text);

  /// Attaches a link to [url] to the current test-run hook.
  void link(String url, {String? title});
}
