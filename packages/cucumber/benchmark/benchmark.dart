// Times cucumber-dart on a large generated suite (docs/performance.md).
//
// From packages/cucumber:
//
//   dart run benchmark/benchmark.dart                 # the default size
//   dart run benchmark/benchmark.dart --features 50   # a smaller suite
//   dart run benchmark/benchmark.dart --no-dart-test  # in-process phases only
//   dart run benchmark/benchmark.dart --json build/benchmark/results.json
//
// It generates the features into build/benchmark/features/, times the
// in-process phases (discovery, parsing, glue loading, SuitePlan creation, a
// SerialHost run, and the report work done when a suite ends), then times
// `dart test benchmark/suite_test.dart` on a one-scenario baseline, on the
// suite, on the suite with the NDJSON, HTML and summary reports, and on the
// suite with the JSON reporter that IDEs use.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'src/generator.dart';
import 'src/phases.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('features', defaultsTo: '300', help: 'Feature files.')
    ..addOption(
      'scenarios',
      defaultsTo: '10',
      help: 'Pickles per feature (from 4, 3 of them are example rows).',
    )
    ..addOption(
      'repeat',
      defaultsTo: '5',
      help: 'Timed repetitions of each in-process phase.',
    )
    ..addFlag('dart-test', defaultsTo: true, help: 'Time `dart test` runs.')
    ..addOption(
      'dart-test-repeat',
      defaultsTo: '3',
      help: 'Runs of each `dart test` variant.',
    )
    ..addOption('json', help: 'Also write the results to this file.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(parser.usage);
    exitCode = 2;
    return;
  }
  if (options.flag('help')) {
    stdout
      ..writeln('Usage: dart run benchmark/benchmark.dart [options]')
      ..writeln(parser.usage);
    return;
  }
  int count(String name) {
    final value = int.tryParse(options.option(name)!);
    if (value == null || value < 1) {
      throw FormatException('--$name must be a positive integer.');
    }
    return value;
  }

  final config = BenchmarkConfig(
    shape: SuiteShape(
      features: count('features'),
      scenarios: count('scenarios'),
    ),
    repeat: count('repeat'),
    dartTest: options.flag('dart-test'),
    dartTestRepeat: count('dart-test-repeat'),
  );
  final result = await runBenchmark(config, log: stdout.writeln);
  final c = result.counts;
  stdout
    ..writeln()
    ..writeln(
      'Suite: ${c.features} features, ${c.pickles} pickles, ${c.steps} steps, '
      '${c.stepDefinitions} step definitions, ${c.hooks} hooks; a run emits '
      '${c.envelopes} messages (${(c.ndjsonBytes / 1e6).toStringAsFixed(1)} MB '
      'of NDJSON).',
    )
    ..writeln('Dart ${Platform.version}')
    ..writeln(
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
      '${Platform.numberOfProcessors} processors',
    );
  if (options.option('json') case final path?) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
      );
    stdout.writeln('Wrote $path');
  }
}
