// Runs benchmark/benchmark.dart's phases on a tiny suite, so the benchmark
// keeps working (docs/performance.md). It checks what the benchmark measures,
// not how fast it is.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../benchmark/src/generator.dart';
import '../benchmark/src/phases.dart';

void main() {
  test(
    'the benchmark times every phase of a generated suite that passes',
    () async {
      const shape = SuiteShape(features: 3, scenarios: 5);
      const output = 'build/benchmark-test';
      addTearDown(() {
        final directory = Directory(p.join(cucumberPackageRoot, output));
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final result = await runBenchmark(
        const BenchmarkConfig(
          shape: shape,
          repeat: 2,
          dartTestRepeat: 1,
          output: output,
        ),
      );

      final counts = result.counts;
      expect(counts.features, 3);
      expect(counts.pickles, 15);
      // Per feature: 2 scenarios with a background step and 3 or 4 steps, and
      // 3 example rows with a background step and 2 steps.
      expect(counts.steps, 3 * (4 + 5 + 3 * 3));
      expect(counts.stepDefinitions, 200);
      expect(counts.hooks, 6);
      expect(counts.envelopes, greaterThan(counts.pickles * 4));
      expect(counts.ndjsonBytes, greaterThan(0));

      expect(result.phases.map((phase) => phase.name), [
        'discover + read',
        'parse',
        'glue loading',
        'SuitePlan.create',
        'SerialHost run',
        'SerialHost run + NDJSON',
        'parse NDJSON',
        'mergeReportParts',
        'HTML report',
        'summary',
      ]);
      for (final phase in result.phases) {
        expect(phase.samples, hasLength(2), reason: phase.name);
      }

      expect(
        {for (final run in result.dartTest) run.name: run.passed},
        {
          'baseline (1 scenario)': 1,
          'suite': 15,
          'suite + reports': 15,
          'suite, JSON reporter (IDEs)': 15,
        },
      );
      for (final run in result.dartTest) {
        expect(run.tests, run.passed, reason: run.name);
        expect(run.load != null, run.name.contains('JSON'), reason: run.name);
      }
      final reports = p.join(cucumberPackageRoot, output, 'reports');
      expect(File(p.join(reports, 'messages.ndjson')).existsSync(), isTrue);
      expect(File(p.join(reports, 'report.html')).existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('the generated features have the shape asked for', () {
    final text = featureText(7, const SuiteShape(features: 8, scenarios: 6));
    expect(
      RegExp(r'^  Scenario: ', multiLine: true).allMatches(text),
      hasLength(3),
    );
    expect(text, contains('Scenario Outline'));
    expect(
      RegExp(r'^        \| \d', multiLine: true).allMatches(text),
      hasLength(3),
    );
    expect(
      featureText(0, const SuiteShape(features: 1, scenarios: 3)),
      isNot(contains('Scenario Outline')),
    );
  });
}
