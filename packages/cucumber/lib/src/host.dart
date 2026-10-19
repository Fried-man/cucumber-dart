import 'package:cucumber_core/engine.dart';
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

/// Declares a [SuitePlan] as `package:test` groups and tests (design §6,
/// ADR-0013).
///
/// - Features, rules, scenario outlines and examples become [group]s, and
///   each pickle becomes a [test], named with [PlanNode.displayName].
/// - Every group and test has a [TestLocation] pointing at its `.feature`
///   line, so IDEs can navigate to it.
/// - Gherkin tags that are valid `package:test` tags become test tags (unless
///   [mapTags] is `false`).
/// - [setUpAll] starts the run and [tearDownAll] finishes it. Both only run
///   when at least one test runs.
/// - Each test runs its pickle and reports the final attempt: PASSED passes,
///   SKIPPED is marked skipped, PENDING, UNDEFINED and AMBIGUOUS fail with a
///   [TestFailure], and FAILED rethrows the original error.
final class PackageTestHost implements TestHost {
  /// Creates a host for features below [packageRoot].
  const PackageTestHost({
    required this.packageRoot,
    this.mapTags = true,
    this.scenarioTimeout,
  });

  /// The directory feature URIs are relative to.
  final String packageRoot;

  /// Whether Gherkin tags become `package:test` tags.
  final bool mapTags;

  /// The timeout of one scenario attempt; the test timeout is this times the
  /// number of attempts.
  final Timeout? scenarioTimeout;

  @override
  void declare(SuitePlan plan) {
    var beforeAllHooks = 0;
    setUpAll(() async {
      final order = plan.options.order;
      if (order is RandomOrder) {
        print(
          'Cucumber: running scenarios in random order. Reproduce it with '
          "order: 'random:${order.seed}'.",
        );
      }
      await plan.start();
      beforeAllHooks = plan.hookResults.length;
    });
    tearDownAll(() async {
      final result = await plan.finish();
      final afterAll = result.hooks.skip(beforeAllHooks);
      final failures = [
        for (final hook in afterAll)
          if (hook.status.isFailedish) hook,
      ];
      if (failures.isNotEmpty) {
        fail(
          [
            for (final hook in failures) _describeHookFailure(hook),
          ].join('\n\n'),
        );
      }
      final error = result.error;
      if (error != null) {
        fail('Cucumber failed with an internal error: $error');
      }
    });

    final timeout = attemptsTimeout(scenarioTimeout, plan.options.retry + 1);
    for (final node in plan.children) {
      _declare(plan, node, timeout);
    }
  }

  void _declare(SuitePlan plan, PlanNode node, Timeout? timeout) {
    final location = testLocation(node);
    switch (node) {
      case PlanGroup(:final children):
        group(node.displayName, location: location, () {
          for (final child in children) {
            _declare(plan, child, timeout);
          }
        });
      case ParseErrorNode():
        test(node.displayName, location: location, () {
          fail('${node.uri} could not be parsed:\n${node.message}');
        });
      case PickleNode():
        final tags = mapTags ? testTags(node.tags) : const <String>[];
        test(
          node.displayName,
          location: location,
          tags: tags.isEmpty ? null : tags,
          timeout: timeout,
          () async {
            final result = await plan.runPickle(node);
            reportResult(result, testRunHooks: plan.hookResults);
          },
        );
    }
  }

  /// The [TestLocation] of [node]: its feature file and line.
  TestLocation testLocation(PlanNode node) {
    final path = p.normalize(p.join(packageRoot, node.uri));
    return TestLocation(
      Uri.file(path),
      node.location.line,
      node.location.column ?? 1,
    );
  }
}

/// Matches the tags `package:test` accepts: (optionally hyphenated) Dart
/// identifiers.
final RegExp _testTag = RegExp(r'^[a-zA-Z_-][a-zA-Z0-9_-]*$');

/// The `package:test` tags for Gherkin [tags] (design §6): the `@` is
/// removed, and tags that are not hyphenated identifiers (such as
/// `@issue:123`) are left out, because `package:test` rejects them.
List<String> testTags(Iterable<String> tags) => [
  ...{
    for (final tag in tags)
      if (_testTag.hasMatch(tag.startsWith('@') ? tag.substring(1) : tag))
        tag.startsWith('@') ? tag.substring(1) : tag,
  },
];

/// The timeout for a test that makes up to [attempts] attempts of
/// [perAttempt] (design §5.8). Without [perAttempt], the default
/// `package:test` timeout is scaled.
Timeout? attemptsTimeout(Timeout? perAttempt, int attempts) {
  if (perAttempt == null) {
    return attempts <= 1 ? null : Timeout.factor(attempts);
  }
  if (perAttempt == Timeout.none || attempts <= 1) return perAttempt;
  final duration = perAttempt.duration;
  if (duration != null) return Timeout(duration * attempts);
  return Timeout.factor(perAttempt.scaleFactor! * attempts);
}

/// Reports [result] to `package:test` (design §6):
///
/// | Status | Report |
/// |---|---|
/// | PASSED | returns normally |
/// | SKIPPED | [markTestSkipped] |
/// | PENDING, UNDEFINED, AMBIGUOUS | throws a [TestFailure], with snippets for undefined steps |
/// | FAILED | prints the Cucumber context with [printOnFailure], then rethrows the original error with its stack trace |
///
/// A pickle that did not run (because a `BeforeAll` hook failed) fails with
/// [TestCaseResult.notRunReason] and the failures of [testRunHooks].
void reportResult(
  TestCaseResult result, {
  List<StepResult> testRunHooks = const [],
}) {
  final reason = result.notRunReason;
  if (reason != null) {
    fail(
      [
        reason,
        for (final hook in testRunHooks)
          if (hook.status.isFailedish) _describeHookFailure(hook),
      ].join('\n\n'),
    );
  }
  switch (result.status) {
    case Status.passed || Status.unknown:
      return;
    case Status.skipped:
      final step = result.decisiveStep;
      final why = step?.message;
      markTestSkipped(
        step == null
            ? 'Skipped'
            : 'Skipped at ${_describeStep(step)}'
                  '${why == null || why.isEmpty ? '' : ': $why'}',
      );
    case Status.pending || Status.undefined || Status.ambiguous:
      fail(failureMessage(result));
    case Status.failed:
      final failed = [
        for (final step in result.steps)
          if (step.status == Status.failed) step,
      ];
      final first = failed.isEmpty ? null : failed.first;
      final error = first?.error;
      if (first == null || error == null) fail(failureMessage(result));
      printOnFailure(failureMessage(result));
      Error.throwWithStackTrace(error, first.stackTrace ?? StackTrace.empty);
  }
}

/// Explains why [result] failed: the scenario, the decisive steps and, for
/// undefined steps, Dart snippets implementing them.
String failureMessage(TestCaseResult result) {
  final pickle = result.pickle;
  final scenario =
      'scenario "${pickle.name}" (${pickle.uri}:${pickle.location?.line ?? 1})';
  final steps = [
    for (final step in result.steps)
      if (step.status == result.status) step,
  ];
  final buffer = StringBuffer();
  final status = result.status;
  final kind = switch (status) {
    Status.pending => 'Pending',
    Status.undefined => 'Undefined',
    Status.ambiguous => 'Ambiguous',
    Status.failed => 'Failed',
    _ => status.name,
  };
  buffer.writeln('$kind ${steps.length == 1 ? 'step' : 'steps'} in $scenario:');
  for (final step in steps) {
    buffer.write('  ${_describeStep(step)}');
    final message = step.message;
    if (status == Status.failed) {
      buffer.write(': ${step.error ?? message}');
    } else if (status != Status.undefined && message != null) {
      buffer.write(':\n${_indent(message, '    ')}');
    }
    buffer.writeln();
  }
  if (result.attempts > 1) {
    buffer.writeln('(after ${result.attempts} attempts)');
  }
  final snippets = result.snippets;
  if (status == Status.undefined && snippets.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(
        snippets.length == 1
            ? 'Implement it with this snippet:'
            : 'Implement them with these snippets:',
      )
      ..writeln();
    for (final snippet in snippets) {
      buffer
        ..writeln(snippet)
        ..writeln();
    }
  }
  return buffer.toString().trimRight();
}

String _describeStep(StepResult step) =>
    '${step.description.trim()} (${step.location})';

/// Packages whose frames are left out of hook failure traces.
const Set<String> _internalPackages = {
  'cucumber',
  'cucumber_core',
  'matcher',
  'stack_trace',
  'test',
  'test_api',
  'test_core',
};

/// [stackTrace] without frames from the SDK, the cucumber packages and
/// `package:test`.
String _userFrames(StackTrace stackTrace) {
  try {
    final frames = Trace.from(
      stackTrace,
    ).frames.where((f) => !f.isCore && !_internalPackages.contains(f.package));
    return Trace(frames).toString().trimRight();
  } on Object {
    return stackTrace.toString().trimRight();
  }
}

String _describeHookFailure(StepResult hook) {
  final error = hook.error;
  final trace = hook.stackTrace == null ? '' : _userFrames(hook.stackTrace!);
  final details = error == null
      ? hook.message ?? hook.status.name
      : '$error${trace.isEmpty ? '' : '\n$trace'}';
  return '${hook.status.name.toUpperCase()} ${_describeStep(hook)}:\n'
      '${_indent(details, '  ')}';
}

String _indent(String text, String prefix) =>
    text.trimRight().split('\n').map((line) => '$prefix$line').join('\n');
