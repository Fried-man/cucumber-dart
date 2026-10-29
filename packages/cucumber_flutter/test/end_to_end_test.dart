// Runs `flutter test` on fixtures/e2e and on the example app.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/flutter_test_runner.dart';

void main() {
  group('flutter test on two entry files', () {
    final directory = projectDirectory('fixtures/e2e');
    final build = p.join(directory, 'build');
    late FlutterTestRun run;

    setUpAll(() async {
      if (Directory(build).existsSync()) {
        Directory(build).deleteSync(recursive: true);
      }
      // Without CUCUMBER_RUN_ID: the parts of the two test processes are
      // correlated through flutter test's font configuration file.
      run = await runFlutterTest(directory);
    });

    test('fails because scenarios fail', () {
      expect(run.exitCode, 1, reason: run.describe());
    });

    test('maps outcomes', () {
      expect(
        {
          for (final name in [
            'passed',
            'failed',
            'widget exception',
            'undefined',
            'pending',
            'skipped',
            'flaky',
          ])
            name: run.test('Outcomes $name').outcome,
          'second': run.test('Second file from the second entry file').outcome,
        },
        {
          'passed': 'passed',
          'failed': 'failed',
          'widget exception': 'failed',
          'undefined': 'failed',
          'pending': 'failed',
          'skipped': 'skipped',
          'flaky': 'passed',
          'second': 'passed',
        },
        reason: run.describe(),
      );
    });

    test('an exception reported by Flutter fails its step', () {
      final test = run.test('Outcomes widget exception');
      expect(test.output, contains('Bad state: broken widget'));
      expect(
        test.prints.join('\n'),
        contains(
          'Failed step in scenario "widget exception" '
          '(features/outcomes.feature:13):\n'
          '  Given a widget that throws while building '
          '(features/outcomes.feature:14): Bad state: broken widget',
        ),
      );
    });

    test('undefined steps get snippets with a FlutterWorld', () {
      expect(
        run.test('Outcomes undefined').output,
        contains("Given('a step nobody wrote', (FlutterWorld world) {"),
      );
    });

    test('skipped scenarios are skipped with the reason', () {
      expect(
        run.test('Outcomes skipped').prints,
        contains(
          'Skipped at Given a skipped step (features/outcomes.feature:24): '
          'not here',
        ),
      );
    });

    test('groups are located in the feature files, tests are not', () {
      final group = run.group('Outcomes');
      expect(group.url, endsWith('/fixtures/e2e/features/outcomes.feature'));
      expect(group.line, 1);
      // flutter_test's testWidgets takes no location: the test points at
      // testWidgets, called by the cucumberWidgets call in the entry file.
      final test = run.test('Outcomes passed');
      expect(test.url, 'package:flutter_test/src/widget_tester.dart');
      expect(test.rootUrl, endsWith('/fixtures/e2e/test/outcomes_test.dart'));
      expect(test.rootLine, 5);
    });

    test('prints the summary of each suite', () {
      final summaries = run.printsOf('(tearDownAll)');
      expect(
        summaries,
        contains(
          '7 scenarios (2 failed, 1 undefined, 1 pending, 1 skipped, '
          '2 passed)',
        ),
      );
      expect(summaries, contains('1 scenario (1 passed)'));
    });

    test('writes one part per test file, in one run directory', () {
      final runs = Directory(
        p.join(build, '.cucumber', 'parts'),
      ).listSync().whereType<Directory>().toList();
      expect(runs, hasLength(1));
      expect(p.basename(runs.single.path), matches(r'^flutter-[0-9a-f]{8}$'));
      expect(
        [
          for (final file in runs.single.listSync())
            if (file.path.endsWith('.ndjson')) p.basename(file.path),
        ]..sort(),
        ['outcomes_test.ndjson', 'second_test.ndjson'],
      );
    });

    test('leaves one merged NDJSON report with every scenario', () {
      final envelopes = readNdjson(
        p.join(build, 'cucumber', 'messages.ndjson'),
      );
      expect(ofType(envelopes, 'testRunStarted'), hasLength(1));
      expect(ofType(envelopes, 'testRunFinished').single['success'], isFalse);
      expect(
        {for (final source in ofType(envelopes, 'source')) source['uri']},
        {'features/outcomes.feature', 'features/second.feature'},
      );
      // 8 scenarios, 2 of them retried once; then the flaky one passed.
      expect(ofType(envelopes, 'testCaseStarted'), hasLength(8 + 3));
      expect(
        {
          for (final started in ofType(envelopes, 'testCaseStarted'))
            started['workerId'],
        },
        {'outcomes_test', 'second_test'},
      );
      final failed = [
        for (final finished in ofType(envelopes, 'testStepFinished'))
          if ((finished['testStepResult']! as Map)['status'] == 'FAILED')
            '${(finished['testStepResult']! as Map)['message']}',
      ];
      // The error taken from Flutter, without frames of cucumber_flutter.
      expect(
        failed,
        contains('Bad state: broken widget\nfeatures/outcomes.feature:14'),
      );
      expect(
        [
          for (final attachment in ofType(envelopes, 'attachment'))
            attachment['body'],
        ],
        containsAll(['After passed: 1', 'After from the second entry file: 1']),
      );
    });

    test('leaves the HTML report', () {
      final html = File(
        p.join(build, 'cucumber', 'report.html'),
      ).readAsStringSync();
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('from the second entry file'));
      expect(html, endsWith('</html>\n'));
    });
  });

  test('flutter test --tags runs the tagged scenarios', () async {
    final run = await runFlutterTest(
      projectDirectory('fixtures/e2e'),
      arguments: ['--tags', 'smoke', 'test/outcomes_test.dart'],
    );
    expect(run.exitCode, 0, reason: run.describe());
    expect(
      [
        for (final test in run.tests.values)
          if (!test.name.startsWith('(') && !test.name.startsWith('loading'))
            '${test.outcome} ${test.name}',
      ],
      ['passed Outcomes passed'],
    );
  });

  test('the example app passes', () async {
    final directory = projectDirectory('example');
    final run = await runFlutterTest(directory);
    expect(run.exitCode, 0, reason: run.describe());
    expect(run.printsOf('(tearDownAll)'), contains('5 scenarios (5 passed)'));
    final envelopes = readNdjson(
      p.join(directory, 'build', 'cucumber', 'messages.ndjson'),
    );
    expect(ofType(envelopes, 'testCaseFinished'), hasLength(5));
    expect(ofType(envelopes, 'testRunFinished').single['success'], isTrue);
  });
}
