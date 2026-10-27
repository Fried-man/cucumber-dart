// The phases the benchmark times. See benchmark/benchmark.dart for the command
// line and docs/performance.md for the results.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/discovery.dart';
import 'package:cucumber/src/suite.dart' show findPackageRoot;
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_html_formatter/cucumber_html_formatter.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;

import 'generator.dart';
import 'glue.dart';

/// What to run.
final class BenchmarkConfig {
  /// Creates a configuration.
  const BenchmarkConfig({
    required this.shape,
    this.repeat = 5,
    this.dartTest = true,
    this.dartTestRepeat = 3,
    this.output = 'build/benchmark',
  });

  /// The size of the generated suite.
  final SuiteShape shape;

  /// How many timed repetitions of each in-process phase (after one warm-up).
  final int repeat;

  /// Whether to time `dart test` runs too.
  final bool dartTest;

  /// How many times to run each `dart test` variant.
  final int dartTestRepeat;

  /// Where the suite is generated, relative to the package root of
  /// `package:cucumber`.
  final String output;
}

/// The timings of one phase.
final class PhaseResult {
  /// Creates the result of [name] from its timed [samples].
  PhaseResult(this.name, this.samples, {this.note = ''})
    : assert(samples.isNotEmpty);

  /// The phase.
  final String name;

  /// The duration of each timed repetition.
  final List<Duration> samples;

  /// What the phase covers.
  final String note;

  /// The median sample.
  Duration get median {
    final sorted = [...samples]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) ~/ 2;
  }

  /// The fastest sample.
  Duration get min => samples.reduce((a, b) => a < b ? a : b);

  /// As JSON, in milliseconds.
  Map<String, Object?> toJson() => {
    'name': name,
    'medianMs': median.inMicroseconds / 1000,
    'minMs': min.inMicroseconds / 1000,
    'samplesMs': [for (final s in samples) s.inMicroseconds / 1000],
  };
}

/// The counts of the generated suite.
final class SuiteCounts {
  /// Creates counts.
  const SuiteCounts({
    required this.features,
    required this.pickles,
    required this.steps,
    required this.stepDefinitions,
    required this.hooks,
    required this.envelopes,
    required this.ndjsonBytes,
  });

  /// Feature files.
  final int features;

  /// Pickles (scenarios and example rows), which are tests under `dart test`.
  final int pickles;

  /// Pickle steps.
  final int steps;

  /// Step definitions.
  final int stepDefinitions;

  /// Hooks.
  final int hooks;

  /// Messages of a run.
  final int envelopes;

  /// The size of the run's NDJSON.
  final int ndjsonBytes;

  /// As JSON.
  Map<String, Object?> toJson() => {
    'features': features,
    'pickles': pickles,
    'steps': steps,
    'stepDefinitions': stepDefinitions,
    'hooks': hooks,
    'envelopes': envelopes,
    'ndjsonBytes': ndjsonBytes,
  };
}

/// The result of a benchmark run.
final class BenchmarkResult {
  /// Creates a result.
  const BenchmarkResult(this.counts, this.phases, this.dartTest);

  /// The size of the suite.
  final SuiteCounts counts;

  /// The in-process phases.
  final List<PhaseResult> phases;

  /// The `dart test` runs (empty unless enabled).
  final List<DartTestResult> dartTest;

  /// As JSON.
  Map<String, Object?> toJson() => {
    'dart': Platform.version,
    'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'processors': Platform.numberOfProcessors,
    'counts': counts.toJson(),
    'phases': [for (final phase in phases) phase.toJson()],
    'dartTest': [for (final run in dartTest) run.toJson()],
  };
}

/// The timings of a `dart test` variant.
final class DartTestResult {
  /// Creates a result.
  DartTestResult(this.name, this.wall, this.load, this.tests, this.passed);

  /// The variant.
  final String name;

  /// The process's wall time.
  final PhaseResult wall;

  /// For the JSON reporter, the time until the test file was loaded
  /// (compiled, `main()` declared the suite, and `package:test` received
  /// the tests), as the reporter reports it.
  final PhaseResult? load;

  /// The number of tests that ran (in the last run).
  final int tests;

  /// The number of tests that passed (in the last run).
  final int passed;

  /// As JSON.
  Map<String, Object?> toJson() => {
    'name': name,
    'wall': wall.toJson(),
    'load': load?.toJson(),
    'tests': tests,
    'passed': passed,
  };
}

/// Times [body]: one warm-up run, then [repeat] timed runs. [setUp] runs
/// before each run, outside the timing, and its result is passed to [body].
Future<PhaseResult> timePhase<T>(
  String name,
  int repeat,
  FutureOr<T> Function() setUp,
  FutureOr<void> Function(T value) body, {
  String note = '',
}) async {
  final samples = <Duration>[];
  for (var i = 0; i <= repeat; i++) {
    final value = await setUp();
    final stopwatch = Stopwatch()..start();
    await body(value);
    stopwatch.stop();
    if (i > 0) samples.add(stopwatch.elapsed);
  }
  return PhaseResult(name, samples, note: note);
}

/// The package root of `package:cucumber`.
String get cucumberPackageRoot => findPackageRoot(Directory.current.path);

/// Generates the suite of [config] and times every phase. [log] receives
/// progress.
Future<BenchmarkResult> runBenchmark(
  BenchmarkConfig config, {
  void Function(String line)? log,
}) async {
  final root = cucumberPackageRoot;
  final output = p.join(root, config.output);
  final featuresDirectory = p.join(output, 'features');
  final baselineDirectory = p.join(output, 'baseline');
  log?.call('Generating ${config.shape} in $output');
  generateSuite(config.shape, featuresDirectory);
  generateBaseline(baselineDirectory);
  final locations = [p.relative(featuresDirectory, from: root)];

  final sources = discoverFeatures(locations, packageRoot: root).sources;
  final repeat = config.repeat;
  final phases = <PhaseResult>[];
  Future<void> phase(Future<PhaseResult> result) async {
    final value = await result;
    phases.add(value);
    log?.call(
      '  ${value.name.padRight(24)} median ${_ms(value.median)}, '
      'min ${_ms(value.min)}',
    );
  }

  log?.call('In-process phases (median of $repeat after a warm-up):');
  await phase(
    timePhase(
      'discover + read',
      repeat,
      () {},
      (_) => discoverFeatures(locations, packageRoot: root),
      note: 'discoverFeatures: list and read the feature files',
    ),
  );
  await phase(
    timePhase(
      'parse',
      repeat,
      () {},
      (_) => SourceLoader(IdScheme.deterministic()).loadAll(sources),
      note: 'SourceLoader: Gherkin parse, pickles and AST index',
    ),
  );
  await phase(
    timePhase(
      'glue loading',
      repeat,
      () {},
      (_) => SupportCodeLibrary.load<WarehouseWorld>(
        warehouseGlue(),
        ids: IdScheme.deterministic(),
      ),
      note: 'construct the glue values and SupportCodeLibrary.load',
    ),
  );
  SuitePlan plan([List<Plugin> plugins = const []]) =>
      SuitePlan.create<WarehouseWorld>(
        features: sources,
        glue: warehouseGlue(),
        world: WarehouseWorld.new,
        plugins: plugins,
      );
  await phase(
    timePhase(
      'SuitePlan.create',
      repeat,
      () {},
      (_) => plan(),
      note: 'parse, glue loading, filter, order and plan tree',
    ),
  );

  var envelopes = <messages.Envelope>[];
  var ndjsonBytes = 0;
  await phase(
    timePhase(
      'SerialHost run',
      repeat,
      plan,
      (SuitePlan plan) async {
        final result = await const SerialHost().run(plan);
        if (!result.success) throw StateError('The benchmark suite failed.');
      },
      note: 'assemble and run every test case, no plugins',
    ),
  );
  await phase(
    timePhase(
      'SerialHost run + NDJSON',
      repeat,
      () {
        final collected = <messages.Envelope>[];
        var bytes = 0;
        return (
          plan([
            CallbackPlugin((envelope) {
              collected.add(envelope);
              bytes +=
                  utf8.encode(messages.envelopeToJsonString(envelope)).length +
                  1;
            }),
          ]),
          () => (collected, bytes),
        );
      },
      ((SuitePlan, (List<messages.Envelope>, int) Function()) value) async {
        final (plan, collected) = value;
        await const SerialHost().run(plan);
        (envelopes, ndjsonBytes) = collected();
      },
      note: 'the same, serializing every message to NDJSON',
    ),
  );
  final ndjson = [
    for (final envelope in envelopes) messages.envelopeToJsonString(envelope),
  ];
  await phase(
    timePhase(
      'parse NDJSON',
      repeat,
      () {},
      (_) {
        for (final (index, line) in ndjson.indexed) {
          messages.parseEnvelopeJson(line, lineNumber: index + 1);
        }
      },
      note: 'read a report part back (as the automatic merge does)',
    ),
  );
  await phase(
    timePhase(
      'mergeReportParts',
      repeat,
      () {},
      (_) => mergeReportParts([ReportPart('benchmark', envelopes)]),
      note: 'merge the run as one report part',
    ),
  );
  await phase(
    timePhase('HTML report', repeat, () {}, (_) {
      final writer = MessagesToHtmlWriter(_CountingSink());
      envelopes.forEach(writer.write);
      writer.close();
    }, note: 'MessagesToHtmlWriter to an in-memory sink'),
  );
  await phase(
    timePhase(
      'summary',
      repeat,
      () {},
      (_) => formatSummaryOf(envelopes),
      note: 'formatSummaryOf the run',
    ),
  );

  final created = plan();
  final counts = SuiteCounts(
    features: sources.length,
    pickles: created.pickles.length,
    steps: created.pickles.fold(
      0,
      (sum, node) => sum + node.pickle.steps.length,
    ),
    stepDefinitions: created.library.stepDefinitions.length,
    hooks:
        created.library.beforeHooks.length +
        created.library.afterHooks.length +
        created.library.beforeStepHooks.length +
        created.library.afterStepHooks.length +
        created.library.beforeAllHooks.length +
        created.library.afterAllHooks.length,
    envelopes: envelopes.length,
    ndjsonBytes: ndjsonBytes,
  );
  await created.finish();

  final dartTest = <DartTestResult>[];
  if (config.dartTest) {
    log?.call(
      'dart test benchmark/suite_test.dart (median of '
      '${config.dartTestRepeat}):',
    );
    final reports = p.join(config.output, 'reports');
    final suite = {'CUCUMBER_FEATURES': locations.single};
    for (final (name, environment, json) in [
      (
        'baseline (1 scenario)',
        {'CUCUMBER_FEATURES': p.relative(baselineDirectory, from: root)},
        false,
      ),
      ('suite', suite, false),
      (
        'suite + reports',
        {
          ...suite,
          'CUCUMBER_PLUGIN': [
            'message:${p.join(reports, 'messages.ndjson')}',
            'html:${p.join(reports, 'report.html')}',
            'summary',
          ].join(','),
        },
        false,
      ),
      ('suite, JSON reporter (IDEs)', suite, true),
    ]) {
      final result = await _timeDartTest(
        name,
        config.dartTestRepeat,
        root,
        environment,
        json: json,
      );
      dartTest.add(result);
      final load = result.load;
      log?.call(
        '  ${name.padRight(28)} wall ${_ms(result.wall.median)}'
        '${load == null ? '' : ', loaded after ${_ms(load.median)}'}, '
        '${result.passed}/${result.tests} tests passed',
      );
    }
  }
  return BenchmarkResult(counts, phases, dartTest);
}

/// The summary line of the expanded reporter, such as `+3000: All tests
/// passed!` or `+2 ~1 -1: Some tests failed.`
final RegExp _summaryLine = RegExp(
  r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: (?:All tests passed!|Some tests failed\.)',
);

/// Runs `dart test benchmark/suite_test.dart` [repeat] times with
/// [environment], with the expanded reporter or, if [json], the JSON
/// reporter (which IDEs use, and which makes `package:test` record a stack
/// trace for every test and group).
Future<DartTestResult> _timeDartTest(
  String name,
  int repeat,
  String root,
  Map<String, String> environment, {
  required bool json,
}) async {
  final wall = <Duration>[];
  final load = <Duration>[];
  var tests = 0;
  var passed = 0;
  for (var i = 0; i < repeat; i++) {
    final stopwatch = Stopwatch()..start();
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'test',
        '--reporter',
        json ? 'json' : 'expanded',
        'benchmark/suite_test.dart',
      ],
      workingDirectory: root,
      environment: {
        for (final key in Platform.environment.keys)
          if (key.toUpperCase().startsWith('CUCUMBER_')) key: '',
        ...environment,
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    stopwatch.stop();
    final stdout = '${result.stdout}';
    final summary = _summaryLine.allMatches(stdout).lastOrNull;
    final report = json ? _JsonReport(stdout) : null;
    if (result.exitCode != 0 ||
        (json ? report!.loaded == null : summary == null)) {
      throw StateError(
        'dart test ($name) exited with ${result.exitCode}.\n'
        '${result.stderr}\n'
        '${report?.errors.take(5).join('\n') ?? stdout}',
      );
    }
    wall.add(stopwatch.elapsed);
    if (report != null) {
      load.add(report.loaded!);
      tests = report.tests;
      passed = report.passed;
    } else {
      passed = int.parse(summary![1]!);
      tests =
          passed + int.parse(summary[2] ?? '0') + int.parse(summary[3] ?? '0');
    }
  }
  return DartTestResult(
    name,
    PhaseResult('$name: wall', wall),
    json ? PhaseResult('$name: load', load) : null,
    tests,
    passed,
  );
}

/// The events of `dart test --reporter json` that the benchmark uses.
final class _JsonReport {
  _JsonReport(String stdout) {
    final loading = <int>{};
    for (final line in const LineSplitter().convert(stdout)) {
      if (!line.startsWith('{')) continue;
      final Object? event;
      try {
        event = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (event is! Map<String, Object?>) continue;
      switch (event['type']) {
        case 'testStart':
          final test = event['test']! as Map<String, Object?>;
          if ('${test['name']}'.startsWith('loading ')) {
            loading.add(test['id']! as int);
          }
        case 'testDone':
          if (loading.contains(event['testID'])) {
            loaded = Duration(milliseconds: event['time']! as int);
          } else if (event['hidden'] != true) {
            tests++;
            if (event['result'] == 'success' && event['skipped'] != true) {
              passed++;
            }
          }
        case 'error':
          errors.add('${event['error']}');
      }
    }
  }

  Duration? loaded;
  int tests = 0;
  int passed = 0;
  final List<String> errors = [];
}

final class _CountingSink implements StringSink {
  int length = 0;

  @override
  void write(Object? object) => length += '$object'.length;

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => length++;

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

String _ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';
