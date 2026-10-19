import 'package:cucumber/src/host.dart';
import 'package:cucumber_core/engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _feature = '''
Feature: Outcomes

  Scenario: passed
    Given a step passes

  Scenario: failed
    Given a step fails

  Scenario: pending
    Given a pending step

  Scenario: undefined
    Given an undefined step with 3 cukes
    And another undefined step

  Scenario: ambiguous
    Given an ambiguous step

  Scenario: skipped
    Given a step skips
''';

final _error = StateError('boom');
StackTrace? _stackTrace;

final _glue = <Glue>[
  Given('a step passes', () {}),
  Given('a step fails', () {
    try {
      throw _error;
    } on StateError catch (_, st) {
      _stackTrace = st;
      rethrow;
    }
  }),
  Given('a pending step', () => pending('later')),
  Given('an ambiguous step', () {}),
  Given(RegExp('^an ambiguous (.*)'), (String _) {}),
  Given('a step skips', () => skip('not today')),
];

Future<Map<String, TestCaseResult>> _results() async {
  final plan = SuitePlan.create(
    features: [const FeatureSource('features/outcomes.feature', _feature)],
    glue: _glue,
  );
  final run = await const SerialHost().run(plan);
  return {for (final r in run.testCases) r.pickle.name: r};
}

void main() {
  group('reportResult', () {
    late Map<String, TestCaseResult> results;

    setUpAll(() async => results = await _results());

    Matcher failsWith(Object message) => throwsA(
      isA<TestFailure>().having((e) => e.message, 'message', message),
    );

    test('PASSED returns', () {
      reportResult(results['passed']!);
    });

    test('FAILED rethrows the original error and stack trace', () {
      Object? thrown;
      StackTrace? trace;
      try {
        reportResult(results['failed']!);
      } on Object catch (e, st) {
        thrown = e;
        trace = st;
      }
      expect(thrown, same(_error));
      expect(trace.toString(), _stackTrace.toString());
    });

    test('PENDING fails with the step and its message', () {
      expect(
        () => reportResult(results['pending']!),
        failsWith(
          'Pending step in scenario "pending" '
          '(features/outcomes.feature:9):\n'
          '  Given a pending step (features/outcomes.feature:10):\n'
          '    later',
        ),
      );
    });

    test('UNDEFINED fails with snippets', () {
      expect(
        () => reportResult(results['undefined']!),
        failsWith(
          allOf(
            startsWith(
              'Undefined steps in scenario "undefined" '
              '(features/outcomes.feature:12):\n'
              '  Given an undefined step with 3 cukes '
              '(features/outcomes.feature:13)\n'
              '  And another undefined step (features/outcomes.feature:14)\n'
              '\n'
              'Implement them with these snippets:\n',
            ),
            contains(
              "Given('an undefined step with {int} cukes', (int int1) {",
            ),
            contains("Given('another undefined step', () {"),
          ),
        ),
      );
    });

    test('AMBIGUOUS fails with the candidates', () {
      expect(
        () => reportResult(results['ambiguous']!),
        failsWith(
          allOf(
            contains('Ambiguous step in scenario "ambiguous"'),
            contains('Multiple step definitions match "an ambiguous step"'),
            contains('host_test.dart'),
          ),
        ),
      );
    });

    test('a pickle that did not run fails with the reason and hook errors', () {
      final pickle = results['passed']!.pickle;
      expect(
        () => reportResult(
          TestCaseResult.notRun(
            pickle,
            'Not run because a BeforeAll hook failed.',
          ),
          testRunHooks: [
            const StepResult(
              status: Status.passed,
              duration: Duration.zero,
              description: 'BeforeAll hook "fine"',
              location: 'test/hooks.dart:1',
            ),
            StepResult(
              status: Status.failed,
              duration: Duration.zero,
              description: 'BeforeAll hook "db"',
              location: 'test/hooks.dart:2',
              error: StateError('down'),
              stackTrace: StackTrace.current,
            ),
          ],
        ),
        failsWith(
          allOf(
            startsWith(
              'Not run because a BeforeAll hook failed.\n\n'
              'FAILED BeforeAll hook "db" (test/hooks.dart:2):\n'
              '  Bad state: down\n'
              '  test',
            ),
            isNot(contains('"fine"')),
            isNot(contains('package:test_api')),
          ),
        ),
      );
    });

    test('failureMessage describes a FAILED result', () {
      expect(
        failureMessage(results['failed']!),
        'Failed step in scenario "failed" (features/outcomes.feature:6):\n'
        '  Given a step fails (features/outcomes.feature:7): Bad state: boom',
      );
    });
  });

  group('testTags', () {
    test('removes the @ and drops tags package:test rejects', () {
      expect(
        testTags([
          '@smoke',
          '@wip',
          '@issue:123',
          '@with space',
          '@kebab-case',
          '@_private',
          '@9lives',
          '@smoke',
          '@über',
        ]),
        ['smoke', 'wip', 'kebab-case', '_private'],
      );
    });
  });

  group('attemptsTimeout', () {
    test('scales the timeout by the number of attempts', () {
      expect(attemptsTimeout(null, 1), isNull);
      expect(attemptsTimeout(null, 3), const Timeout.factor(3));
      const seconds = Timeout(Duration(seconds: 10));
      expect(attemptsTimeout(seconds, 1), seconds);
      expect(attemptsTimeout(seconds, 2), const Timeout(Duration(seconds: 20)));
      expect(
        attemptsTimeout(const Timeout.factor(2), 3),
        const Timeout.factor(6),
      );
      expect(attemptsTimeout(Timeout.none, 3), Timeout.none);
    });
  });

  test('testLocation points at the feature file line and column', () {
    final plan = SuitePlan.create(
      features: [const FeatureSource('features/outcomes.feature', _feature)],
      glue: _glue,
    );
    final root = p.join(p.current, 'project');
    final host = PackageTestHost(packageRoot: root);
    final feature = plan.children.single;
    final scenario = (feature as FeatureNode).children[1];
    final featureLocation = host.testLocation(feature);
    final scenarioLocation = host.testLocation(scenario);
    expect(
      featureLocation.uri,
      Uri.file(p.join(root, 'features', 'outcomes.feature')),
    );
    expect((featureLocation.line, featureLocation.column), (1, 1));
    expect((scenarioLocation.line, scenarioLocation.column), (6, 3));
  });

  // The host declares a plan inside this test file; the group's tearDownAll
  // finishes the run before the next test checks it.
  final collector = CollectingPlugin();
  group('a declared plan', () {
    final plan = SuitePlan.create(
      features: [
        const FeatureSource('features/declared.feature', '''
Feature: Declared
  Scenario: passes
    Given a step passes

  Scenario: skips
    Given a step skips
'''),
      ],
      glue: _glue,
      plugins: [collector],
    );
    PackageTestHost(packageRoot: p.current).declare(plan);
  });

  test('ran in setUpAll and finished in tearDownAll', () {
    expect(collector.isClosed, isTrue);
    final types = [for (final e in collector.envelopes) e.toJson().keys.single];
    expect(types.first, 'meta');
    expect(types.where((t) => t == 'testCaseFinished'), hasLength(2));
    expect(types.last, 'testRunFinished');
    expect(collector.envelopes.last.testRunFinished!.success, isTrue);
  });
}
