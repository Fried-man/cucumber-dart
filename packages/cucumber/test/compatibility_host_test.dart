// Runs Cucumber Compatibility Kit samples through the real dart test host
// (fixtures/cck) and compares the NDJSON it writes with the expected messages,
// using the harness of packages/cucumber_core/test/compatibility (design §10).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../cucumber_core/test/compatibility/cck.dart';
import 'support/dart_test_runner.dart';

/// Samples that pass through the SerialHost but cannot through dart test.
const Map<String, String> _notThroughDartTest = {
  'empty':
      'declares no tests, so package:test never runs setUpAll and nothing is '
      'written (design §6)',
};

final String _fixture = fixtureDirectory('cck');

void main() {
  final samples = [
    for (final dir in sampleDirectories())
      if (!skippedSamples.containsKey(sampleName(dir)) &&
          !_notThroughDartTest.containsKey(sampleName(dir)))
        dir,
  ];
  late DartTestRun run;

  setUpAll(() async {
    final target = Directory(p.join(_fixture, 'samples'));
    if (target.existsSync()) target.deleteSync(recursive: true);
    for (final dir in samples) {
      final copy = Directory(p.join(target.path, sampleName(dir)))
        ..createSync(recursive: true);
      for (final file in dir.listSync().whereType<File>()) {
        file.copySync(p.join(copy.path, p.basename(file.path)));
      }
    }
    final build = Directory(p.join(_fixture, 'build'));
    if (build.existsSync()) build.deleteSync(recursive: true);

    run = await runDartTest(
      _fixture,
      environment: {'CCK_SAMPLES': samples.map(sampleName).join(',')},
    );
  });

  test('the samples ran', () {
    expect(run.featureTests, isNotEmpty, reason: run.describe());
  });

  for (final dir in samples) {
    final name = sampleName(dir);
    test(name, () {
      final file = File(p.join(_fixture, 'build', 'cck', '$name.ndjson'));
      expect(file.existsSync(), isTrue, reason: run.describe());
      final actual = readNdjson(file.path);
      final problems = [
        ...compareMessages(expectedMessages(dir), actual),
        ...partialOrderProblems(actual),
      ];
      if (problems.isNotEmpty) {
        fail('${problems.length} problem(s):\n\n${problems.join('\n\n')}');
      }

      // package:test saw the same outcomes as the messages report.
      final tests = [
        for (final t in run.featureTests)
          if (t.name.startsWith('$name ')) t.outcome,
      ];
      expect(tests, hasLength(ofType(actual, 'pickle').length));
      expect(tests..sort(), _expectedOutcomes(actual)..sort());
    });
  }
}

/// The `package:test` outcome of each pickle, from the final attempts in
/// [envelopes]: PASSED passes, SKIPPED is skipped, the rest fail (as do
/// pickles that never ran because a `BeforeAll` hook failed).
List<String> _expectedOutcomes(List<Map<String, Object?>> envelopes) {
  final testCaseOfStarted = {
    for (final s in ofType(envelopes, 'testCaseStarted'))
      s['id']! as String: s['testCaseId']! as String,
  };
  final statuses = <String, List<String>>{};
  for (final f in ofType(envelopes, 'testStepFinished')) {
    final result = f['testStepResult']! as Map<String, Object?>;
    (statuses[f['testCaseStartedId']! as String] ??= []).add(
      result['status']! as String,
    );
  }
  const severity = [
    'UNKNOWN',
    'PASSED',
    'SKIPPED',
    'PENDING',
    'UNDEFINED',
    'AMBIGUOUS',
    'FAILED',
  ];
  final outcomes = <String>[];
  for (final f in ofType(envelopes, 'testCaseFinished')) {
    if (f['willBeRetried'] == true) continue;
    final started = f['testCaseStartedId']! as String;
    assert(testCaseOfStarted.containsKey(started));
    final worst = (statuses[started] ?? const ['PASSED']).fold(
      'PASSED',
      (a, b) => severity.indexOf(b) > severity.indexOf(a) ? b : a,
    );
    outcomes.add(switch (worst) {
      'PASSED' => 'passed',
      'SKIPPED' => 'skipped',
      _ => 'failed',
    });
  }
  final notRun = ofType(envelopes, 'pickle').length - outcomes.length;
  return [...outcomes, for (var i = 0; i < notRun; i++) 'failed'];
}
