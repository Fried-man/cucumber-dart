import 'dart:io';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:cucumber_query/cucumber_query.dart';
import 'package:test/test.dart';

void main() {
  late Query query;

  setUp(() => query = Query());

  messages.Timestamp at(int seconds, [int nanos = 0]) =>
      messages.Timestamp(seconds: seconds, nanos: nanos);

  messages.TestCaseStarted started(String id, messages.Timestamp timestamp) =>
      messages.TestCaseStarted(
        id: id,
        testCaseId: id,
        attempt: 0,
        timestamp: timestamp,
      );

  messages.TestStepFinished stepFinished(
    String testCaseStartedId,
    messages.TestStepResultStatus status, {
    String testStepId = 'step',
    String? message,
  }) => messages.TestStepFinished(
    testCaseStartedId: testCaseStartedId,
    testStepId: testStepId,
    testStepResult: messages.TestStepResult(
      duration: const messages.Duration(seconds: 0, nanos: 0),
      status: status,
      message: message,
    ),
    timestamp: at(0),
  );

  // Ported from Query.spec.ts.
  group('findAllTestCaseStarted', () {
    test('retains timestamp order', () {
      final testCasesStarted = [
        started('1', at(1, 1)),
        started('2', at(2, 1)),
        started('3', at(2, 3)),
      ];
      for (final testCaseStarted in testCasesStarted.reversed) {
        query.update(messages.Envelope(testCaseStarted: testCaseStarted));
      }
      expect(query.findAllTestCaseStarted(), testCasesStarted);
    });

    test('uses id as tie breaker', () {
      final testCasesStarted = [started('1', at(1, 1)), started('2', at(1, 1))];
      for (final testCaseStarted in testCasesStarted.reversed) {
        query.update(messages.Envelope(testCaseStarted: testCaseStarted));
      }
      expect(query.findAllTestCaseStarted(), testCasesStarted);
    });

    test('leaves out attempts that will be retried', () {
      final first = started('1', at(1));
      final retry = started('2', at(3));
      query
        ..update(messages.Envelope(testCaseStarted: first))
        ..update(
          messages.Envelope(
            testCaseFinished: messages.TestCaseFinished(
              testCaseStartedId: '1',
              timestamp: at(2),
              willBeRetried: true,
            ),
          ),
        )
        ..update(messages.Envelope(testCaseStarted: retry));
      expect(query.findAllTestCaseStarted(), [retry]);
      expect(query.findAllTestCaseFinished(), isEmpty);
      expect(query.countTestCasesStarted(), 1);
    });
  });

  group('findMostSevereTestStepResultBy', () {
    test('returns the first of the most severe results', () {
      final testCaseStarted = started('1', at(1));
      query.update(messages.Envelope(testCaseStarted: testCaseStarted));
      for (final (status, message) in [
        (messages.TestStepResultStatus.passed, null),
        (messages.TestStepResultStatus.failed, 'first'),
        (messages.TestStepResultStatus.undefined, null),
        (messages.TestStepResultStatus.failed, 'second'),
      ]) {
        query.update(
          messages.Envelope(
            testStepFinished: stepFinished('1', status, message: message),
          ),
        );
      }
      final result = query.findMostSevereTestStepResultBy(testCaseStarted);
      expect(result?.status, messages.TestStepResultStatus.failed);
      expect(result?.message, 'first');
    });

    test('returns null without finished steps or a known start', () {
      final testCaseStarted = started('1', at(1));
      query.update(messages.Envelope(testCaseStarted: testCaseStarted));
      expect(query.findMostSevereTestStepResultBy(testCaseStarted), isNull);
      expect(
        query.findMostSevereTestStepResultBy(
          messages.TestCaseFinished(
            testCaseStartedId: 'unknown',
            timestamp: at(2),
            willBeRetried: false,
          ),
        ),
        isNull,
      );
    });

    test('counts test cases by their most severe status', () {
      for (final (id, statuses) in [
        ('1', [messages.TestStepResultStatus.passed]),
        (
          '2',
          [
            messages.TestStepResultStatus.passed,
            messages.TestStepResultStatus.pending,
            messages.TestStepResultStatus.skipped,
          ],
        ),
        ('3', <messages.TestStepResultStatus>[]),
      ]) {
        query.update(messages.Envelope(testCaseStarted: started(id, at(1))));
        for (final status in statuses) {
          query.update(
            messages.Envelope(testStepFinished: stepFinished(id, status)),
          );
        }
      }
      expect(query.countMostSevereTestStepResultStatus(), {
        messages.TestStepResultStatus.unknown: 0,
        messages.TestStepResultStatus.passed: 1,
        messages.TestStepResultStatus.skipped: 0,
        messages.TestStepResultStatus.pending: 1,
        messages.TestStepResultStatus.undefined: 0,
        messages.TestStepResultStatus.ambiguous: 0,
        messages.TestStepResultStatus.failed: 0,
      });
    });
  });

  group('durations', () {
    test('are exact to the nanosecond', () {
      final testCaseStarted = started('1', at(1, 900000000));
      final testCaseFinished = messages.TestCaseFinished(
        testCaseStartedId: '1',
        timestamp: at(3, 100000001),
        willBeRetried: false,
      );
      query
        ..update(messages.Envelope(testCaseStarted: testCaseStarted))
        ..update(messages.Envelope(testCaseFinished: testCaseFinished));
      const expected = messages.Duration(seconds: 1, nanos: 200000001);
      expect(query.findTestCaseDurationBy(testCaseStarted), expected);
      expect(query.findTestCaseDurationBy(testCaseFinished), expected);
    });

    test('are null while unfinished', () {
      final testCaseStarted = started('1', at(1));
      query
        ..update(messages.Envelope(testCaseStarted: testCaseStarted))
        ..update(
          messages.Envelope(
            testRunStarted: messages.TestRunStarted(timestamp: at(0)),
          ),
        );
      expect(query.findTestCaseDurationBy(testCaseStarted), isNull);
      expect(query.findTestRunDuration(), isNull);
    });
  });

  group('incomplete streams', () {
    test('yield null and empty results instead of errors', () {
      const testStep = messages.TestStep(
        id: 'ts',
        pickleStepId: 'missing',
        stepDefinitionIds: ['missing'],
      );
      final testStepFinished = stepFinished(
        'missing',
        messages.TestStepResultStatus.passed,
      );
      expect(query.findPickleStepBy(testStep), isNull);
      expect(query.findStepDefinitionsBy(testStep), isEmpty);
      expect(query.findUnambiguousStepDefinitionBy(testStep), isNull);
      expect(query.findHookBy(testStep), isNull);
      expect(query.findTestCaseBy(testStepFinished), isNull);
      expect(query.findPickleBy(testStepFinished), isNull);
      expect(query.findAttachmentsBy(testStepFinished), isEmpty);
      expect(query.findTestStepBy(testStepFinished), isNull);
      expect(
        query.findHookBy(
          messages.TestRunHookFinished(
            testRunHookStartedId: 'missing',
            result: messages.TestStepResult(
              duration: const messages.Duration(seconds: 0, nanos: 0),
              status: messages.TestStepResultStatus.passed,
            ),
            timestamp: at(0),
          ),
        ),
        isNull,
      );
      expect(query.findMeta(), isNull);
      expect(query.findTestRunStarted(), isNull);
      expect(query.findTestRunFinished(), isNull);
    });
  });

  test('rejects unsupported kinds of message', () {
    expect(
      () => query.findPickleBy('a string'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('findPickleBy does not accept a String'),
        ),
      ),
    );
    expect(
      () => query.findTestStepBy(started('1', at(0))),
      throwsArgumentError,
    );
    expect(() => query.findLineageBy(42), throwsArgumentError);
  });

  // Ported from Query.spec.ts.
  group('findLineageBy', () {
    test('returns the lineage of a minimal scenario', () {
      final envelopes = _load('minimal');
      envelopes.forEach(query.update);
      final gherkinDocument = envelopes
          .firstWhere((envelope) => envelope.gherkinDocument != null)
          .gherkinDocument!;
      final feature = gherkinDocument.feature!;
      final scenario = feature.children
          .firstWhere((child) => child.scenario != null)
          .scenario;
      final pickle = envelopes
          .firstWhere((envelope) => envelope.pickle != null)
          .pickle!;

      expect(
        query.findLineageBy(pickle),
        Lineage(
          gherkinDocument: gherkinDocument,
          feature: feature,
          scenario: scenario,
        ),
      );
    });

    test('returns the lineage of a pickle from an examples table', () {
      final envelopes = _load('examples-tables');
      envelopes.forEach(query.update);
      final gherkinDocument = envelopes
          .firstWhere((envelope) => envelope.gherkinDocument != null)
          .gherkinDocument!;
      final feature = gherkinDocument.feature!;
      final scenario = feature.children
          .firstWhere((child) => child.scenario != null)
          .scenario!;
      final pickle = envelopes
          .firstWhere((envelope) => envelope.pickle != null)
          .pickle!;
      final examples = scenario.examples.first;

      expect(
        query.findLineageBy(pickle),
        Lineage(
          gherkinDocument: gherkinDocument,
          feature: feature,
          scenario: scenario,
          examples: examples,
          examplesIndex: 0,
          example: examples.tableBody.first,
          exampleIndex: 0,
        ),
      );
    });

    test('returns the lineage of a pickle with background steps', () {
      final envelopes = _load('rules-backgrounds');
      envelopes.forEach(query.update);
      final gherkinDocument = envelopes
          .firstWhere((envelope) => envelope.gherkinDocument != null)
          .gherkinDocument!;
      final feature = gherkinDocument.feature!;
      final background = feature.children
          .firstWhere((child) => child.background != null)
          .background;
      final rule = feature.children
          .firstWhere((child) => child.rule != null)
          .rule!;
      final ruleBackground = rule.children
          .firstWhere((child) => child.background != null)
          .background;
      final scenario = rule.children
          .firstWhere((child) => child.scenario != null)
          .scenario;
      final pickle = envelopes
          .firstWhere((envelope) => envelope.pickle != null)
          .pickle!;

      expect(
        query.findLineageBy(pickle),
        Lineage(
          gherkinDocument: gherkinDocument,
          feature: feature,
          background: background,
          rule: rule,
          ruleBackground: ruleBackground,
          scenario: scenario,
        ),
      );
    });
  });

  // Ported from Query.spec.ts.
  group('findLocationOf', () {
    messages.Pickle withoutLocation(messages.Pickle pickle) => messages.Pickle(
      id: pickle.id,
      uri: pickle.uri,
      name: pickle.name,
      language: pickle.language,
      steps: pickle.steps,
      tags: pickle.tags,
      astNodeIds: pickle.astNodeIds,
    );

    for (final sample in ['minimal', 'examples-tables']) {
      test('falls back to the lineage without a pickle location ($sample)', () {
        final envelopes = _load(sample);
        envelopes.forEach(query.update);
        final pickle = envelopes
            .firstWhere((envelope) => envelope.pickle != null)
            .pickle!;

        expect(query.findLocationOf(withoutLocation(pickle)), pickle.location);
      });
    }
  });

  group('namingStrategy', () {
    test('names a pickle without a lineage by its name', () {
      const pickle = messages.Pickle(
        id: '1',
        uri: 'a.feature',
        name: 'a pickle',
        language: 'en',
        steps: [],
        tags: [],
        astNodeIds: [],
      );
      expect(
        namingStrategy(
          NamingStrategyLength.long,
        ).reduce(const Lineage(), pickle),
        'a pickle',
      );
      expect(
        namingStrategy(NamingStrategyLength.short).reduce(const Lineage()),
        '',
      );
    });
  });
}

List<messages.Envelope> _load(String sample) => [
  for (final line in File('testdata/src/$sample.ndjson').readAsLinesSync())
    if (line.trim().isNotEmpty) messages.parseEnvelopeJson(line),
];
