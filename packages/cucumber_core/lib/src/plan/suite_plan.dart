import 'dart:async';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../filter/pickle_filter.dart';
import '../filter/pickle_order.dart';
import '../gherkin/source_loader.dart';
import '../glue/glue.dart';
import '../glue/support_code_library.dart';
import '../runtime/errors.dart';
import '../runtime/ids.dart';
import '../runtime/message_bus.dart';
import '../runtime/platform.dart';
import '../runtime/plugin.dart';
import '../runtime/results.dart';
import '../runtime/snippets.dart';
import '../runtime/test_case_assembler.dart';
import '../runtime/test_case_runner.dart';
import '../world/world.dart';
import 'plan_nodes.dart';

/// Options for a run, resolved by the host from code, files and the
/// environment.
final class RunOptions {
  /// Creates run options.
  const RunOptions({
    this.tags,
    this.names = const [],
    this.lines = const {},
    this.order = PickleOrder.defined,
    this.retry = 0,
    this.dryRun = false,
    this.worldParameters = const {},
  });

  /// A tag expression selecting pickles.
  final String? tags;

  /// Regular expressions, one of which must match a pickle's name.
  final List<String> names;

  /// Lines selecting pickles, per feature file URI.
  final Map<String, Set<int>> lines;

  /// The order in which pickles run.
  final PickleOrder order;

  /// Extra attempts for FAILED test cases.
  final int retry;

  /// Whether to report steps without running any user code.
  final bool dryRun;

  /// The world parameters (JSON-like values).
  final Map<String, Object?> worldParameters;
}

/// A suite ready to run: parsed features, loaded glue, and the selected
/// pickles arranged in a tree that hosts declare (ADR-0001).
///
/// Creating a plan is synchronous, so hosts can declare tests from it
/// immediately. Messages are buffered until [start]:
///
/// 1. [start] emits the buffered static messages, `testRunStarted`, and runs
///    the `BeforeAll` hooks.
/// 2. [runPickle] runs one pickle (with retries) and returns its result.
/// 3. [finish] runs the `AfterAll` hooks, emits `testRunFinished` and closes
///    the plugins.
///
/// If [start] is never called, [finish] closes the plugins without emitting
/// anything.
final class SuitePlan {
  SuitePlan._({
    required this.children,
    required this.pickles,
    required this.parseErrors,
    required this.features,
    required this.options,
    required this.library,
    required MessageBus bus,
    required IdScheme ids,
    required TestCaseRunner runner,
    required TestCaseAssembler assembler,
  }) : _bus = bus,
       _ids = ids,
       _runner = runner,
       _assembler = assembler;

  /// Parses [features], loads [glue], selects and orders pickles, and plans
  /// the run.
  ///
  /// - [world] creates a World for each scenario attempt; a [DefaultWorld] is
  ///   used when omitted.
  /// - [plugins] receive the messages.
  /// - [platform] supplies the clock and `meta` facts.
  /// - [ids] allocates message IDs (default: deterministic static IDs and
  ///   random dynamic ones, ADR-0018).
  ///
  /// Throws a `GlueException` for invalid glue and an [ArgumentError] for
  /// invalid options.
  static SuitePlan create<W extends Object>({
    required Iterable<FeatureSource> features,
    required List<Glue> glue,
    W Function()? world,
    RunOptions options = const RunOptions(),
    List<Plugin> plugins = const [],
    CucumberPlatform platform = const CucumberPlatform(),
    IdScheme? ids,
  }) {
    if (world == null) {
      return _create<DefaultWorld>(
        features,
        glue,
        DefaultWorld.new,
        options,
        plugins,
        platform,
        ids ?? IdScheme.deterministic(),
      );
    }
    return _create<W>(
      features,
      glue,
      world,
      options,
      plugins,
      platform,
      ids ?? IdScheme.deterministic(),
    );
  }

  static SuitePlan _create<W extends Object>(
    Iterable<FeatureSource> sources,
    List<Glue> glue,
    W Function() world,
    RunOptions options,
    List<Plugin> plugins,
    CucumberPlatform platform,
    IdScheme ids,
  ) {
    if (options.retry < 0) {
      throw ArgumentError.value(options.retry, 'retry', 'Must not be negative');
    }
    final filter = PickleFilter(
      tags: options.tags,
      names: options.names,
      lines: options.lines,
    );
    final bus = MessageBus(plugins)
      ..emit(messages.Envelope(meta: platform.meta()));

    final features = SourceLoader(ids).loadAll(sources);
    final parseErrors = <ParseErrorNode>[];
    final selected = <PickleNode>[];
    for (final feature in features) {
      feature.envelopes.forEach(bus.emit);
      if (feature.hasParseErrors) {
        parseErrors.add(ParseErrorNode(feature.uri, feature.parseErrors));
      }
      for (final pickle in feature.pickles) {
        if (filter.matches(pickle, feature.index)) {
          selected.add(PickleNode(pickle, feature.index));
        }
      }
    }

    final library = SupportCodeLibrary.load<W>(glue, ids: ids);
    library.envelopes.forEach(bus.emit);

    final ordered = options.order.apply(selected);
    final runner = TestCaseRunner(
      library: library,
      bus: bus,
      ids: ids,
      platform: platform,
      worldFactory: world,
      snippets: SnippetGenerator(
        library.parameterTypes,
        worldTypeName: library.worldTypeName,
      ),
      retry: options.retry,
      dryRun: options.dryRun,
    );
    return SuitePlan._(
      children: List.unmodifiable([...parseErrors, ...buildPlanTree(ordered)]),
      pickles: List.unmodifiable(ordered),
      parseErrors: List.unmodifiable(parseErrors),
      features: List.unmodifiable(features),
      options: options,
      library: library,
      bus: bus,
      ids: ids,
      runner: runner,
      assembler: TestCaseAssembler(library, ids),
    );
  }

  /// The top-level nodes: parse errors, then features (in run order).
  final List<PlanNode> children;

  /// The selected pickles, in run order.
  final List<PickleNode> pickles;

  /// The feature files that failed to parse.
  final List<ParseErrorNode> parseErrors;

  /// Every parsed feature file, in discovery order.
  final List<LoadedFeature> features;

  /// The run options.
  final RunOptions options;

  /// The loaded glue.
  final SupportCodeLibrary library;

  final MessageBus _bus;
  final IdScheme _ids;
  final TestCaseRunner _runner;
  final TestCaseAssembler _assembler;

  Future<void>? _starting;
  String? _testRunStartedId;
  late final TestRunImpl _testRun = TestRunImpl(
    deepCopy(options.worldParameters)! as Map<String, Object?>,
  );
  bool _beforeAllFailed = false;
  bool _success = true;
  Object? _internalError;
  StackTrace? _internalStackTrace;
  final List<TestCaseResult> _results = [];
  final List<StepResult> _hookResults = [];
  Future<TestRunResult>? _finishing;

  /// Whether [start] has been called.
  bool get isStarted => _starting != null;

  /// Whether a `BeforeAll` hook failed, in which case no pickle runs.
  bool get beforeAllFailed => _beforeAllFailed;

  /// The results of the `BeforeAll` hooks (and, after [finish], the
  /// `AfterAll` hooks).
  List<StepResult> get hookResults => List.unmodifiable(_hookResults);

  /// Starts the run: delivers the buffered messages, emits `testRunStarted`
  /// and runs the `BeforeAll` hooks. Calling it again returns the same
  /// future.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _bus.start();
    final id = _testRunStartedId = _ids.newId();
    _bus.emit(
      messages.Envelope(
        testRunStarted: messages.TestRunStarted(
          id: id,
          timestamp: messages.dateTimeToTimestamp(_runner.platform.now()),
        ),
      ),
    );
    try {
      for (final hook in library.beforeAllHooks) {
        final result = await _runner.runTestRunHook(hook, _testRun, id);
        _hookResults.add(result);
        if (result.status.isFailedish) _beforeAllFailed = true;
      }
    } on Object catch (e, st) {
      _internalError ??= e;
      _internalStackTrace ??= st;
      _beforeAllFailed = true;
    }
    if (_beforeAllFailed) _success = false;
  }

  /// Runs [node] (starting the run first if needed) and returns its result.
  ///
  /// If a `BeforeAll` hook failed, nothing runs and the result says why.
  Future<TestCaseResult> runPickle(PickleNode node) async {
    await start();
    if (_finishing != null) {
      throw StateError('The run has finished.');
    }
    if (_beforeAllFailed) {
      return TestCaseResult.notRun(
        node.pickle,
        'Not run because a BeforeAll hook failed.',
      );
    }
    try {
      final testCase = _assembler.assemble(
        node.pickle,
        index: node.index,
        testRunStartedId: _testRunStartedId,
      );
      final result = await _runner.run(
        testCase,
        worldParameters: _testRun.parameters,
      );
      _results.add(result);
      if (result.isFailure) _success = false;
      return result;
    } on Object catch (e, st) {
      _internalError ??= e;
      _internalStackTrace ??= st;
      _success = false;
      rethrow;
    }
  }

  /// Finishes the run: runs the `AfterAll` hooks, emits `testRunFinished` and
  /// closes the plugins. Calling it again returns the same future.
  Future<TestRunResult> finish() => _finishing ??= _finish();

  Future<TestRunResult> _finish() async {
    if (parseErrors.isNotEmpty) _success = false;
    if (_starting == null) {
      await _bus.close();
      return TestRunResult(
        success: _success,
        testCases: const [],
        hooks: const [],
      );
    }
    await _starting;
    try {
      for (final hook in library.afterAllHooks) {
        final result = await _runner.runTestRunHook(
          hook,
          _testRun,
          _testRunStartedId!,
        );
        _hookResults.add(result);
        if (result.status.isFailedish) _success = false;
      }
    } on Object catch (e, st) {
      _internalError ??= e;
      _internalStackTrace ??= st;
    }
    final error = _internalError;
    if (error != null) _success = false;
    _bus.emit(
      messages.Envelope(
        testRunFinished: messages.TestRunFinished(
          success: _success,
          timestamp: messages.dateTimeToTimestamp(_runner.platform.now()),
          testRunStartedId: _testRunStartedId,
          message: error == null
              ? null
              : errorMessage(error, _internalStackTrace),
          exception: error == null
              ? null
              : exceptionMessage(error, _internalStackTrace),
        ),
      ),
    );
    await _bus.close();
    return TestRunResult(
      success: _success,
      testCases: List.unmodifiable(_results),
      hooks: List.unmodifiable(_hookResults),
      error: error,
    );
  }
}

/// Declares a [SuitePlan] in a test framework (ADR-0001).
abstract interface class TestHost {
  /// Declares (or runs) [plan].
  FutureOr<void> declare(SuitePlan plan);
}

/// Runs a [SuitePlan] directly, one pickle after another. Used by the
/// compatibility kit harness and future command-line runners.
final class SerialHost implements TestHost {
  /// Creates a serial host.
  const SerialHost();

  @override
  Future<TestRunResult> declare(SuitePlan plan) => run(plan);

  /// Runs every pickle of [plan] and returns the run's result.
  Future<TestRunResult> run(SuitePlan plan) async {
    await plan.start();
    for (final pickle in plan.pickles) {
      if (plan.beforeAllFailed) break;
      await plan.runPickle(pickle);
    }
    return plan.finish();
  }
}
