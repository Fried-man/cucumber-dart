import 'dart:async';

import 'package:cucumber_core/engine.dart';
import 'package:cucumber_core/src/runtime/test_case_runner.dart'
    show StepArityException, TransformerResultException;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:test/test.dart';

import '../support.dart';

class CountingWorld extends World {
  CountingWorld() {
    instances++;
  }

  static int instances = 0;
  int value = 0;
}

class User {
  User(this.name);
  final String name;
}

void main() {
  setUp(() => CountingWorld.instances = 0);

  group('dry run', () {
    test('runs no user code but reports undefined steps', () async {
      final calls = <String>[];
      final run = await runFeature(
        '''
Feature: f
  Scenario: s
    Given a defined step
    And an undefined step
''',
        [
          BeforeAll(() => calls.add('beforeAll')),
          Before(() => calls.add('before')),
          Given('a defined step', () => calls.add('step')),
          After(() => calls.add('after')),
          AfterAll(() => calls.add('afterAll')),
        ],
        world: CountingWorld.new,
        options: const RunOptions(dryRun: true),
      );
      expect(calls, isEmpty);
      expect(CountingWorld.instances, 1, reason: 'the World is still created');
      expect(run.statuses.single, [
        Status.skipped,
        Status.skipped,
        Status.undefined,
        Status.skipped,
      ]);
      expect(run.result.hooks.map((h) => h.status), [
        Status.skipped,
        Status.skipped,
      ]);
      expect(
        run.envelopes.where((e) => e.testRunHookStarted != null),
        hasLength(2),
      );
      expect(run.result.success, isFalse);
    });
  });

  group('step hooks', () {
    test('fold into the step result and see its outcome', () async {
      final seen = <String>[];
      final run = await runFeature(
        '''
Feature: f
  @tagged
  Scenario: s
    Given a step
''',
        [
          BeforeStep((Step s) {
            seen.add('before ${s.text} ${s.status.name}');
            s.scenario.log('from BeforeStep');
          }),
          Given('a step', () => seen.add('step')),
          AfterStep(
            (Step s) =>
                seen.add('after ${s.keyword}${s.text} ${s.status.name}'),
          ),
          AfterStep((Step s) => seen.add('not run'), tags: '@other'),
        ],
      );
      expect(seen, [
        'before a step unknown',
        'step',
        'after Given a step passed',
      ]);
      expect(run.statuses.single, [Status.passed]);
      final stepId = run.envelopes
          .firstWhere((e) => e.testCase != null)
          .testCase!
          .testSteps
          .single
          .id;
      expect(run.attachments.single.testStepId, stepId);
      expect(
        run.envelopes.where((e) => e.hook != null).map((e) => e.hook!.type),
        [
          messages.HookType.beforeTestStep,
          messages.HookType.afterTestStep,
          messages.HookType.afterTestStep,
        ],
      );
    });

    test('a failing BeforeStep skips the step body', () async {
      var ran = false;
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given a step\n',
        [
          BeforeStep(() => throw StateError('nope')),
          Given('a step', () => ran = true),
        ],
      );
      expect(ran, isFalse);
      expect(run.statuses.single, [Status.failed]);
      expect(run.result.testCases.single.steps.single.error, isA<StateError>());
    });
  });

  group('user code', () {
    test('times out', () async {
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given a slow step\n',
        [
          Given(
            'a slow step',
            () => Future<void>.delayed(const Duration(seconds: 5)),
            timeout: const Duration(milliseconds: 20),
          ),
        ],
      );
      expect(
        run.result.testCases.single.steps.single.error,
        isA<TimeoutException>(),
      );
    });

    test('uncaught asynchronous errors fail the running step', () async {
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given a leaky step\n    And another\n',
        [
          Given('a leaky step', () async {
            unawaited(Future<void>(() => throw StateError('leaked')));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }),
          Given('another', () {}),
        ],
      );
      expect(run.statuses.single, [Status.failed, Status.skipped]);
      expect(run.result.testCases.single.steps.first.error, isA<StateError>());
    });

    test('failure messages end with the Gherkin step frame', () async {
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given a failing step\n',
        [Given('a failing step', () => throw StateError('boom'))],
        uri: 'features/fail.feature',
      );
      final result = run.stepResults.single;
      expect(result.status, messages.TestStepResultStatus.failed);
      expect(result.exception!.type, 'StateError');
      expect(result.exception!.message, 'Bad state: boom');
      expect(result.message, startsWith('Bad state: boom\n'));
      expect(result.message, endsWith('features/fail.feature:3'));
      expect(result.message, isNot(contains('package:cucumber_core')));
    });

    test('pending and skip carry their messages', () async {
      final run = await runFeature(
        'Feature: f\n  Scenario: a\n    Given todo\n  Scenario: b\n    Given skipped\n',
        [
          Given('todo', () => pending('later')),
          Given('skipped', () => skip('not today')),
        ],
      );
      expect(run.statuses, [
        [Status.pending],
        [Status.skipped],
      ]);
      expect(run.stepResults.map((r) => r.message), ['later', 'not today']);
      expect(run.result.success, isFalse);
    });
  });

  group('World', () {
    test('a new World is created for every attempt', () async {
      final worlds = <CountingWorld>[];
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given a flaky step\n',
        [
          Given('a flaky step', (CountingWorld w) {
            worlds.add(w);
            w.value++;
            if (worlds.length < 3) throw StateError('flaky');
          }),
        ],
        world: CountingWorld.new,
        options: const RunOptions(retry: 2),
      );
      expect(run.result.success, isTrue);
      expect(run.result.testCases.single.attempts, 3);
      expect(worlds.toSet(), hasLength(3));
      expect(worlds.map((w) => w.value), [1, 1, 1]);
      expect(
        run.envelopes
            .where((e) => e.testCaseFinished != null)
            .map((e) => e.testCaseFinished!.willBeRetried),
        [true, true, false],
      );
    });

    test('world parameters are copied per attempt after BeforeAll', () async {
      final seen = <Object?>[];
      await runFeature(
        'Feature: f\n  Scenario: a\n    Given a step\n  Scenario: b\n    Given a step\n',
        [
          BeforeAll(
            (TestRun run) =>
                (run.parameters['list']! as List).add('fromBeforeAll'),
          ),
          Given('a step', (World w) {
            seen.add([...w.parameters['list']! as List]);
            (w.parameters['list']! as List).add('leak');
          }),
        ],
        options: const RunOptions(
          worldParameters: {
            'list': ['initial'],
          },
        ),
      );
      expect(seen, [
        ['initial', 'fromBeforeAll'],
        ['initial', 'fromBeforeAll'],
      ]);
    });

    test('After hooks see the scenario status and error', () async {
      late Scenario seen;
      Object? status;
      await runFeature(
        '''
Feature: f
  @smoke
  Scenario: failing one
    Given a failing step
''',
        [
          Given('a failing step', () => throw ArgumentError('bad')),
          After((Scenario s) {
            seen = s;
            status = s.status;
          }),
        ],
      );
      expect(status, Status.failed);
      expect(seen.isFailed, isTrue);
      expect(seen.error, isA<ArgumentError>());
      expect(seen.name, 'failing one');
      expect(seen.tags, ['@smoke']);
      expect(seen.line, 3);
      expect(seen.uri, 'features/test.feature');
      expect(seen.attempt, 0);
      expect(seen.language, 'en');
    });

    test('World members only work while a scenario runs', () {
      expect(() => CountingWorld().scenario, throwsStateError);
      expect(() => attach('x'), throwsStateError);
      expect(() => log('x'), throwsStateError);
    });
  });

  group('attachments', () {
    test('support strings, bytes, logs and links from helpers', () async {
      void helper() => attach('from a helper');
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given attachments\n',
        [
          Given('attachments', (World w) async {
            helper();
            await Future<void>.delayed(Duration.zero);
            w.attach([1, 2, 3], fileName: 'bytes.bin');
            log('a log line');
            link('https://cucumber.io', title: 'Cucumber');
            w.scenario.attach('{}', mediaType: 'application/json');
          }),
        ],
      );
      expect(
        run.attachments.map(
          (a) => (a.body, a.contentEncoding.value, a.mediaType, a.fileName),
        ),
        [
          ('from a helper', 'IDENTITY', 'text/plain', null),
          ('AQID', 'BASE64', 'application/octet-stream', 'bytes.bin'),
          ('a log line', 'IDENTITY', 'text/x.cucumber.log+plain', null),
          ('https://cucumber.io', 'IDENTITY', 'text/uri-list', 'Cucumber'),
          ('{}', 'IDENTITY', 'application/json', null),
        ],
      );
      expect(run.attachments.every((a) => a.timestamp != null), isTrue);
      expect(run.attachments.every((a) => a.testCaseStartedId != null), isTrue);
    });

    test('reject unsupported data', () async {
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given a bad attachment\n',
        [Given('a bad attachment', () => attach(42))],
      );
      expect(run.result.testCases.single.steps.single.error, isArgumentError);
    });
  });

  group('parameter types', () {
    test('transformers can use the World and be async', () async {
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given "Ada" logs in\n',
        [
          ParameterType<User>('user', r'"([^"]*)"', (
            CountingWorld w,
            String name,
          ) async {
            await Future<void>.delayed(Duration.zero);
            w.value = 42;
            return User(name);
          }),
          Given('{user} logs in', (CountingWorld w, User user) {
            if (user.name != 'Ada' || w.value != 42) throw StateError('wrong');
          }),
        ],
        world: CountingWorld.new,
      );
      expect(run.result.success, isTrue);
    });

    test('a transformer returning the wrong type fails the step', () async {
      final run = await runFeature(
        'Feature: f\n  Scenario: s\n    Given Ada logs in\n',
        [
          ParameterType<User>('user', 'Ada', (String s) => s as Object),
          Given('{user} logs in', (User user) {}),
        ],
      );
      expect(
        run.result.testCases.single.steps.single.error,
        isA<TransformerResultException>(),
      );
    });

    test('built-in types are not nullable', () async {
      Object? received;
      await runFeature(
        'Feature: f\n  Scenario: s\n    Given 1.5 and -2 and "x" and word\n',
        [
          Given('{float} and {int} and {string} and {word}', (
            double f,
            int i,
            String s,
            String w,
          ) {
            received = [f, i, s, w];
          }),
        ],
      );
      expect(received, [1.5, -2, 'x', 'word']);
    });
  });

  test('a step with an unexpected multiline argument fails', () async {
    final run = await runFeature(
      'Feature: f\n  Scenario: s\n    Given a step\n      | a |\n',
      [Given('a step', () {})],
    );
    expect(
      run.result.testCases.single.steps.single.error,
      isA<StepArityException>(),
    );
  });

  test('a failing BeforeAll hook stops every test case', () async {
    var ran = false;
    final run =
        await runFeature('Feature: f\n  Scenario: s\n    Given a step\n', [
          BeforeAll(() => throw StateError('setup failed')),
          Given('a step', () => ran = true),
          AfterAll(() {}),
        ]);
    expect(ran, isFalse);
    expect(run.result.success, isFalse);
    expect(run.result.hooks.map((h) => h.status), [
      Status.failed,
      Status.passed,
    ]);
    expect(run.envelopes.where((e) => e.testCase != null), isEmpty);
  });

  test('undefined steps produce Dart snippets', () async {
    final run = await runFeature(
      '''
Feature: f
  Scenario: s
    When I eat 3 "red" apples
      """
      text
      """
''',
      [],
      world: CountingWorld.new,
    );
    final testCase = run.result.testCases.single;
    expect(testCase.status, Status.undefined);
    expect(
      testCase.snippets.single,
      '''
When('I eat {int} {string} apples', (CountingWorld world, int int1, String string1, DocString docString) {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),
// Or use one of these expressions:
// When('I eat {float} {string} apples', (CountingWorld world, double float1, String string1, DocString docString) {''',
    );
    final suggestion = run.envelopes
        .firstWhere((e) => e.suggestion != null)
        .suggestion!;
    expect(suggestion.snippets.map((s) => s.language), ['dart', 'dart']);
  });
}
