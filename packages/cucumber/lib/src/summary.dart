import 'package:cucumber_core/engine.dart' show Plugin, SnippetGenerator;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:cucumber_query/cucumber_query.dart';

/// Prints a summary of the run when the suite ends (design §8.2, ADR-0009).
/// Its plugin specification is `summary`.
///
/// The summary is [formatSummary] of the messages the plugin received:
/// failures and warnings with their locations, the scenario and step counts,
/// the duration, and the Dart snippets for undefined steps. Under `dart test`
/// it is printed from `tearDownAll`, so the test reporter shows it.
///
/// A suite whose tests are all filtered out never starts its run, so it
/// prints nothing.
final class SummaryPlugin implements Plugin {
  /// Creates a plugin that writes the summary with [output] (default:
  /// [print]).
  SummaryPlugin({void Function(String summary)? output})
    : _output = output ?? print;

  final void Function(String summary) _output;
  final Query _query = Query();
  bool _received = false;

  @override
  void onMessage(messages.Envelope envelope) {
    _received = true;
    _query.update(envelope);
  }

  @override
  void close() {
    if (!_received) return;
    _received = false;
    _output(formatSummary(_query));
  }

  @override
  String toString() => 'summary';
}

/// [formatSummary] of [envelopes].
String formatSummaryOf(Iterable<messages.Envelope> envelopes) {
  final query = Query();
  envelopes.forEach(query.update);
  return formatSummary(query);
}

/// Summarises the messages indexed by [query] for people, following
/// cucumber-js's summary formatter (design §8.2):
///
/// ```text
/// Failures:
///
/// 1) Scenario: Shop - failing (attempt 2) # features/shop.feature:12
///    PASSED  Given a shop # features/shop.feature:6
///    FAILED  When a step fails with "boom" # features/shop.feature:14
///              Bad state: boom
///    SKIPPED Then a step passes # features/shop.feature:15
///
/// Warnings:
///
/// 1) Scenario: Shop - failing (attempt 1, retried) # features/shop.feature:12
///    ...
///
/// 5 scenarios (1 failed, 1 undefined, 3 passed)
/// 23 steps (1 failed, 1 undefined, 2 skipped, 19 passed)
/// 0m00.120s (executing steps: 0m00.085s)
///
/// You can implement missing steps with the snippets below:
///
/// Given('an undefined step', () {
///   ...
/// }),
/// ```
///
/// - **Undefined parameter types** come first, as in cucumber-js.
/// - **Failures** are what fails the run (design §5.7): final attempts that
///   ended FAILED, AMBIGUOUS, UNDEFINED or PENDING, and failed test run
///   hooks. Unlike cucumber-js, which is not strict-only, PENDING is a
///   failure.
/// - **Warnings** are the other non-passing scenarios: attempts that will be
///   retried and final attempts that ended SKIPPED.
/// - Each scenario is named with the long naming strategy of
///   `cucumber_query`, located at its `uri:line`, and lists its steps and
///   non-passing hooks.
/// - **Counts** cover final attempts only. Scenarios are counted by their
///   most severe step status, steps are the pickle steps (not hooks), and
///   statuses are listed from the most to the least severe.
/// - **Duration**: the test run, then the sum of all test step durations
///   (retried attempts and hooks included). Left out while the run has not
///   finished.
/// - **Snippets** for undefined steps come from the `suggestion` messages.
///   Each suggestion is presented as one snippet (the other expressions as
///   comments, design §7.5) and duplicates are left out.
///
/// This is a pure function of the messages, so a merged report can reuse it
/// (design §8.4).
String formatSummary(Query query) => _SummaryFormatter(query).format();

typedef _Status = messages.TestStepResultStatus;

/// Statuses in reporting order: the most severe first (cucumber-js), with
/// UNKNOWN (which cucumber-js does not list) last.
const List<_Status> _reportOrder = [
  _Status.failed,
  _Status.ambiguous,
  _Status.undefined,
  _Status.pending,
  _Status.skipped,
  _Status.passed,
  _Status.unknown,
];

/// Statuses that fail the run (design §5.7).
const Set<_Status> _failing = {
  _Status.failed,
  _Status.ambiguous,
  _Status.undefined,
  _Status.pending,
};

final NamingStrategy _naming = namingStrategy(NamingStrategyLength.long);

final class _SummaryFormatter {
  _SummaryFormatter(this.query);

  final Query query;

  /// Snippets for undefined steps, in order of first appearance.
  final Set<String> _snippets = {};

  String format() {
    // The final (or current) attempt of each test case, in run order.
    final finalAttempts = query.findAllTestCaseStarted();
    final retried = _retriedAttemptsByTestCaseId();

    final failures = <String Function(String)>[];
    final warnings = <String Function(String)>[];
    final hooks = query.findAllTestRunHookFinished();
    bool isAfterAll(messages.TestRunHookFinished hook) =>
        query.findHookBy(hook)?.type == messages.HookType.afterTestRun;
    void addHooks({required bool afterAll}) {
      for (final hook in hooks) {
        if (isAfterAll(hook) == afterAll &&
            _failing.contains(hook.result.status)) {
          failures.add((prefix) => _formatTestRunHook(prefix, hook));
        }
      }
    }

    addHooks(afterAll: false);
    final scenarioCounts = <_Status, int>{};
    final stepCounts = <_Status, int>{};
    for (final attempt in finalAttempts) {
      for (final earlier
          in retried[attempt.testCaseId] ??
              const <messages.TestCaseStarted>[]) {
        warnings.add(
          (prefix) => _formatAttempt(prefix, earlier, willBeRetried: true),
        );
      }
      final status = _statusOf(attempt);
      _increment(scenarioCounts, status);
      for (final (finished, testStep)
          in query.findTestStepFinishedAndTestStepBy(attempt)) {
        if (_isPickleStep(testStep)) {
          _increment(stepCounts, finished.testStepResult.status);
        }
      }
      if (_failing.contains(status)) {
        failures.add(
          (prefix) => _formatAttempt(prefix, attempt, willBeRetried: false),
        );
      } else if (status == _Status.skipped) {
        warnings.add(
          (prefix) => _formatAttempt(prefix, attempt, willBeRetried: false),
        );
      }
    }
    addHooks(afterAll: true);

    for (final attempt in finalAttempts) {
      _collectSnippets(attempt);
    }

    final sections = [
      ?_formatUndefinedParameterTypes(),
      ?_formatIssues('Failures', failures),
      ?_formatIssues('Warnings', warnings),
      [
        _formatCounts('scenario', scenarioCounts),
        _formatCounts('step', stepCounts),
        ?_formatDuration(),
      ].join('\n'),
      if (_snippets.isNotEmpty)
        'You can implement missing steps with the snippets below:\n\n'
            '${_snippets.join('\n\n')}',
    ];
    return sections.join('\n\n');
  }

  /// The attempts that will be retried, in attempt order, by test case ID.
  Map<String, List<messages.TestCaseStarted>> _retriedAttemptsByTestCaseId() {
    final seen = <String>{};
    final byTestCaseId = <String, List<messages.TestCaseStarted>>{};
    for (final finished in query.findAllTestStepFinished()) {
      final attempt = query.findTestCaseStartedBy(finished);
      if (attempt == null || !seen.add(attempt.id)) continue;
      if (query.findTestCaseFinishedBy(attempt)?.willBeRetried ?? false) {
        byTestCaseId.putIfAbsent(attempt.testCaseId, () => []).add(attempt);
      }
    }
    for (final attempts in byTestCaseId.values) {
      attempts.sort((a, b) => a.attempt.compareTo(b.attempt));
    }
    return byTestCaseId;
  }

  /// The most severe status of [attempt]'s steps. An attempt without steps
  /// passed once it finished (as in cucumber-js and the core).
  _Status _statusOf(messages.TestCaseStarted attempt) {
    final result = query.findMostSevereTestStepResultBy(attempt);
    if (result != null) return result.status;
    return query.findTestCaseFinishedBy(attempt) == null
        ? _Status.unknown
        : _Status.passed;
  }

  static bool _isPickleStep(messages.TestStep testStep) =>
      testStep.pickleStepId?.isNotEmpty ?? false;

  static void _increment(Map<_Status, int> counts, _Status status) =>
      counts[status] = (counts[status] ?? 0) + 1;

  /// `Undefined parameter types:` and a line per name (the latest
  /// expression wins), as in cucumber-js.
  String? _formatUndefinedParameterTypes() {
    final byName = <String, messages.UndefinedParameterType>{
      for (final type in query.findAllUndefinedParameterTypes())
        type.name: type,
    };
    if (byName.isEmpty) return null;
    return 'Undefined parameter types:\n\n'
        '${byName.values.map((t) => '- "${t.name}" e.g. `${t.expression}`').join('\n')}';
  }

  static String? _formatIssues(
    String title,
    List<String Function(String prefix)> issues,
  ) {
    if (issues.isEmpty) return null;
    return '$title:\n\n'
        '${[for (final (i, issue) in issues.indexed) issue('${i + 1}) ')].join('\n\n')}';
  }

  /// A scenario attempt: its name and location, then its steps (with the
  /// messages of non-passing ones) and its non-passing hooks.
  String _formatAttempt(
    String prefix,
    messages.TestCaseStarted attempt, {
    required bool willBeRetried,
  }) {
    final pickle = query.findPickleBy(attempt);
    final number = attempt.attempt;
    final attemptText = number > 0 || willBeRetried
        ? ' (attempt ${number + 1}${willBeRetried ? ', retried' : ''})'
        : '';
    final location = pickle == null ? null : _pickleLocation(pickle);
    final header =
        'Scenario: ${pickle == null ? '' : _name(pickle)}$attemptText'
        '${location == null ? '' : ' # $location'}';

    final rows = <(_Status, String, String?, String?)>[];
    var beforePickleSteps = true;
    for (final (finished, testStep) in query.findTestStepFinishedAndTestStepBy(
      attempt,
    )) {
      final result = finished.testStepResult;
      if (_isPickleStep(testStep)) {
        beforePickleSteps = false;
        final pickleStep = query.findPickleStepBy(testStep);
        final step = pickleStep == null ? null : query.findStepBy(pickleStep);
        final keyword =
            step?.keyword ?? '${SnippetGenerator.keyword(pickleStep?.type)} ';
        rows.add((
          result.status,
          '$keyword${pickleStep?.text ?? ''}',
          step == null || pickle == null
              ? null
              : '${pickle.uri}:${step.location.line}',
          _stepMessage(result, hasSnippet: _snippetsOf(pickleStep).isNotEmpty),
        ));
      } else if (result.status != _Status.passed) {
        final hook = query.findHookBy(testStep);
        final before = switch (hook?.type) {
          messages.HookType.beforeTestCase => true,
          messages.HookType.afterTestCase => false,
          _ => beforePickleSteps,
        };
        rows.add((
          result.status,
          '${before ? 'Before' : 'After'} hook${_quotedName(hook?.name)}',
          _sourceLocation(hook?.sourceReference),
          _stepMessage(result, hasSnippet: false),
        ));
      }
    }

    final indent = ' ' * prefix.length;
    final width = rows.fold(
      0,
      (width, row) => row.$1.value.length > width ? row.$1.value.length : width,
    );
    final lines = ['$prefix$header'];
    for (final (status, text, location, message) in rows) {
      lines.add(
        '$indent${status.value.padRight(width)} $text'
        '${location == null ? '' : ' # $location'}',
      );
      if (message != null) {
        lines.add(_indent(message, ' ' * (indent.length + width + 3)));
      }
    }
    return lines.join('\n');
  }

  /// A failed test run hook: its kind, name and location, and its message.
  String _formatTestRunHook(String prefix, messages.TestRunHookFinished hook) {
    final definition = query.findHookBy(hook);
    final kind = switch (definition?.type) {
      messages.HookType.afterTestRun => 'AfterAll',
      messages.HookType.beforeTestRun => 'BeforeAll',
      _ => 'Test run',
    };
    final location = _sourceLocation(definition?.sourceReference);
    final result = hook.result;
    final message = _stepMessage(result, hasSnippet: false);
    return [
      '$prefix$kind hook${_quotedName(definition?.name)} '
          '(${result.status.value.toLowerCase()})'
          '${location == null ? '' : ' # $location'}',
      if (message != null) _indent(message, ' ' * (prefix.length + 2)),
    ].join('\n');
  }

  /// What a person needs to know about a non-passing [result].
  static String? _stepMessage(
    messages.TestStepResult result, {
    required bool hasSnippet,
  }) {
    final message = result.message?.trimRight();
    final text = message == null || message.isEmpty ? null : message;
    return switch (result.status) {
      _Status.failed || _Status.ambiguous =>
        text ?? result.exception?.message ?? result.exception?.type,
      _Status.pending => text == null ? 'Pending' : 'Pending: $text',
      _Status.undefined =>
        hasSnippet
            ? 'Undefined. Implement it with the snippet below.'
            : 'Undefined.',
      // A skip without a reason has the message `skipped`.
      _Status.skipped =>
        text == null || text.toLowerCase() == 'skipped'
            ? null
            : 'Skipped: $text',
      _Status.passed || _Status.unknown => null,
    };
  }

  /// Adds the snippets of [attempt]'s undefined steps.
  void _collectSnippets(messages.TestCaseStarted attempt) {
    for (final (finished, testStep) in query.findTestStepFinishedAndTestStepBy(
      attempt,
    )) {
      if (finished.testStepResult.status == _Status.undefined &&
          _isPickleStep(testStep)) {
        _snippets.addAll(_snippetsOf(query.findPickleStepBy(testStep)));
      }
    }
  }

  /// The snippets suggested for [pickleStep], one per suggestion.
  List<String> _snippetsOf(messages.PickleStep? pickleStep) => [
    if (pickleStep != null)
      for (final suggestion in query.findSuggestionsBy(pickleStep))
        if (suggestion.snippets.isNotEmpty)
          SnippetGenerator.present([
            for (final snippet in suggestion.snippets) snippet.code,
          ]),
  ];

  /// `uri:line` of [pickle].
  String _pickleLocation(messages.Pickle pickle) {
    final line = query.findLocationOf(pickle)?.line;
    return line == null ? pickle.uri : '${pickle.uri}:$line';
  }

  String _name(messages.Pickle pickle) {
    final lineage = query.findLineageBy(pickle);
    return lineage == null ? pickle.name : _naming.reduce(lineage, pickle);
  }

  /// `5 scenarios (1 failed, 1 undefined, 3 passed)`, as in cucumber-js.
  static String _formatCounts(String noun, Map<_Status, int> counts) {
    final total = counts.values.fold(0, (a, b) => a + b);
    final text = '$total $noun${total == 1 ? '' : 's'}';
    if (total == 0) return text;
    final details = [
      for (final status in _reportOrder)
        if ((counts[status] ?? 0) > 0)
          '${counts[status]} ${status.value.toLowerCase()}',
    ];
    return '$text (${details.join(', ')})';
  }

  /// `0m01.234s (executing steps: 0m00.567s)`, as in cucumber-js, or `null`
  /// while the run has not finished.
  String? _formatDuration() {
    final run = query.findTestRunDuration();
    if (run == null) return null;
    var steps = Duration.zero;
    for (final finished in query.findAllTestStepFinished()) {
      steps += _toDuration(finished.testStepResult.duration);
    }
    return '${formatDuration(_toDuration(run))} '
        '(executing steps: ${formatDuration(steps)})';
  }

  static Duration _toDuration(messages.Duration duration) => Duration(
    microseconds:
        duration.seconds * Duration.microsecondsPerSecond +
        duration.nanos ~/ 1000,
  );
}

/// [duration] in cucumber-js's summary format: `<minutes>m<ss>.<mmm>s`, such
/// as `0m01.234s`. Unlike cucumber-js, minutes are not wrapped at an hour.
String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  final millis = (duration.inMilliseconds % 1000).toString().padLeft(3, '0');
  return '${minutes}m$seconds.${millis}s';
}

String _quotedName(String? name) =>
    name == null || name.isEmpty ? '' : ' "$name"';

String? _sourceLocation(messages.SourceReference? reference) {
  final uri = reference?.uri;
  if (uri == null || uri.isEmpty) return null;
  final line = reference?.location?.line;
  return line == null ? uri : '$uri:$line';
}

String _indent(String text, String prefix) =>
    text.split('\n').map((line) => '$prefix$line'.trimRight()).join('\n');
