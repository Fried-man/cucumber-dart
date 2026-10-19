import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../status.dart';

/// The result of a test step or test-run hook.
final class StepResult {
  /// Creates a result.
  const StepResult({
    required this.status,
    required this.duration,
    required this.description,
    required this.location,
    this.error,
    this.stackTrace,
    this.message,
    this.snippet,
    this.isHook = false,
  });

  /// The status.
  final Status status;

  /// How long it ran.
  final Duration duration;

  /// What ran: `Given I have 3 cukes` or `Before hook "name"`.
  final String description;

  /// Where it is defined: `features/belly.feature:12` for steps, the glue
  /// source reference for hooks.
  final String location;

  /// The error, for failed results.
  final Object? error;

  /// The stack trace of [error].
  final StackTrace? stackTrace;

  /// An explanation, for pending, skipped, undefined and ambiguous results.
  final String? message;

  /// A Dart snippet implementing the step, for undefined steps.
  final String? snippet;

  /// Whether this is a hook rather than a pickle step.
  final bool isHook;

  @override
  String toString() => '${status.name.toUpperCase()} $description ($location)';
}

/// The result of running a pickle, as reported to hosts (design §6).
final class TestCaseResult {
  /// Creates a result.
  const TestCaseResult({
    required this.pickle,
    required this.status,
    required this.attempts,
    required this.steps,
    this.notRunReason,
  });

  /// Creates the result of a pickle that did not run, because of [reason].
  TestCaseResult.notRun(this.pickle, String reason)
    : status = Status.skipped,
      attempts = 0,
      steps = const [],
      notRunReason = reason;

  /// The pickle.
  final messages.Pickle pickle;

  /// The status of the final attempt.
  final Status status;

  /// How many attempts ran.
  final int attempts;

  /// The step results of the final attempt, hooks included.
  final List<StepResult> steps;

  /// Why the pickle did not run (for example, a failed `BeforeAll` hook), or
  /// `null` when it ran.
  final String? notRunReason;

  /// Whether the pickle ran.
  bool get ran => notRunReason == null;

  /// Whether this result fails the run (strict mode, design §5.7).
  bool get isFailure => status.isFailedish;

  /// The first step whose status is the test case's status.
  StepResult? get decisiveStep {
    for (final step in steps) {
      if (step.status == status) return step;
    }
    return null;
  }

  /// The snippets for undefined steps, without duplicates.
  List<String> get snippets => [
    ...{for (final step in steps) ?step.snippet},
  ];
}

/// The result of a test run.
final class TestRunResult {
  /// Creates a result.
  const TestRunResult({
    required this.success,
    required this.testCases,
    required this.hooks,
    this.error,
  });

  /// Whether the run succeeded: no final attempt ended PENDING, UNDEFINED,
  /// AMBIGUOUS or FAILED, no test-run hook failed and no feature file failed
  /// to parse.
  final bool success;

  /// The results of the pickles that ran, in run order.
  final List<TestCaseResult> testCases;

  /// The results of the `BeforeAll` and `AfterAll` hooks, in run order.
  final List<StepResult> hooks;

  /// An internal error that ended the run, if any.
  final Object? error;
}
