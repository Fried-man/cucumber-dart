// Runs `dart test` on the fixture projects in fixtures/e2e and fixtures/merge
// and checks what package:test reports (JSON reporter) and what Cucumber
// writes (NDJSON, HTML, merged report parts).
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../cucumber_core/test/compatibility/cck.dart'
    show partialOrderProblems;
import 'support/dart_test_runner.dart';

final String _fixture = fixtureDirectory('e2e');

String _build(String file) => p.join(_fixture, 'build', 'cucumber', file);

void _clean() {
  final build = Directory(p.join(_fixture, 'build'));
  if (build.existsSync()) build.deleteSync(recursive: true);
}

void main() {
  group('dart test on a fixture project', () {
    late DartTestRun run;
    late List<Map<String, Object?>> envelopes;

    setUpAll(() async {
      _clean();
      run = await runDartTest(
        _fixture,
        environment: {'CUCUMBER_WORLD_PARAMETERS': '{"source": "env"}'},
      );
      envelopes = readNdjson(_build('messages.ndjson'));
    });

    test('fails because scenarios fail', () {
      expect(run.exitCode, 1, reason: run.describe());
    });

    test('declares one test per scenario and example row', () {
      expect(
        [for (final t in run.featureTests) t.name],
        unorderedEquals([
          // test/cucumber_test.dart: every feature file, with a test for the
          // one that does not parse, and without @wip (cucumber.yaml).
          'features/broken.feature',
          'Other one',
          'Other two',
          'Shop passing',
          'Shop failing',
          'Shop pending',
          'Shop undefined',
          'Shop ambiguous',
          'Shop skipped',
          'Shop flaky',
          'Shop world parameters',
          'Shop Payments pay with <method> Cards Example #1.1: pay with visa',
          'Shop Payments pay with <method> Cards Example #1.2: pay with amex',
          'Shop Payments pay with <method> Examples Example #2.1: pay with cash',
          // test/before_all_test.dart: features/more/other.feature:3.
          'Other one',
        ]),
      );
    });

    test('locates groups and tests in the feature files', () {
      void expectFile(String? url, String file) {
        expect(url, endsWith('/fixtures/e2e/features/$file'));
        expect(Uri.parse(url!).isScheme('file'), isTrue);
      }

      const row =
          'Shop Payments pay with <method> Cards Example #1.2: pay with amex';
      final locations = <String, (int?, int?)>{};
      for (final name in [
        'Shop',
        'Shop Payments',
        'Shop Payments pay with <method>',
        'Shop Payments pay with <method> Cards',
      ]) {
        final group = run.group(name);
        expectFile(group.url, 'shop.feature');
        locations[name] = (group.line, group.column);
      }
      for (final name in ['Shop failing', row]) {
        final test = run.test(name);
        expectFile(test.url, 'shop.feature');
        locations[name] = (test.line, test.column);
      }
      final broken = run.test('features/broken.feature');
      expectFile(broken.url, 'broken.feature');
      locations['features/broken.feature'] = (broken.line, broken.column);

      expect(locations, {
        'Shop': (2, 1),
        'Shop Payments': (41, 3),
        'Shop Payments pay with <method>': (44, 5),
        'Shop Payments pay with <method> Cards': (47, 7),
        'Shop failing': (12, 3),
        row: (50, 9),
        'features/broken.feature': (4, 3),
      });
    });

    test('maps outcomes', () {
      final outcomes = {
        for (final t in run.featureTests)
          if (t.name.startsWith('Shop') || t.name.startsWith('features/'))
            t.name: t.outcome,
      };
      expect(outcomes, {
        'features/broken.feature': 'failed',
        'Shop passing': 'passed',
        'Shop failing': 'failed',
        'Shop pending': 'failed',
        'Shop undefined': 'failed',
        'Shop ambiguous': 'failed',
        'Shop skipped': 'skipped',
        'Shop flaky': 'passed',
        'Shop world parameters': 'passed',
        'Shop Payments pay with <method> Cards Example #1.1: pay with visa':
            'passed',
        'Shop Payments pay with <method> Cards Example #1.2: pay with amex':
            'passed',
        'Shop Payments pay with <method> Examples Example #2.1: pay with cash':
            'passed',
      });
    });

    test('FAILED rethrows the original error after printing the context', () {
      final failing = run.test('Shop failing');
      expect(
        failing.result,
        'error',
        reason: 'StateError is not a TestFailure',
      );
      expect(failing.errors.single, startsWith('Bad state: boom\n'));
      expect(failing.errors.single, contains('shop_glue.dart'));
      expect(
        failing.prints.join('\n'),
        allOf(
          contains(
            'Failed step in scenario "failing" (features/shop.feature:12)',
          ),
          contains('When a step fails with "boom" (features/shop.feature:14)'),
          contains('(after 2 attempts)'),
        ),
      );
    });

    test('PENDING, UNDEFINED and AMBIGUOUS fail with a TestFailure', () {
      final pending = run.test('Shop pending');
      expect(pending.result, 'failure');
      expect(
        pending.errors.single,
        allOf(
          contains('Pending step in scenario "pending"'),
          contains('Given a pending step (features/shop.feature:18)'),
          contains('not built yet'),
        ),
      );

      final undefined = run.test('Shop undefined');
      expect(undefined.result, 'failure');
      expect(
        undefined.errors.single,
        allOf(
          contains(
            'And an undefined step with 3 cukes (features/shop.feature:22)',
          ),
          contains('Implement it with this snippet:'),
          contains(
            "Given('an undefined step with {int} cukes', "
            '(ShopWorld world, int int1) {',
          ),
          contains('throw PendingException();'),
        ),
      );

      final ambiguous = run.test('Shop ambiguous');
      expect(ambiguous.result, 'failure');
      expect(
        ambiguous.errors.single,
        allOf(
          contains('Multiple step definitions match "an ambiguous step"'),
          contains('shop_glue.dart'),
        ),
      );
    });

    test('SKIPPED is marked skipped with the reason', () {
      final skipped = run.test('Shop skipped');
      expect(skipped.errors, isEmpty);
      expect(
        skipped.prints.join('\n'),
        contains(
          'Skipped at Given a step skips (features/shop.feature:29): '
          'not today',
        ),
      );
    });

    test('a parse error is a failing test', () {
      final broken = run.test('features/broken.feature');
      expect(broken.result, 'failure');
      expect(
        broken.errors.single,
        contains('(4:3): expected: #EOF, #TableRow'),
      );
    });

    test('a failed BeforeAll hook fails every test with the reason', () {
      final tests = [
        for (final t in run.featureTests)
          if (t.name == 'Other one' && t.result != 'success') t,
      ];
      expect(tests, hasLength(1), reason: run.describe());
      expect(
        tests.single.errors.single,
        allOf(
          startsWith('Not run because a BeforeAll hook failed.'),
          contains('FAILED BeforeAll hook "database"'),
          contains('Bad state: database is down'),
          contains('before_all_test.dart'),
        ),
      );

      final messages = readNdjson(_build('before_all.ndjson'));
      expect(ofType(messages, 'pickle'), hasLength(2));
      expect(ofType(messages, 'testCase'), isEmpty);
      final hook = ofType(messages, 'testRunHookFinished').single;
      expect((hook['result']! as Map<String, Object?>)['status'], 'FAILED');
      expect(ofType(messages, 'testRunFinished').single['success'], isFalse);
    });

    test('writes the NDJSON report', () {
      String typeOf(Map<String, Object?> e) => e.keys.single;
      expect(typeOf(envelopes.first), 'meta');
      expect(typeOf(envelopes.last), 'testRunFinished');
      expect(envelopes.last['testRunFinished'], containsPair('success', false));

      expect(
        [for (final s in ofType(envelopes, 'source')) s['uri']],
        [
          'features/broken.feature',
          'features/more/other.feature',
          'features/shop.feature',
        ],
      );
      expect(ofType(envelopes, 'parseError'), hasLength(1));
      // Filtered pickles (@wip) are still emitted, but never run.
      final pickles = ofType(envelopes, 'pickle');
      expect(pickles.map((p) => p['name']), contains('work in progress'));
      expect(pickles, hasLength(14));
      expect(ofType(envelopes, 'testCase'), hasLength(13));
    });

    test('writes the HTML report with every message', () {
      expect(
        readHtmlReport(_build('report.html')),
        envelopes,
        reason: 'the report embeds the NDJSON stream, in order',
      );
    });

    test('reports the Dart platform in meta', () {
      final meta = envelopes.first['meta']! as Map<String, Object?>;
      final runtime = meta['runtime']! as Map<String, Object?>;
      expect(runtime['name'], 'Dart');
      expect(runtime['version'], Platform.version.split(' ').first);
      expect(meta['os'], containsPair('name', Platform.operatingSystem));
      expect((meta['cpu']! as Map<String, Object?>)['name'], isNotEmpty);
      expect(meta['implementation'], containsPair('name', 'cucumber-dart'));
    });

    test('retries FAILED scenarios inside the test', () {
      final pickle = ofType(
        envelopes,
        'pickle',
      ).singleWhere((p) => p['name'] == 'flaky');
      final testCase = ofType(
        envelopes,
        'testCase',
      ).singleWhere((t) => t['pickleId'] == pickle['id']);
      final attempts = ofType(
        envelopes,
        'testCaseStarted',
      ).where((s) => s['testCaseId'] == testCase['id']).toList();
      expect([for (final a in attempts) a['attempt']], [0, 1]);
      final finished = {
        for (final f in ofType(envelopes, 'testCaseFinished'))
          f['testCaseStartedId']: f['willBeRetried'],
      };
      expect([for (final a in attempts) finished[a['id']]], [true, false]);
    });

    test('merges world parameters from code, cucumber.yaml and the '
        'environment', () {
      final logs = [
        for (final a in ofType(envelopes, 'attachment'))
          if (a['mediaType'] == 'text/x.cucumber.log+plain')
            jsonDecode(a['body']! as String),
      ];
      expect(logs.single, {
        'source': 'env',
        'fromCode': true,
        'nested': {'a': 1},
      });
    });

    test('prints the summary when each suite ends', () {
      String summaryOf(String file) {
        final teardowns = [
          for (final t in run.tests.values)
            if (t.name == '(tearDownAll)' &&
                p.url.basename(t.suite.replaceAll(r'\', '/')) == file)
              t,
        ];
        expect(teardowns, hasLength(1), reason: run.describe());
        return teardowns.single.prints.join('\n');
      }

      final duration = RegExp(
        r'^\d+m\d\d\.\d{3}s \(executing steps: \d+m\d\d\.\d{3}s\)$',
        multiLine: true,
      );
      final summary = summaryOf('cucumber_test.dart');
      expect(
        summary,
        allOf([
          startsWith(
            'Failures:\n\n'
            '1) Scenario: Shop - failing (attempt 2) # '
            'features/shop.feature:12\n'
            '   PASSED  Given a shop # features/shop.feature:6\n',
          ),
          contains(
            '   FAILED  When a step fails with "boom" # '
            'features/shop.feature:14\n'
            '             Bad state: boom\n',
          ),
          contains('2) Scenario: Shop - pending # features/shop.feature:17\n'),
          contains(
            '3) Scenario: Shop - undefined # features/shop.feature:20\n',
          ),
          contains(
            '4) Scenario: Shop - ambiguous # features/shop.feature:24\n',
          ),
          contains(
            'Warnings:\n\n'
            '1) Scenario: Shop - failing (attempt 1, retried) # '
            'features/shop.feature:12\n',
          ),
          contains('2) Scenario: Shop - skipped # features/shop.feature:28\n'),
          contains(
            '3) Scenario: Shop - flaky (attempt 1, retried) # '
            'features/shop.feature:31\n',
          ),
          contains(
            '\n13 scenarios (1 failed, 1 ambiguous, 1 undefined, 1 pending, '
            '1 skipped, 8 passed)\n'
            '27 steps (1 failed, 1 ambiguous, 1 undefined, 1 pending, '
            '2 skipped, 21 passed)\n',
          ),
          matches(duration),
          endsWith(
            'You can implement missing steps with the snippets below:\n\n'
            "Given('an undefined step with {int} cukes', "
            '(ShopWorld world, int int1) {\n'
            '  // Write code here that turns the phrase above into concrete '
            'actions\n'
            '  throw PendingException();\n'
            '}),\n'
            '// Or use one of these expressions:\n'
            "// Given('an undefined step with {float} cukes', "
            '(ShopWorld world, double float1) {',
          ),
        ]),
      );
      expect(summary, isNot(contains('Shop passing')));

      expect(
        summaryOf('before_all_test.dart'),
        allOf([
          startsWith(
            'Failures:\n\n'
            '1) BeforeAll hook "database" (failed) # '
            'test/before_all_test.dart:',
          ),
          contains('     Bad state: database is down\n'),
          contains('\n0 scenarios\n0 steps\n'),
          matches(duration),
        ]),
      );
    });

    test('delivers the messages to custom plugins', () {
      final counts =
          jsonDecode(File(_build('counts.json')).readAsStringSync())
              as Map<String, Object?>;
      final expected = <String, int>{};
      for (final envelope in envelopes) {
        expected.update(envelope.keys.single, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(counts, expected);
    });
  });

  group('dart test --tags with a profile from CUCUMBER_PROFILE', () {
    late DartTestRun run;

    setUpAll(() async {
      _clean();
      run = await runDartTest(
        _fixture,
        arguments: ['--tags', 'smoke', 'test/cucumber_test.dart'],
        environment: {
          'CUCUMBER_PROFILE': 'ci',
          'CUCUMBER_EXECUTION_ORDER': 'reverse',
        },
      );
    });

    test('runs only the scenarios with that tag, in the configured order', () {
      expect(run.exitCode, 0, reason: run.describe());
      expect(
        [for (final t in run.featureTests) '${t.outcome} ${t.name}'],
        ['skipped Shop skipped', 'passed Shop passing'],
      );
    });

    test('emits test cases only for the tests that ran', () {
      expect(
        File(_build('messages.ndjson')).existsSync(),
        isFalse,
        reason: 'the ci profile replaces the plugins',
      );
      final envelopes = readNdjson(_build('ci.ndjson'));
      expect(ofType(envelopes, 'pickle'), hasLength(14));
      expect(ofType(envelopes, 'testCase'), hasLength(2));
      expect(ofType(envelopes, 'testCaseFinished'), hasLength(2));
      expect(
        envelopes.last['testRunFinished'],
        containsPair('success', false),
        reason: 'features/broken.feature does not parse',
      );
    });

    test('writes the HTML report of cucumber.yaml', () {
      expect(
        File(_build('report.html')).existsSync(),
        isFalse,
        reason: 'the ci profile replaces the plugins',
      );
      expect(
        readHtmlReport(_build('ci.html')),
        readNdjson(_build('ci.ndjson')),
      );
    });
  });

  group('dart test on three entry files', () {
    final fixture = fixtureDirectory('merge');
    String build(String relative) =>
        p.joinAll([fixture, 'build', ...relative.split('/')]);
    late DartTestRun run;
    late List<Map<String, Object?>> envelopes;

    setUpAll(() async {
      final directory = Directory(p.join(fixture, 'build'));
      if (directory.existsSync()) directory.deleteSync(recursive: true);
      // Parts of two earlier runs: one finished long ago, one recent.
      for (final (runId, age) in [('stale', 2 * 24), ('recent', 0)]) {
        File(build('.cucumber/parts/$runId/cart_test.ndjson'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{}\n')
          ..setLastModifiedSync(DateTime.now().subtract(Duration(hours: age)));
      }
      run = await runDartTest(fixture);
      envelopes = readNdjson(build('cucumber/messages.ndjson'));
    });

    /// The directory of this run's parts.
    String runParts() => Directory(
      build('.cucumber/parts'),
    ).listSync().singleWhere((e) => p.basename(e.path) != 'recent').path;

    /// Runs `dart run cucumber:merge [arguments]` in the fixture.
    Future<ProcessResult> merge(List<String> arguments) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'cucumber:merge', ...arguments],
      workingDirectory: fixture,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    String describe(ProcessResult result) =>
        'exit code ${result.exitCode}\nstdout:\n${result.stdout}\n'
        'stderr:\n${result.stderr}';

    const scenarios = {
      'add an item',
      'remove an item',
      'shared by cart',
      'pay',
      'ship to France',
      'ship to Japan',
      'find an item',
      'shared by search',
    };

    test('runs every scenario', () {
      expect(run.exitCode, 0, reason: run.describe());
      expect(run.featureTests, hasLength(scenarios.length));
    });

    test('writes one part per suite, named after the suite', () {
      expect(
        p.basename(runParts()),
        matches(RegExp(r'^\d+$')),
        reason: 'the run ID is the process ID of dart test',
      );
      expect(
        [
          for (final file in Directory(runParts()).listSync())
            p.basename(file.path),
        ]..sort(),
        [
          'cart_test.json',
          'cart_test.ndjson',
          'checkout.json',
          'checkout.ndjson',
          'search_test.json',
          'search_test.ndjson',
        ],
      );
      expect(
        [
          for (final file in Directory(build('.cucumber')).listSync())
            p.basename(file.path),
        ]..sort(),
        ['merge.lock', 'parts'],
        reason: 'merge lock guards are removed',
      );
      expect(
        [
          for (final file in Directory(build('cucumber')).listSync())
            p.basename(file.path),
        ]..sort(),
        ['messages.ndjson', 'report.html'],
        reason: 'temporary files are renamed',
      );
    });

    test('leaves one merged NDJSON report with every scenario', () {
      List<String> types(String type) => [
        for (final e in envelopes)
          if (e.keys.single == type) type,
      ];
      expect(envelopes.first.keys.single, 'meta');
      expect(types('meta'), hasLength(1));
      expect(types('testRunStarted'), hasLength(1));
      expect(types('testRunFinished'), hasLength(1));
      expect(envelopes.last['testRunFinished'], containsPair('success', true));
      expect(partialOrderProblems(envelopes), isEmpty);

      expect(
        [for (final s in ofType(envelopes, 'source')) s['uri']],
        unorderedEquals([
          'features/cart.feature',
          'features/shared.feature',
          'features/checkout.feature',
          'features/search.feature',
        ]),
        reason: 'features/shared.feature is in two parts, but listed once',
      );
      final pickles = {
        for (final pickle in ofType(envelopes, 'pickle'))
          pickle['id']: pickle['name'],
      };
      expect(ofType(envelopes, 'pickle'), hasLength(pickles.length));
      expect(pickles.values.toSet(), scenarios);
      expect(ofType(envelopes, 'stepDefinition'), hasLength(2));
      expect(ofType(envelopes, 'hook'), hasLength(1));

      final testCases = {
        for (final testCase in ofType(envelopes, 'testCase'))
          testCase['id']: pickles[testCase['pickleId']],
      };
      final suites = <String, Set<Object?>>{};
      for (final started in ofType(envelopes, 'testCaseStarted')) {
        (suites[started['workerId']! as String] ??= {}).add(
          testCases[started['testCaseId']],
        );
      }
      expect(suites, {
        'cart_test': {'add an item', 'remove an item', 'shared by cart'},
        'checkout': {'pay', 'ship to France', 'ship to Japan'},
        'search_test': {'find an item', 'shared by search'},
      });
      expect(
        [for (final h in ofType(envelopes, 'testRunHookStarted')) h['workerId']]
          ..sort(),
        ['cart_test', 'checkout', 'search_test'],
      );
    });

    test('leaves one merged HTML report with every message', () {
      expect(readHtmlReport(build('cucumber/report.html')), envelopes);
    });

    test('prunes the parts of earlier runs unchanged for an hour', () {
      expect([
        for (final run in Directory(build('.cucumber/parts')).listSync())
          p.basename(run.path),
      ], unorderedEquals([p.basename(runParts()), 'recent']));
    });

    test('dart run cucumber:merge merges the parts as the automatic merge '
        'did', () async {
      final result = await merge([
        p.relative(runParts(), from: fixture),
        '-p',
        'message:build/merged/messages.ndjson',
        '-p',
        'html:build/merged/report.html',
        '-p',
        'summary',
      ]);
      expect(result.exitCode, 0, reason: describe(result));
      expect(
        result.stdout,
        matches(RegExp(r'^8 scenarios \(8 passed\)$', multiLine: true)),
      );
      expect(result.stderr, isNot(contains('Warning')));
      expect(readNdjson(build('merged/messages.ndjson')), envelopes);
      expect(readHtmlReport(build('merged/report.html')), envelopes);
    });

    test('dart run cucumber:merge merges the parts of two shards with the '
        'same suite IDs', () async {
      // A second shard that ran the same suites.
      final shard = Directory(build('shard-2'))..createSync();
      for (final file in Directory(runParts()).listSync().whereType<File>()) {
        file.copySync(p.join(shard.path, p.basename(file.path)));
      }
      final result = await merge([
        runParts(),
        'build/shard-2',
        '--plugin=message:build/shards.ndjson',
      ]);
      expect(result.exitCode, 0, reason: describe(result));
      expect(result.stdout, isNot(contains('scenarios')), reason: 'no summary');
      expect(
        result.stderr,
        allOf(
          contains('Note: Suite ID "cart_test" is used by several'),
          contains('is merged as "cart_test#2"'),
          contains('is merged as "checkout#2"'),
          contains('is merged as "search_test#2"'),
          isNot(contains('Warning')),
        ),
      );
      final merged = readNdjson(build('shards.ndjson'));
      expect(partialOrderProblems(merged), isEmpty);
      expect(
        ofType(merged, 'pickle'),
        hasLength(scenarios.length),
        reason: 'static messages are de-duplicated',
      );
      final workers = <Object?, int>{};
      for (final started in ofType(merged, 'testCaseStarted')) {
        workers.update(started['workerId'], (n) => n + 1, ifAbsent: () => 1);
      }
      expect(workers, {
        'cart_test': 3,
        'checkout': 3,
        'search_test': 2,
        'cart_test#2': 3,
        'checkout#2': 3,
        'search_test#2': 2,
      });
      expect(merged.last['testRunFinished'], containsPair('success', true));
    });

    test('dart run cucumber:merge exits with 2 for a usage error', () async {
      final result = await merge(['--plugin', 'junit:out.xml', 'build']);
      expect(result.exitCode, 2, reason: describe(result));
      expect(result.stderr, contains('Error: Unknown plugin "junit:out.xml"'));
    });

    test('prints the summary of each suite', () {
      final summaries = {
        for (final t in run.tests.values)
          if (t.name == '(tearDownAll)')
            p.url.basename(t.suite.replaceAll(r'\', '/')): t.prints.join('\n'),
      };
      expect(summaries, {
        'cart_test.dart': startsWith('3 scenarios (3 passed)\n'),
        'checkout_test.dart': startsWith('3 scenarios (3 passed)\n'),
        'search_test.dart': startsWith('2 scenarios (2 passed)\n'),
      });
    });
  });

  test('the example project passes', () async {
    final example = p.join(cucumberPackageDirectory, 'example');
    final run = await runDartTest(example);
    expect(run.exitCode, 0, reason: run.describe());
    expect(run.featureTests, hasLength(6));
    // cucumber.yaml adds the summary plugin.
    final summary = [
      for (final t in run.tests.values)
        if (t.name == '(tearDownAll)') ...t.prints,
    ].join('\n');
    expect(summary, startsWith('6 scenarios (6 passed)\n'));
    expect(
      summary,
      isNot(contains('Failures:')),
      reason: 'a passing run is only counts and the duration',
    );
    final build = p.join(example, 'build', 'cucumber');
    expect(
      readHtmlReport(p.join(build, 'report.html')),
      readNdjson(p.join(build, 'messages.ndjson')),
    );
  });
}
