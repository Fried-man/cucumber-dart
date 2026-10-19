import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/summary.dart' show formatDuration;
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:cucumber_query/cucumber_query.dart';
import 'package:test/test.dart';

const _shop = '''
Feature: Shop

  Background:
    Given a shop

  Scenario: passing
    Given a step passes

  Scenario: failing
    When a step fails
    Then a step passes

  Scenario: pending
    Given a pending step

  Scenario: undefined
    Given 3 undefined cukes
    And a step passes

  Scenario: ambiguous
    Given an ambiguous step

  Scenario: skipped
    Given a step skips
''';

final _shopGlue = <Glue>[
  Given('a shop', () {}),
  Given('a step passes', () {}),
  When('a step fails', () => throw StateError('boom')),
  Given('a pending step', () => pending('not built yet')),
  Given('an ambiguous step', () {}),
  Given(RegExp(r'^an ambiguous (.*)$'), (String what) {}),
  Given('a step skips', () => skip('not today')),
];

/// A clock that advances one millisecond per reading, and stopwatches that
/// never run, so every step takes no time.
final class _TestPlatform extends CucumberPlatform {
  int _milliseconds = 0;

  @override
  DateTime now() =>
      DateTime.utc(2026, 10, 19).add(Duration(milliseconds: _milliseconds++));

  @override
  Stopwatch startStopwatch() => Stopwatch();
}

/// Runs [features] through the [SerialHost] and returns the messages.
///
/// Error messages of FAILED and AMBIGUOUS steps and hooks are cut to their
/// first line, because the rest (stack traces, glue locations) depends on
/// this file.
Future<List<messages.Envelope>> _run(
  Map<String, String> features,
  List<Glue> glue, {
  int retry = 0,
  bool dryRun = false,
}) async {
  final collector = CollectingPlugin();
  final plan = SuitePlan.create(
    features: [
      for (final MapEntry(:key, :value) in features.entries)
        FeatureSource(key, value),
    ],
    glue: glue,
    options: RunOptions(retry: retry, dryRun: dryRun),
    plugins: [collector],
    platform: _TestPlatform(),
    ids: IdScheme.incrementing(),
  );
  await const SerialHost().run(plan);
  return [for (final envelope in collector.envelopes) _firstLine(envelope)];
}

messages.Envelope _firstLine(messages.Envelope envelope) {
  final json =
      jsonDecode(messages.envelopeToJsonString(envelope))
          as Map<String, Object?>;
  final finished =
      (json['testStepFinished'] ?? json['testRunHookFinished'])
          as Map<String, Object?>?;
  if (finished == null) return envelope;
  final result =
      (finished['testStepResult'] ?? finished['result'])!
          as Map<String, Object?>;
  final message = result['message'] as String?;
  if (message == null ||
      !const {'FAILED', 'AMBIGUOUS'}.contains(result['status'])) {
    return envelope;
  }
  result['message'] = message.split('\n').first;
  return messages.Envelope.fromJson(json);
}

/// [summary] with its duration line replaced by `<duration>`.
String _withoutDuration(String summary) => summary.replaceAll(
  RegExp(
    r'^\d+m\d\d\.\d{3}s \(executing steps: \d+m\d\d\.\d{3}s\)$',
    multiLine: true,
  ),
  '<duration>',
);

Future<String> _summarise(
  Map<String, String> features,
  List<Glue> glue, {
  int retry = 0,
  bool dryRun = false,
}) async => _withoutDuration(
  formatSummaryOf(await _run(features, glue, retry: retry, dryRun: dryRun)),
);

/// The messages of the Cucumber Compatibility Kit sample [name].
List<messages.Envelope> _cck(String name) {
  final library = Isolate.resolvePackageUriSync(
    Uri.parse(
      'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
    ),
  )!;
  final file = File.fromUri(library.resolve('../features/$name/$name.ndjson'));
  return [
    for (final line in file.readAsLinesSync())
      if (line.trim().isNotEmpty)
        messages.Envelope.fromJson(jsonDecode(line) as Map<String, Object?>),
  ];
}

List<String> _cckSamples() {
  final library = Isolate.resolvePackageUriSync(
    Uri.parse(
      'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
    ),
  )!;
  return [
    for (final dir in Directory.fromUri(
      library.resolve('../features/'),
    ).listSync().whereType<Directory>())
      dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
  ]..sort();
}

void main() {
  group('formatSummary', () {
    test('lists failures and warnings, counts, and snippets', () async {
      final summary = await _summarise(
        {'features/shop.feature': _shop},
        _shopGlue,
        retry: 1,
      );
      expect(summary, '''
Failures:

1) Scenario: Shop - failing (attempt 2) # features/shop.feature:9
   PASSED  Given a shop # features/shop.feature:4
   FAILED  When a step fails # features/shop.feature:10
             Bad state: boom
   SKIPPED Then a step passes # features/shop.feature:11

2) Scenario: Shop - pending # features/shop.feature:13
   PASSED  Given a shop # features/shop.feature:4
   PENDING Given a pending step # features/shop.feature:14
             Pending: not built yet

3) Scenario: Shop - undefined # features/shop.feature:16
   PASSED    Given a shop # features/shop.feature:4
   UNDEFINED Given 3 undefined cukes # features/shop.feature:17
               Undefined. Implement it with the snippet below.
   SKIPPED   And a step passes # features/shop.feature:18

4) Scenario: Shop - ambiguous # features/shop.feature:20
   PASSED    Given a shop # features/shop.feature:4
   AMBIGUOUS Given an ambiguous step # features/shop.feature:21
               Multiple step definitions match "an ambiguous step":

Warnings:

1) Scenario: Shop - failing (attempt 1, retried) # features/shop.feature:9
   PASSED  Given a shop # features/shop.feature:4
   FAILED  When a step fails # features/shop.feature:10
             Bad state: boom
   SKIPPED Then a step passes # features/shop.feature:11

2) Scenario: Shop - skipped # features/shop.feature:23
   PASSED  Given a shop # features/shop.feature:4
   SKIPPED Given a step skips # features/shop.feature:24
             Skipped: not today

6 scenarios (1 failed, 1 ambiguous, 1 undefined, 1 pending, 1 skipped, 1 passed)
14 steps (1 failed, 1 ambiguous, 1 undefined, 1 pending, 3 skipped, 7 passed)
<duration>

You can implement missing steps with the snippets below:

Given('{int} undefined cukes', (int int1) {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),
// Or use one of these expressions:
// Given('{float} undefined cukes', (double float1) {''');
    });

    test('a passing run is only counts and the duration', () async {
      final summary = await _summarise({
        'features/a.feature': _passing,
      }, _shopGlue);
      expect(summary, '''
2 scenarios (2 passed)
2 steps (2 passed)
<duration>''');
    });

    test('counts only the final attempt of a retried scenario', () async {
      var attempts = 0;
      final summary = await _summarise(
        {'features/flaky.feature': _flaky},
        [
          Given('a step that passes the third time', () {
            if (++attempts < 3) throw StateError('flaky $attempts');
          }),
        ],
        retry: 2,
      );
      expect(summary, '''
Warnings:

1) Scenario: Flaky - flaky (attempt 1, retried) # features/flaky.feature:3
   FAILED Given a step that passes the third time # features/flaky.feature:4
            Bad state: flaky 1

2) Scenario: Flaky - flaky (attempt 2, retried) # features/flaky.feature:3
   FAILED Given a step that passes the third time # features/flaky.feature:4
            Bad state: flaky 2

1 scenario (1 passed)
1 step (1 passed)
<duration>''');
    });

    test('a scenario that keeps failing is a failure after its warnings', () {
      return expectLater(
        _summarise(
          {'features/flaky.feature': _flaky},
          [
            Given(
              'a step that passes the third time',
              () => throw StateError('never'),
            ),
          ],
          retry: 1,
        ),
        completion(
          allOf(
            contains(
              'Failures:\n\n'
              '1) Scenario: Flaky - flaky (attempt 2) # '
              'features/flaky.feature:3\n',
            ),
            contains(
              'Warnings:\n\n'
              '1) Scenario: Flaky - flaky (attempt 1, retried) # '
              'features/flaky.feature:3\n',
            ),
            contains('1 scenario (1 failed)\n1 step (1 failed)\n'),
          ),
        ),
      );
    });

    test('de-duplicates the snippets of undefined steps', () async {
      final summary = await _summarise({
        'features/a.feature': '''
Feature: A
  Scenario: one
    Given an undefined step
    When I eat "red" apples
  Scenario: two
    Given an undefined step
''',
        'features/b.feature': '''
Feature: B
  Scenario: three
    Given an undefined step
      | a table |
    Then nothing happens
''',
      }, const []);
      expect(
        summary,
        endsWith('''
3 scenarios (3 undefined)
5 steps (5 undefined)
<duration>

You can implement missing steps with the snippets below:

Given('an undefined step', () {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),

When('I eat {string} apples', (String string1) {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),

Given('an undefined step', (DataTable dataTable) {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),

Then('nothing happens', () {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),'''),
        reason:
            'undefined steps stay undefined after a failed-ish step; the '
            'same text with a data table needs another snippet',
      );
      expect(
        RegExp(
          r"^Given\('an undefined step', \(\) \{$",
          multiLine: true,
        ).allMatches(summary),
        hasLength(1),
      );
    });

    test('lists undefined steps in a dry run', () async {
      final summary = await _summarise(
        {'features/shop.feature': _shop},
        _shopGlue,
        dryRun: true,
      );
      expect(
        summary,
        allOf(
          contains('6 scenarios (1 ambiguous, 1 undefined, 4 skipped)'),
          contains('14 steps (1 ambiguous, 1 undefined, 12 skipped)'),
          contains("Given('{int} undefined cukes', (int int1) {"),
        ),
      );
    });

    test('lists failed test run hooks and hooks of scenarios', () async {
      final summary = await _summarise(
        {'features/a.feature': _passing},
        [
          BeforeAll(() => throw StateError('database is down'), name: 'db'),
          AfterAll(() => throw StateError('cleanup failed')),
          Given('a shop', () {}),
          Given('a step passes', () {}),
        ],
      );
      expect(
        summary,
        allOf(
          matches(
            RegExp(
              r'^Failures:\n\n'
              r'1\) BeforeAll hook "db" \(failed\) # test/summary_test\.dart:\d+\n'
              r'     Bad state: database is down\n\n'
              r'2\) AfterAll hook \(failed\) # test/summary_test\.dart:\d+\n'
              r'     Bad state: cleanup failed\n\n'
              r'0 scenarios\n'
              r'0 steps\n'
              r'<duration>$',
            ),
          ),
        ),
      );

      final scenarioHooks = await _summarise(
        {'features/a.feature': _passing},
        [
          Before(() {}, name: 'passes'),
          After(() => throw StateError('teardown'), name: 'breaks'),
          Given('a shop', () {}),
          Given('a step passes', () {}),
        ],
      );
      expect(
        scenarioHooks,
        matches(
          RegExp(
            r'^Failures:\n\n'
            r'1\) Scenario: A - one # features/a\.feature:6\n'
            r'   PASSED Given a shop # features/a\.feature:4\n'
            r'   PASSED Given a step passes # features/a\.feature:7\n'
            r'   FAILED After hook "breaks" # test/summary_test\.dart:\d+\n'
            r'            Bad state: teardown\n\n'
            r'2\) Scenario: A - two # features/a\.feature:9\n',
          ),
        ),
        reason: 'passing hooks are left out',
      );
      expect(
        scenarioHooks,
        contains('2 scenarios (2 failed)\n2 steps (2 passed)\n'),
        reason: 'hooks are not counted as steps',
      );
    });

    test('names example rows and locates them on their row', () async {
      final summary = await _summarise(
        {
          'features/outline.feature': '''
Feature: Outline
  Rule: Payments
    Scenario Outline: pay with <method>
      Given I pay with "<method>"

      Examples: Cards
        | method |
        | visa   |
        | amex   |
''',
        },
        [
          Given('I pay with {string}', (String method) {
            if (method == 'amex') pending();
          }),
        ],
      );
      expect(
        summary,
        startsWith(
          'Failures:\n\n'
          '1) Scenario: Outline - Payments - pay with <method> - Cards - '
          '#1.2: pay with amex # features/outline.feature:9\n'
          '   PENDING Given I pay with "amex" # features/outline.feature:4\n'
          '             Pending: TODO: implement me\n\n'
          '2 scenarios (1 pending, 1 passed)\n',
        ),
      );
    });

    test('lists undefined parameter types first', () async {
      final summary = await _summarise(
        {'features/a.feature': _passing},
        [
          Given('a shop', () {}),
          Given('a step passes', () {}),
          Given('a {flight} departs', (Object flight) {}),
        ],
      );
      expect(
        summary,
        startsWith(
          'Undefined parameter types:\n\n'
          '- "flight" e.g. `a {flight} departs`\n\n'
          '2 scenarios (2 passed)\n',
        ),
      );
    });

    test('an empty run has no scenarios and no steps', () async {
      expect(await _summarise(const {}, const []), '''
0 scenarios
0 steps
<duration>''');
      expect(formatSummaryOf(const []), '0 scenarios\n0 steps');
      expect(formatSummary(Query()), '0 scenarios\n0 steps');
    });

    test('reports the run duration and the time spent in steps', () {
      messages.Timestamp at(int seconds, int nanos) =>
          messages.Timestamp(seconds: seconds, nanos: nanos);
      final summary = formatSummaryOf([
        messages.Envelope(
          testRunStarted: messages.TestRunStarted(timestamp: at(100, 0)),
        ),
        for (final (id, nanos) in [('a', 250000000), ('b', 5000000)])
          messages.Envelope(
            testStepFinished: messages.TestStepFinished(
              testCaseStartedId: id,
              testStepId: id,
              testStepResult: messages.TestStepResult(
                duration: messages.Duration(seconds: 1, nanos: nanos),
                status: messages.TestStepResultStatus.passed,
              ),
              timestamp: at(101, 0),
            ),
          ),
        messages.Envelope(
          testRunFinished: messages.TestRunFinished(
            success: true,
            timestamp: at(163, 456789000),
          ),
        ),
      ]);
      expect(
        summary,
        '0 scenarios\n0 steps\n1m03.456s (executing steps: 0m02.255s)',
      );
    });

    test('formatDuration follows cucumber-js', () {
      expect(formatDuration(Duration.zero), '0m00.000s');
      expect(
        formatDuration(const Duration(seconds: 7, milliseconds: 8)),
        '0m07.008s',
      );
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '62m03.000s',
      );
    });

    group('Compatibility Kit samples', () {
      test('retry', () {
        expect(
          _withoutDuration(formatSummaryOf(_cck('retry'))),
          allOf(
            contains(
              '4 scenarios (1 failed, 3 passed)\n'
              '4 steps (1 failed, 3 passed)\n',
            ),
            contains('(attempt 1, retried)'),
          ),
        );
      });

      for (final (name, counts) in [
        ('empty', '1 scenario (1 passed)\n0 steps'),
        ('minimal', '1 scenario (1 passed)\n1 step (1 passed)'),
        ('ambiguous', '1 scenario (1 ambiguous)\n1 step (1 ambiguous)'),
        ('pending', '3 scenarios (3 pending)\n'),
        (
          'undefined',
          '4 scenarios (4 undefined)\n6 steps (4 undefined, 1 skipped, 1 passed)',
        ),
        ('retry-undefined', '1 scenario (1 undefined)\n1 step (1 undefined)'),
        ('retry-pending', '1 scenario (1 pending)\n1 step (1 pending)'),
        ('retry-ambiguous', '1 scenario (1 ambiguous)\n1 step (1 ambiguous)'),
      ]) {
        test(name, () {
          expect(formatSummaryOf(_cck(name)), contains(counts));
        });
      }

      test('undefined: snippets come from the suggestions', () {
        final summary = formatSummaryOf(_cck('undefined'));
        expect(
          summary,
          endsWith(
            'You can implement missing steps with the snippets below:\n\n'
            'Given("a step that is yet to be defined", () => {\n'
            '  return "pending"\n'
            '})\n\n'
            'Given("a list of {int} things", (int: number) => {\n'
            '  return "pending"\n'
            '})\n'
            '// Or use one of these expressions:\n'
            '// Given("a list of {float} things", (float: number) => {',
          ),
        );
      });

      test('every sample can be summarised', () {
        for (final name in _cckSamples()) {
          final envelopes = _cck(name);
          final finals = [
            for (final e in envelopes)
              if (e.testCaseFinished case final f? when !f.willBeRetried) f,
          ];
          final summary = formatSummaryOf(envelopes);
          final scenarios = finals.length;
          expect(
            summary,
            matches(RegExp('(^|\n)$scenarios scenarios?( |\n)')),
            reason: name,
          );
          expect(
            summary,
            matches(RegExp(r'\d+m\d\d\.\d{3}s \(executing steps: ')),
            reason: name,
          );
        }
      });
    });
  });

  group('SummaryPlugin', () {
    test('prints the summary once, when the run ends', () async {
      final printed = <String>[];
      final plugin = SummaryPlugin(output: printed.add);
      final plan = SuitePlan.create(
        features: const [FeatureSource('features/a.feature', _passing)],
        glue: _shopGlue,
        plugins: [plugin],
      );
      await plan.start();
      for (final node in plan.pickles) {
        await plan.runPickle(node);
      }
      expect(printed, isEmpty);
      await plan.finish();
      plugin.close();
      expect(printed, hasLength(1));
      expect(
        printed.single,
        matches(
          RegExp(
            r'^2 scenarios \(2 passed\)\n2 steps \(2 passed\)\n'
            r'\d+m\d\d\.\d{3}s \(executing steps: \d+m\d\d\.\d{3}s\)$',
          ),
        ),
      );
      expect(plugin.toString(), 'summary');
    });

    test('prints nothing when the run never starts', () async {
      final printed = <String>[];
      final plan = SuitePlan.create(
        features: const [FeatureSource('features/a.feature', _passing)],
        glue: _shopGlue,
        plugins: [SummaryPlugin(output: printed.add)],
      );
      await plan.finish();
      expect(printed, isEmpty);
    });
  });
}

const _passing = '''
Feature: A

  Background:
    Given a shop

  Scenario: one
    Given a step passes

  Scenario: two
''';

const _flaky = '''
Feature: Flaky

  Scenario: flaky
    Given a step that passes the third time
''';
