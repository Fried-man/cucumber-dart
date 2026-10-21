import 'package:cucumber/cucumber.dart';
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:cucumber_query/cucumber_query.dart';
import 'package:test/test.dart';

import '../../cucumber_core/test/compatibility/cck.dart';

const _shared = '''
Feature: Shared

  Scenario: first
    Given a step passes

  Scenario: second
    Given a step passes
''';

const _cart = '''
Feature: Cart

  Scenario: add
    Given a step passes
''';

const _search = '''
Feature: Search

  Scenario: find
    Given a step passes

  Scenario: fail
    Given a step fails
''';

/// Glue shared by every part: the same values give the same IDs.
final _glue = <Glue>[
  BeforeAll(() {}, name: 'start'),
  Given('a step passes', () {}),
  Given('a step fails', () => throw StateError('boom')),
];

/// A clock that starts at [start] and advances one millisecond per reading.
final class _Clock extends CucumberPlatform {
  _Clock(this.start);

  final DateTime start;
  int _milliseconds = 0;

  @override
  DateTime now() => start.add(Duration(milliseconds: _milliseconds++));
}

/// Runs [features] (`uri: source`) with [_glue] through the [SerialHost],
/// selecting [lines] (`uri: lines`), with a clock starting at [start].
Future<List<messages.Envelope>> _run(
  Map<String, String> features, {
  Map<String, Set<int>> lines = const {},
  required DateTime start,
  IdScheme? ids,
}) async {
  final collector = CollectingPlugin();
  final plan = SuitePlan.create(
    features: [
      for (final MapEntry(:key, :value) in features.entries)
        FeatureSource(key, value),
    ],
    glue: _glue,
    options: RunOptions(lines: lines),
    plugins: [collector],
    platform: _Clock(start),
    ids: ids,
  );
  await const SerialHost().run(plan);
  return collector.envelopes;
}

final _t0 = DateTime.utc(2026, 10, 20, 12);

/// Part `cart`: features/shared.feature:3 and features/cart.feature.
Future<ReportPart> _cartPart({DateTime? start, IdScheme? ids}) async =>
    ReportPart(
      'cart',
      await _run(
        {'features/shared.feature': _shared, 'features/cart.feature': _cart},
        lines: {
          'features/shared.feature': {3},
        },
        start: start ?? _t0.add(const Duration(seconds: 10)),
        ids: ids,
      ),
    );

/// Part `search`: features/shared.feature:6 and features/search.feature:3
/// (passing), or all of features/search.feature with [failing].
Future<ReportPart> _searchPart({
  DateTime? start,
  bool failing = false,
  IdScheme? ids,
}) async => ReportPart(
  'search',
  await _run(
    {'features/shared.feature': _shared, 'features/search.feature': _search},
    lines: {
      'features/shared.feature': {6},
      if (!failing) 'features/search.feature': {3},
    },
    start: start ?? _t0,
    ids: ids,
  ),
);

List<T> _of<T>(
  List<messages.Envelope> envelopes,
  T? Function(messages.Envelope) select,
) => [for (final envelope in envelopes) ?select(envelope)];

DateTime _time(messages.Timestamp timestamp) =>
    messages.timestampToDateTime(timestamp).toUtc();

Query _query(List<messages.Envelope> envelopes) {
  final query = Query();
  envelopes.forEach(query.update);
  return query;
}

void main() {
  group('mergeReportParts', () {
    test('keeps one meta and de-duplicates static messages', () async {
      final cart = await _cartPart();
      final search = await _searchPart();
      final merged = mergeReportParts([cart, search]);

      expect(_of(merged, (e) => e.meta), hasLength(1));
      expect(_of(merged, (e) => e.meta).single, cart.envelopes.first.meta);
      expect(_of(merged, (e) => e.source).map((s) => s.uri), [
        'features/shared.feature',
        'features/cart.feature',
        'features/search.feature',
      ]);
      expect(_of(merged, (e) => e.gherkinDocument).map((d) => d.uri), [
        'features/shared.feature',
        'features/cart.feature',
        'features/search.feature',
      ]);
      expect(_of(merged, (e) => e.pickle).map((p) => p.name), [
        'first',
        'second',
        'add',
        'find',
        'fail',
      ]);
      // Both parts loaded the same glue, so it got the same IDs.
      expect(
        _of(cart.envelopes, (e) => e.stepDefinition).map((s) => s.id),
        _of(search.envelopes, (e) => e.stepDefinition).map((s) => s.id),
      );
      expect(_of(merged, (e) => e.stepDefinition), hasLength(2));
      expect(_of(merged, (e) => e.hook), hasLength(1));

      // The dynamic messages of both parts are kept.
      expect(
        _of(merged, (e) => e.testCase).length,
        _of(cart.envelopes, (e) => e.testCase).length +
            _of(search.envelopes, (e) => e.testCase).length,
      );
      expect(_of(merged, (e) => e.testCaseStarted), hasLength(4));
      expect(_of(merged, (e) => e.testRunHookStarted), hasLength(2));
    });

    test('de-duplicates messages without IDs by content', () {
      messages.Envelope undefinedType(String expression) => messages.Envelope(
        undefinedParameterType: messages.UndefinedParameterType(
          name: 'color',
          expression: expression,
        ),
      );
      final merged = mergeReportParts([
        ReportPart('a', [undefinedType('a {color}')]),
        ReportPart('b', [undefinedType('a {color}'), undefinedType('{color}')]),
      ]);
      expect(_of(merged, (e) => e.undefinedParameterType), [
        undefinedType('a {color}').undefinedParameterType,
        undefinedType('{color}').undefinedParameterType,
      ]);
    });

    test('synthesises one testRunStarted (earliest) and one testRunFinished '
        '(latest)', () async {
      final cart = await _cartPart(start: _t0.add(const Duration(seconds: 10)));
      final search = await _searchPart(start: _t0);
      final merged = mergeReportParts([cart, search]);

      final started = _of(merged, (e) => e.testRunStarted);
      final finished = _of(merged, (e) => e.testRunFinished);
      expect(started, hasLength(1));
      expect(finished, hasLength(1));
      expect(_time(started.single.timestamp), _t0);
      final cartFinished = _of(cart.envelopes, (e) => e.testRunFinished).single;
      expect(finished.single.timestamp, cartFinished.timestamp);
      expect(
        _time(finished.single.timestamp).isAfter(_t0.add(_seconds(10))),
        isTrue,
      );
      expect(finished.single.success, isTrue);
      expect(finished.single.message, isNull);
      expect(merged.first.meta, isNotNull);
      expect(merged.last.testRunFinished, isNotNull);
    });

    test('remaps every testRunStartedId to the synthetic test run', () async {
      final cart = await _cartPart();
      final search = await _searchPart();
      final merged = mergeReportParts([cart, search]);

      final id = _of(merged, (e) => e.testRunStarted).single.id;
      expect(id, _of(cart.envelopes, (e) => e.testRunStarted).single.id);
      expect(
        _of(search.envelopes, (e) => e.testRunStarted).single.id,
        isNot(id),
      );
      expect([
        ..._of(merged, (e) => e.testCase).map((t) => t.testRunStartedId),
        ..._of(
          merged,
          (e) => e.testRunHookStarted,
        ).map((h) => h.testRunStartedId),
        ..._of(merged, (e) => e.testRunFinished).map((f) => f.testRunStartedId),
      ], everyElement(id));
    });

    test('succeeds only if every part finished and succeeded', () async {
      final cart = await _cartPart();
      final failing = await _searchPart(failing: true);
      expect(
        _of(failing.envelopes, (e) => e.testRunFinished).single.success,
        isFalse,
      );
      expect(
        _of(
          mergeReportParts([cart, failing]),
          (e) => e.testRunFinished,
        ).single.success,
        isFalse,
      );
      expect(
        _of(
          mergeReportParts([await _searchPart(), cart]),
          (e) => e.testRunFinished,
        ).single.success,
        isTrue,
      );
    });

    test('a part that did not finish fails the run and comes last', () async {
      final search = await _searchPart();
      final cart = await _cartPart();
      // Cut the cart part inside its last test case.
      final cut = cart.envelopes.lastIndexWhere(
        (e) => e.testStepStarted != null,
      );
      final unfinished = ReportPart('cart', cart.envelopes.take(cut + 1));
      final merged = mergeReportParts([unfinished, search]);

      final finished = _of(merged, (e) => e.testRunFinished).single;
      expect(finished.success, isFalse);
      expect(
        finished.message,
        'The report part of suite "cart" did not finish.',
      );
      expect(
        finished.timestamp,
        _of(search.envelopes, (e) => e.testRunFinished).single.timestamp,
      );
      expect(_of(merged, (e) => e.testCaseStarted).map((s) => s.workerId), [
        'search',
        'search',
        'cart',
        'cart',
      ]);

      // Without any finished part, there is no testRunFinished.
      expect(
        _of(mergeReportParts([unfinished]), (e) => e.testRunFinished),
        isEmpty,
      );
    });

    test("keeps the parts' testRunFinished messages and exceptions", () {
      messages.Envelope finished(String? message) => messages.Envelope(
        testRunFinished: messages.TestRunFinished(
          success: message == null,
          timestamp: const messages.Timestamp(seconds: 1, nanos: 0),
          testRunStartedId: 'run',
          message: message,
          exception: message == null
              ? null
              : messages.Exception(type: 'StateError', message: message),
        ),
      );
      final started = messages.Envelope(
        testRunStarted: const messages.TestRunStarted(
          id: 'run',
          timestamp: messages.Timestamp(seconds: 0, nanos: 0),
        ),
      );
      final merged = mergeReportParts([
        ReportPart('a', [started, finished(null)]),
        ReportPart('b', [started, finished('internal error')]),
      ]);
      final result = _of(merged, (e) => e.testRunFinished).single;
      expect(result.success, isFalse);
      expect(result.message, 'Suite "b": internal error');
      expect(result.exception?.type, 'StateError');

      final single = _of(
        mergeReportParts([
          ReportPart('b', [started, finished('internal error')]),
        ]),
        (e) => e.testRunFinished,
      ).single;
      expect(single.message, 'internal error');
    });

    test('sets workerId to the suite ID on testCaseStarted and '
        'testRunHookStarted', () async {
      final merged = mergeReportParts([await _cartPart(), await _searchPart()]);
      expect(_of(merged, (e) => e.testCaseStarted).map((s) => s.workerId), [
        'cart',
        'cart',
        'search',
        'search',
      ]);
      expect(_of(merged, (e) => e.testRunHookStarted).map((h) => h.workerId), [
        'cart',
        'search',
      ]);
    });

    test('renames clashing dynamic IDs and every reference to them', () async {
      // With incrementing IDs, two runs of the same features allocate the
      // same static IDs (which are de-duplicated) and the same dynamic IDs
      // (which clash).
      final cart = await _cartPart(ids: IdScheme.incrementing());
      final again = ReportPart(
        'again',
        (await _cartPart(ids: IdScheme.incrementing())).envelopes,
      );
      final merged = mergeReportParts([cart, again]);
      expect(_of(merged, (e) => e.pickle), hasLength(3));

      final testCases = _of(merged, (e) => e.testCase);
      final testCaseIds = testCases.map((t) => t.id).toList();
      expect(testCaseIds.toSet(), hasLength(testCaseIds.length));
      final cartIds = _of(cart.envelopes, (e) => e.testCase).map((t) => t.id);
      expect(testCaseIds.take(2), cartIds, reason: 'the first part keeps its');
      expect(testCaseIds.skip(2), [for (final id in cartIds) 'again/$id']);

      final steps = {
        for (final testCase in testCases)
          for (final step in testCase.testSteps) step.id,
      };
      final starts = {
        for (final s in _of(merged, (e) => e.testCaseStarted)) s.id: s,
      };
      expect(starts, hasLength(4));
      for (final s in starts.values) {
        expect(testCaseIds, contains(s.testCaseId));
      }
      for (final f in _of(merged, (e) => e.testStepFinished)) {
        expect(starts, contains(f.testCaseStartedId));
        expect(steps, contains(f.testStepId));
      }
      // References to static messages are left alone.
      final pickleIds = _of(merged, (e) => e.pickle).map((p) => p.id).toSet();
      expect(testCases.map((t) => t.pickleId), everyElement(isIn(pickleIds)));
      expect(partialOrderProblems(toJson(merged)), isEmpty);
    });

    test('keeps a valid order', () async {
      final merged = mergeReportParts([
        await _cartPart(),
        await _searchPart(failing: true),
      ]);
      expect(partialOrderProblems(toJson(merged)), isEmpty);
      const staticTypes = {
        'meta',
        'source',
        'gherkinDocument',
        'parseError',
        'pickle',
        'parameterType',
        'stepDefinition',
        'hook',
        'undefinedParameterType',
      };
      final types = [for (final json in toJson(merged)) typeOf(json)];
      final runStarted = types.indexOf('testRunStarted');
      expect(types.take(runStarted), everyElement(isIn(staticTypes)));
      expect(
        types.skip(runStarted + 1),
        everyElement(isNot(isIn(staticTypes))),
      );
      expect(
        types.lastIndexWhere((t) => t == 'pickle'),
        lessThan(types.indexOf('stepDefinition')),
        reason: 'Gherkin messages come before glue messages',
      );
    });

    test('a single part is unchanged except for workerId', () async {
      final cart = await _cartPart();
      final merged = mergeReportParts([cart]);
      final json = toJson(merged);
      for (final envelope in json) {
        (envelope['testCaseStarted'] as Map<String, Object?>?)?.remove(
          'workerId',
        );
        (envelope['testRunHookStarted'] as Map<String, Object?>?)?.remove(
          'workerId',
        );
      }
      expect(json, toJson(cart.envelopes));
    });

    test('merges no parts into nothing', () {
      expect(mergeReportParts(const []), isEmpty);
    });

    test('rejects parts with the same suite ID', () async {
      final cart = await _cartPart();
      expect(() => mergeReportParts([cart, cart]), throwsArgumentError);
    });
  });

  group('merging a Compatibility Kit sample with itself', () {
    for (final dir in sampleDirectories()) {
      final name = sampleName(dir);
      test(name, () {
        final sample = [
          for (final json in expectedMessages(dir))
            messages.Envelope.fromJson(json),
        ];
        final merged = mergeReportParts([
          ReportPart('a', sample),
          ReportPart('b', sample),
        ]);
        expect(partialOrderProblems(toJson(merged)), isEmpty);

        final single = _query(sample);
        final query = _query(merged);

        // Static messages are de-duplicated.
        int count(Query q, Iterable<Object?> Function(Query) find) =>
            find(q).length;
        for (final find in <Iterable<Object?> Function(Query)>[
          (q) => q.findAllPickles(),
          (q) => q.findAllPickleSteps(),
          (q) => q.findAllStepDefinitions(),
          (q) => q.findAllUndefinedParameterTypes(),
        ]) {
          expect(count(query, find), count(single, find));
        }
        // Dynamic messages are kept from both parts.
        for (final find in <Iterable<Object?> Function(Query)>[
          (q) => q.findAllTestCases(),
          (q) => q.findAllTestCaseStarted(),
          (q) => q.findAllTestCaseFinished(),
          (q) => q.findAllTestSteps(),
          (q) => q.findAllTestStepStarted(),
          (q) => q.findAllTestStepFinished(),
          (q) => q.findAllTestRunHookStarted(),
          (q) => q.findAllTestRunHookFinished(),
        ]) {
          expect(count(query, find), 2 * count(single, find));
        }
        expect(
          query.countTestCasesStarted(),
          2 * single.countTestCasesStarted(),
        );
        expect(query.countMostSevereTestStepResultStatus(), {
          for (final MapEntry(:key, :value)
              in single.countMostSevereTestStepResultStatus().entries)
            key: 2 * value,
        });

        expect(query.findMeta(), single.findMeta());
        expect(query.findTestRunStarted()?.timestamp, isNotNull);
        expect(
          query.findTestRunStarted()?.timestamp,
          single.findTestRunStarted()?.timestamp,
        );
        expect(
          query.findTestRunFinished()?.timestamp,
          single.findTestRunFinished()?.timestamp,
        );
        expect(
          query.findTestRunFinished()?.success,
          single.findTestRunFinished()?.success,
        );
        expect(query.findTestRunDuration(), single.findTestRunDuration());

        // Every attempt still finds its pickle, test case, steps,
        // attachments and lineage.
        final singleAttempts = single.findAllTestCaseStarted();
        final attempts = query.findAllTestCaseStarted();
        expect(attempts.map((a) => a.workerId).toSet(), {
          if (attempts.isNotEmpty) ...{'a', 'b'},
        });
        String describe(Query q, messages.TestCaseStarted attempt) {
          final steps = q.findTestStepFinishedAndTestStepBy(attempt);
          return [
            q.findPickleBy(attempt)?.name,
            q.findTestCaseBy(attempt)?.testSteps.length,
            q.findTestCaseFinishedBy(attempt)?.willBeRetried,
            q.findMostSevereTestStepResultBy(attempt)?.status.value,
            q.findLineageBy(attempt)?.feature?.name,
            [
              for (final (finished, step) in steps)
                '${q.findPickleStepBy(step)?.text} '
                    '${finished.testStepResult.status.value} '
                    '${q.findAttachmentsBy(finished).length}',
            ],
          ].join(' | ');
        }

        expect(
          [for (final attempt in attempts) describe(query, attempt)],
          unorderedEquals([
            for (final _ in ['a', 'b'])
              for (final attempt in singleAttempts) describe(single, attempt),
          ]),
        );
        expect(
          [
            for (final hook in query.findAllTestRunHookFinished())
              '${query.findHookBy(hook)?.id} ${hook.result.status.value} '
                  '${query.findAttachmentsBy(hook).length}',
          ],
          [
            for (final _ in ['a', 'b'])
              for (final hook in single.findAllTestRunHookFinished())
                '${single.findHookBy(hook)?.id} ${hook.result.status.value} '
                    '${single.findAttachmentsBy(hook).length}',
          ],
        );
        expect(
          [
            for (final step in query.findAllPickleSteps())
              query.findSuggestionsBy(step).length,
          ],
          [
            for (final step in single.findAllPickleSteps())
              2 * single.findSuggestionsBy(step).length,
          ],
        );

        // The summary counts both parts.
        final scenarios = 2 * singleAttempts.length;
        expect(
          formatSummary(query),
          matches(RegExp('(^|\\n)$scenarios scenarios?( |\\n|\$)')),
        );
      });
    }
  });
}

Duration _seconds(int seconds) => Duration(seconds: seconds);
