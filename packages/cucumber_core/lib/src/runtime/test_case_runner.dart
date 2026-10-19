import 'dart:async';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../data/data_table.dart';
import '../data/doc_string.dart';
import '../exceptions.dart';
import '../glue/definitions.dart';
import '../glue/glue.dart';
import '../glue/support_code_library.dart';
import '../status.dart';
import '../world/context.dart';
import '../world/scenario.dart';
import '../world/world.dart';
import 'errors.dart';
import 'ids.dart';
import 'message_bus.dart';
import 'platform.dart';
import 'results.dart';
import 'snippets.dart';
import 'test_case_assembler.dart';
import 'user_code_runner.dart';

/// Thrown when a step body cannot be called with a step's arguments.
final class StepArityException implements Exception {
  /// Creates an exception with [message].
  StepArityException(this.message);

  /// What does not fit.
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a parameter type transformer returns a value of the wrong
/// type.
final class TransformerResultException implements Exception {
  /// Creates an exception with [message].
  TransformerResultException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Deep-copies JSON-like [value]: maps and lists are copied recursively.
Object? deepCopy(Object? value) => switch (value) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries) '${entry.key}': deepCopy(entry.value),
  },
  final List<Object?> list => [for (final item in list) deepCopy(item)],
  _ => value,
};

/// Runs test cases: attempts, World lifecycle, status rules, step hooks,
/// retries and suggestions (design §3.3, §5).
final class TestCaseRunner {
  /// Creates a runner.
  TestCaseRunner({
    required this.library,
    required this.bus,
    required this.ids,
    required this.platform,
    required this.worldFactory,
    required this.snippets,
    this.retry = 0,
    this.dryRun = false,
  }) : _userCode = UserCodeRunner(platform);

  /// The glue.
  final SupportCodeLibrary library;

  /// Where messages go.
  final MessageBus bus;

  /// The ID scheme.
  final IdScheme ids;

  /// The platform.
  final CucumberPlatform platform;

  /// Creates a World for each attempt.
  final Object Function() worldFactory;

  /// Generates snippets for undefined steps.
  final SnippetGenerator snippets;

  /// How many extra attempts FAILED test cases get.
  final int retry;

  /// Whether to skip all user code (design §5.6).
  final bool dryRun;

  final UserCodeRunner _userCode;

  messages.Timestamp _now() => messages.dateTimeToTimestamp(platform.now());

  /// Runs [testCase] with [worldParameters] (deep-copied for each attempt).
  Future<TestCaseResult> run(
    AssembledTestCase testCase, {
    Map<String, Object?> worldParameters = const {},
  }) async {
    bus.emit(messages.Envelope(testCase: testCase.message));
    var attempt = 0;
    while (true) {
      final result = await _runAttempt(testCase, attempt, worldParameters);
      if (!result.willBeRetried) {
        return TestCaseResult(
          pickle: testCase.pickle,
          status: result.status,
          attempts: attempt + 1,
          steps: result.steps,
        );
      }
      attempt++;
    }
  }

  Future<_AttemptResult> _runAttempt(
    AssembledTestCase testCase,
    int attempt,
    Map<String, Object?> worldParameters,
  ) async {
    final pickle = testCase.pickle;
    final testCaseStartedId = ids.newId();
    final context = _AttemptContext(
      bus: bus,
      platform: platform,
      testCaseStartedId: testCaseStartedId,
      parameters: deepCopy(worldParameters)! as Map<String, Object?>,
    );
    final scenario = _ScenarioImpl(pickle, attempt, context);
    context.scenario = scenario;

    bus.emit(
      messages.Envelope(
        testCaseStarted: messages.TestCaseStarted(
          attempt: attempt,
          id: testCaseStartedId,
          testCaseId: testCase.message.id,
          timestamp: _now(),
        ),
      ),
    );

    Object? world;
    Object? worldError;
    StackTrace? worldStackTrace;
    try {
      world = runInContext(context, worldFactory);
    } on Object catch (e, st) {
      worldError = e;
      worldStackTrace = st;
    }

    var skipRest = false;
    var failedish = false;
    final results = <StepResult>[];
    for (final step in testCase.steps) {
      context.currentStepId = step.id;
      bus.emit(
        messages.Envelope(
          testStepStarted: messages.TestStepStarted(
            testCaseStartedId: testCaseStartedId,
            testStepId: step.id,
            timestamp: _now(),
          ),
        ),
      );

      final _Outcome outcome;
      final hook = step.hook;
      if (worldError != null && !failedish) {
        outcome = _Outcome.failed(Duration.zero, worldError, worldStackTrace);
      } else if (hook != null) {
        final isBefore = hook.kind == HookKind.before;
        if (dryRun || world == null || (isBefore && (skipRest || failedish))) {
          outcome = _Outcome.skipped();
        } else {
          outcome = await _runHook(hook, world, scenario, context, scenario);
        }
      } else {
        outcome = await _runPickleStep(
          step,
          world,
          scenario,
          context,
          skipRest: skipRest,
          failedish: failedish,
        );
      }

      final location = hook != null
          ? '${hook.glue.source ?? hook.glue}'
          : '${pickle.uri}:${step.gherkinStep?.location.line ?? pickle.location?.line ?? 0}';
      final isAfterHook = hook != null && hook.kind == HookKind.after;
      if (outcome.status == Status.skipped &&
          outcome.explicit &&
          !failedish &&
          !isAfterHook) {
        skipRest = true;
      }
      if (outcome.status.isFailedish) failedish = true;
      scenario._record(outcome);

      bus.emit(
        messages.Envelope(
          testStepFinished: messages.TestStepFinished(
            testCaseStartedId: testCaseStartedId,
            testStepId: step.id,
            testStepResult: outcome.toMessage(location),
            timestamp: _now(),
          ),
        ),
      );
      results.add(
        outcome.toResult(_describe(step), location, isHook: hook != null),
      );
    }

    context.currentStepId = null;
    if (worldError != null && testCase.steps.isEmpty) {
      scenario._record(
        _Outcome.failed(Duration.zero, worldError, worldStackTrace),
      );
    }
    final status = scenario.status == Status.unknown
        ? Status.passed
        : scenario.status;
    final willBeRetried = status == Status.failed && attempt < retry;
    context.active = false;
    bus.emit(
      messages.Envelope(
        testCaseFinished: messages.TestCaseFinished(
          testCaseStartedId: testCaseStartedId,
          timestamp: _now(),
          willBeRetried: willBeRetried,
        ),
      ),
    );
    return _AttemptResult(status, results, willBeRetried);
  }

  String _describe(TestStepPlan step) {
    final hook = step.hook;
    if (hook != null) {
      final kind = hook.kind == HookKind.before ? 'Before' : 'After';
      final name = hook.glue.name;
      return name == null ? '$kind hook' : '$kind hook "$name"';
    }
    final keyword =
        step.gherkinStep?.keyword ??
        '${SnippetGenerator.keyword(step.pickleStep!.type)} ';
    return '$keyword${step.pickleStep!.text}';
  }

  Future<_Outcome> _runPickleStep(
    TestStepPlan step,
    Object? world,
    _ScenarioImpl scenario,
    _AttemptContext context, {
    required bool skipRest,
    required bool failedish,
  }) async {
    final pickleStep = step.pickleStep!;
    if (skipRest) return _Outcome.skipped();
    if (step.matches.length > 1) {
      return _Outcome(
        Status.ambiguous,
        Duration.zero,
        message:
            'Multiple step definitions match "${pickleStep.text}":\n'
            '${step.matches.map((m) => '  ${m.definition.glue} at ${m.definition.glue.source ?? '?'}').join('\n')}',
      );
    }
    if (step.matches.isEmpty) {
      bus.emit(
        messages.Envelope(
          suggestion: messages.Suggestion(
            id: ids.newId(),
            pickleStepId: pickleStep.id,
            snippets: [
              for (final code in snippets.generateAll(pickleStep))
                messages.Snippet(language: 'dart', code: code),
            ],
          ),
        ),
      );
      return _Outcome(
        Status.undefined,
        Duration.zero,
        message: 'Undefined step: "${pickleStep.text}"',
        snippet: snippets.generate(pickleStep),
      );
    }
    if (dryRun || failedish) return _Outcome.skipped();

    final stepObject = _StepImpl(scenario, pickleStep, step.gherkinStep);
    final tags = scenario.tags;
    final outcomes = <_Outcome>[];
    for (final hook in library.beforeStepHooks) {
      if (hook.appliesTo(tags)) {
        outcomes.add(
          await _runHook(hook, world!, stepObject, context, scenario),
        );
      }
    }
    if (!outcomes.any((o) => o.status == Status.failed)) {
      final outcome = await _invokeStep(
        step.matches.single,
        pickleStep,
        world!,
        context,
      );
      outcomes.add(outcome);
      stepObject
        ..status = outcome.status
        ..error = outcome.error;
    }
    for (final hook in library.afterStepHooks) {
      if (hook.appliesTo(tags)) {
        outcomes.add(
          await _runHook(hook, world!, stepObject, context, scenario),
        );
      }
    }
    return _Outcome.fold(outcomes);
  }

  Future<_Outcome> _invokeStep(
    StepMatch match,
    messages.PickleStep pickleStep,
    Object world,
    _AttemptContext context,
  ) async {
    final definition = match.definition;
    final multiline = <Object>[];
    final argument = pickleStep.argument;
    if (argument != null) {
      final parts = <(int, Object)>[
        if (argument.dataTable case final table?)
          (
            table.argumentIndex ?? 0,
            DataTable.withConverter([
              for (final row in table.rows)
                [for (final cell in row.cells) cell.value],
            ], library.converter),
          ),
        if (argument.docString case final docString?)
          (
            docString.argumentIndex ?? 0,
            DocString.withConverter(
              docString.content,
              library.converter,
              mediaType: docString.mediaType,
            ),
          ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      multiline.addAll([for (final p in parts) p.$2]);
    }

    final layout = definition.layoutFor(multiline.length);
    final body = definition.glue.body;
    final arity = definition.arity;
    final result = await _userCode.run(
      () async {
        if (layout == null) {
          throw StepArityException(
            '${definition.glue} takes $arity parameters, but the step has '
            '${definition.parameterCount} expression argument'
            '${definition.parameterCount == 1 ? '' : 's'} and '
            '${multiline.length} multiline argument'
            '${multiline.length == 1 ? '' : 's'}'
            '${definition.parameterCount + multiline.length + 1 == arity || definition.parameterCount + multiline.length == arity ? '' : ' (plus an optional World)'}.',
          );
        }
        if (layout.problem case final problem?) {
          throw StepArityException('${definition.glue}: $problem.');
        }
        final arguments = <Object?>[if (layout.world) world];
        for (final argument in match.arguments) {
          final type = argument.parameterType;
          if (type == null) {
            arguments.add(argument.group.value);
            continue;
          }
          final value = await type.transform(argument.group.values, world);
          if (value != null && !type.witness.accepts(value)) {
            throw TransformerResultException(
              'The transformer of {${type.name}} returned a '
              '${value.runtimeType}, which is not a ${type.witness}.',
            );
          }
          arguments.add(value);
        }
        for (final value in multiline) {
          final index = arguments.length;
          arguments.add(
            value is DataTable
                ? library.converter.tableArgument(body, index, arity, value)
                : library.converter.docStringArgument(
                    body,
                    index,
                    arity,
                    value as DocString,
                  ),
          );
        }
        final returned = Function.apply(body, arguments);
        if (returned is Future<Object?>) await returned;
      },
      context: context,
      timeout: definition.glue.timeout,
      onLateError: context.lateError,
    );
    return _Outcome.of(result);
  }

  /// Runs a `BeforeAll` or `AfterAll` [hook] (design §5.4), emitting
  /// `testRunHookStarted`, any attachments, and `testRunHookFinished`.
  Future<StepResult> runTestRunHook(
    HookDefinition hook,
    TestRun testRun,
    String testRunStartedId,
  ) async {
    final id = ids.newId();
    bus.emit(
      messages.Envelope(
        testRunHookStarted: messages.TestRunHookStarted(
          id: id,
          testRunStartedId: testRunStartedId,
          hookId: hook.id,
          timestamp: _now(),
        ),
      ),
    );
    final _Outcome outcome;
    if (dryRun) {
      outcome = _Outcome.skipped();
    } else {
      final context = _TestRunHookContext(bus, platform, id);
      final body = hook.glue.body;
      final result = await _userCode.run(
        () async {
          final returned = Function.apply(
            body,
            hook.layout == HookLayout.none ? const [] : [testRun],
          );
          if (returned is Future<Object?>) await returned;
        },
        context: context,
        timeout: hook.glue.timeout,
      );
      context.active = false;
      outcome = _Outcome.of(result);
    }
    final location = '${hook.glue.source ?? hook.glue}';
    bus.emit(
      messages.Envelope(
        testRunHookFinished: messages.TestRunHookFinished(
          testRunHookStartedId: id,
          result: outcome.toMessage(location),
          timestamp: _now(),
        ),
      ),
    );
    final kind = hook.kind == HookKind.beforeAll ? 'BeforeAll' : 'AfterAll';
    final name = hook.glue.name;
    return outcome.toResult(
      name == null ? '$kind hook' : '$kind hook "$name"',
      location,
      isHook: true,
    );
  }

  Future<_Outcome> _runHook(
    HookDefinition hook,
    Object world,
    Object contextObject,
    _AttemptContext context,
    _ScenarioImpl scenario,
  ) async {
    final body = hook.glue.body;
    final result = await _userCode.run(
      () async {
        final returned = Function.apply(body, switch (hook.layout) {
          HookLayout.none => const [],
          HookLayout.world => [world],
          HookLayout.context => [contextObject],
          HookLayout.worldAndContext => [world, contextObject],
        });
        if (returned is Future<Object?>) await returned;
      },
      context: context,
      timeout: hook.glue.timeout,
      onLateError: context.lateError,
    );
    return _Outcome.of(result);
  }
}

final class _AttemptResult {
  _AttemptResult(this.status, this.steps, this.willBeRetried);

  final Status status;
  final List<StepResult> steps;
  final bool willBeRetried;
}

/// The result of a step, hook, or step with its step hooks.
final class _Outcome {
  _Outcome(
    this.status,
    this.duration, {
    this.error,
    this.stackTrace,
    this.message,
    this.snippet,
    this.explicit = false,
  });

  _Outcome.skipped() : this(Status.skipped, Duration.zero);

  _Outcome.failed(Duration duration, Object error, StackTrace? stackTrace)
    : this(Status.failed, duration, error: error, stackTrace: stackTrace);

  factory _Outcome.of(UserCodeResult result) {
    final error = result.error;
    return switch (error) {
      null => _Outcome(Status.passed, result.duration),
      PendingException(:final message) => _Outcome(
        Status.pending,
        result.duration,
        error: error,
        stackTrace: result.stackTrace,
        message: message,
      ),
      SkippedException(:final reason) => _Outcome(
        Status.skipped,
        result.duration,
        error: error,
        stackTrace: result.stackTrace,
        message: reason,
        explicit: true,
      ),
      _ => _Outcome.failed(result.duration, error, result.stackTrace),
    };
  }

  /// The worst outcome, with the summed duration.
  factory _Outcome.fold(List<_Outcome> outcomes) {
    var worst = outcomes.first;
    var duration = Duration.zero;
    for (final outcome in outcomes) {
      duration += outcome.duration;
      if (outcome.status.isWorseThan(worst.status)) worst = outcome;
    }
    return _Outcome(
      worst.status,
      duration,
      error: worst.error,
      stackTrace: worst.stackTrace,
      message: worst.message,
      explicit: worst.explicit,
    );
  }

  final Status status;
  final Duration duration;
  final Object? error;
  final StackTrace? stackTrace;
  final String? message;
  final String? snippet;

  /// Whether user code skipped itself (rather than being skipped).
  final bool explicit;

  messages.TestStepResult toMessage(String location) {
    final error = this.error;
    return messages.TestStepResult(
      duration: messages.durationToDurationMessage(duration),
      status: status.toMessage(),
      message: error != null && status == Status.failed
          ? errorMessage(error, stackTrace, gherkinFrame: location)
          : message ?? error?.toString(),
      exception: error == null
          ? null
          : exceptionMessage(error, stackTrace, gherkinFrame: location),
    );
  }

  StepResult toResult(
    String description,
    String location, {
    required bool isHook,
  }) => StepResult(
    status: status,
    duration: duration,
    description: description,
    location: location,
    error: error,
    stackTrace: stackTrace,
    message: message,
    snippet: snippet,
    isHook: isHook,
  );
}

/// The context of a scenario attempt: routes attachments to the current step.
final class _AttemptContext extends ScenarioExecutionContext {
  _AttemptContext({
    required this.bus,
    required this.platform,
    required this.testCaseStartedId,
    required this.parameters,
  });

  final MessageBus bus;
  final CucumberPlatform platform;
  final String testCaseStartedId;

  @override
  final Map<String, Object?> parameters;

  @override
  late final _ScenarioImpl scenario;

  String? currentStepId;
  bool active = true;

  @override
  void attach(Object data, {String? mediaType, String? fileName}) {
    if (!active) {
      throw StateError(
        'Cannot attach after scenario "${scenario.name}" has finished.',
      );
    }
    final encoded = encodeAttachment(data, mediaType);
    bus.emit(
      messages.Envelope(
        attachment: messages.Attachment(
          body: encoded.body,
          contentEncoding: encoded.encoding,
          mediaType: encoded.mediaType,
          fileName: fileName,
          testCaseStartedId: testCaseStartedId,
          testStepId: currentStepId,
          timestamp: messages.dateTimeToTimestamp(platform.now()),
        ),
      ),
    );
  }

  /// Reports an uncaught error that arrived after the user code that caused
  /// it finished, as a stack trace attachment on the current step.
  void lateError(Object error, StackTrace stackTrace) {
    if (!active) return;
    attach(
      'Uncaught error after the step finished:\n'
      '${errorMessage(error, stackTrace)}',
      mediaType: 'text/x.cucumber.stacktrace+plain',
    );
  }
}

/// The context of a running test-run hook.
final class _TestRunHookContext extends ExecutionContext {
  _TestRunHookContext(this.bus, this.platform, this.testRunHookStartedId);

  final MessageBus bus;
  final CucumberPlatform platform;
  final String testRunHookStartedId;
  bool active = true;

  @override
  void attach(Object data, {String? mediaType, String? fileName}) {
    if (!active) {
      throw StateError('Cannot attach after the test-run hook has finished.');
    }
    final encoded = encodeAttachment(data, mediaType);
    bus.emit(
      messages.Envelope(
        attachment: messages.Attachment(
          body: encoded.body,
          contentEncoding: encoded.encoding,
          mediaType: encoded.mediaType,
          fileName: fileName,
          testRunHookStartedId: testRunHookStartedId,
          timestamp: messages.dateTimeToTimestamp(platform.now()),
        ),
      ),
    );
  }
}

/// The test run passed to `BeforeAll` and `AfterAll` hooks.
final class TestRunImpl implements TestRun {
  /// Creates a test run with [parameters].
  TestRunImpl(this.parameters);

  @override
  final Map<String, Object?> parameters;

  @override
  void attach(Object data, {String? mediaType, String? fileName}) =>
      requireContext(
        'TestRun.attach',
      ).attach(data, mediaType: mediaType, fileName: fileName);

  @override
  void log(String text) => requireContext('TestRun.log').log(text);

  @override
  void link(String url, {String? title}) =>
      requireContext('TestRun.link').link(url, title: title);
}

final class _ScenarioImpl implements Scenario {
  _ScenarioImpl(this._pickle, this.attempt, this._context)
    : tags = List.unmodifiable([for (final t in _pickle.tags) t.name]);

  final messages.Pickle _pickle;
  final _AttemptContext _context;

  @override
  final int attempt;

  @override
  final List<String> tags;

  @override
  Status status = Status.unknown;

  @override
  Object? error;

  void _record(_Outcome outcome) {
    if (outcome.status.isWorseThan(status)) status = outcome.status;
    if (outcome.status == Status.failed) error ??= outcome.error;
  }

  @override
  String get id => _pickle.id;

  @override
  String get name => _pickle.name;

  @override
  String get uri => _pickle.uri;

  @override
  int get line => _pickle.location?.line ?? 0;

  @override
  String get language => _pickle.language;

  @override
  bool get isFailed => status == Status.failed;

  @override
  void attach(Object data, {String? mediaType, String? fileName}) =>
      _context.attach(data, mediaType: mediaType, fileName: fileName);

  @override
  void log(String text) => _context.log(text);

  @override
  void link(String url, {String? title}) => _context.link(url, title: title);

  @override
  String toString() => 'Scenario($name)';
}

final class _StepImpl implements Step {
  _StepImpl(this.scenario, this._pickleStep, this._gherkinStep);

  @override
  final Scenario scenario;

  final messages.PickleStep _pickleStep;
  final messages.Step? _gherkinStep;

  @override
  Status status = Status.unknown;

  @override
  Object? error;

  @override
  String get text => _pickleStep.text;

  @override
  String get keyword => _gherkinStep?.keyword ?? '';

  @override
  int get line => _gherkinStep?.location.line ?? 0;

  @override
  String toString() => 'Step($keyword$text)';
}
