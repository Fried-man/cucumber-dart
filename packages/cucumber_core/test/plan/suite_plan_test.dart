import 'package:cucumber_core/engine.dart';
import 'package:test/test.dart';

import '../support.dart';

const _feature = '''
@feature
Feature: Shopping

  Scenario: Browse
    Given a step

  Rule: Payments
    @card
    Scenario Outline: Pay with <method>
      Given a step

      Examples: Cards
        | method |
        | visa   |
        | amex   |

      @cash
      Examples:
        | method |
        | cash   |

    Scenario: Refund
      Given a step
''';

final _glue = [Given('a step', () {})];

SuitePlan _plan({
  RunOptions options = const RunOptions(),
  List<Plugin> plugins = const [],
}) => SuitePlan.create(
  features: [const FeatureSource('features/shop.feature', _feature)],
  glue: _glue,
  options: options,
  plugins: plugins,
);

String _describe(PlanNode node, [String indent = '']) {
  final line =
      '$indent${node.runtimeType}: ${node.displayName} '
      '(${node.location.line})';
  if (node is PlanGroup) {
    return [
      line,
      for (final c in node.children) _describe(c, '$indent  '),
    ].join('\n');
  }
  return line;
}

void main() {
  test('arranges pickles into a tree with short names (design §6)', () {
    final plan = _plan();
    expect(plan.children.map(_describe).join('\n'), '''
FeatureNode: Shopping (2)
  PickleNode: Browse (4)
  RuleNode: Payments (7)
    OutlineNode: Pay with <method> (9)
      ExamplesNode: Cards (12)
        PickleNode: Example #1.1: Pay with visa (14)
        PickleNode: Example #1.2: Pay with amex (15)
      ExamplesNode: Examples (18)
        PickleNode: Example #2.1: Pay with cash (20)
    PickleNode: Refund (22)''');
    expect(plan.pickles[1].tags, ['@feature', '@card']);
  });

  test('example rows are only numbered when the name is not parameterised', () {
    final plan = SuitePlan.create(
      features: [
        const FeatureSource('a.feature', '''
Feature: f
  Scenario Outline: same name
    Given a step <x>
    Examples:
      | x |
      | 1 |
'''),
      ],
      glue: [Given('a step {int}', (int x) {})],
    );
    expect(plan.pickles.single.displayName, 'Example #1.1');
  });

  group('filters', () {
    List<String> names(SuitePlan plan) => [
      for (final p in plan.pickles) p.name,
    ];

    test('by tag expression', () {
      expect(
        names(_plan(options: const RunOptions(tags: '@card and not @cash'))),
        ['Pay with visa', 'Pay with amex'],
      );
    });

    test('by name', () {
      expect(
        names(_plan(options: const RunOptions(names: ['^Re', 'Browse']))),
        ['Browse', 'Refund'],
      );
    });

    test('by line', () {
      Iterable<String> at(Set<int> lines) => names(
        _plan(options: RunOptions(lines: {'features/shop.feature': lines})),
      );
      expect(at({4}), ['Browse']);
      expect(at({5}), ['Browse'], reason: 'a step line selects its scenario');
      expect(at({15}), ['Pay with amex'], reason: 'an example row');
      expect(at({12}), ['Pay with visa', 'Pay with amex'], reason: 'Examples');
      expect(at({7}), hasLength(4), reason: 'a rule');
      expect(at({2}), hasLength(5), reason: 'the feature');
      expect(at({1}), isEmpty);
    });

    test('filtered pickles are still emitted as messages', () async {
      final collector = CollectingPlugin();
      final plan = _plan(
        options: const RunOptions(tags: '@cash'),
        plugins: [collector],
      );
      await const SerialHost().run(plan);
      expect(collector.envelopes.where((e) => e.pickle != null), hasLength(5));
      expect(
        collector.envelopes.where((e) => e.testCase != null),
        hasLength(1),
      );
    });

    test('reject invalid options', () {
      expect(
        () => _plan(options: const RunOptions(tags: 'a and')),
        throwsArgumentError,
      );
      expect(
        () => _plan(options: const RunOptions(names: ['('])),
        throwsArgumentError,
      );
      expect(
        () => _plan(options: const RunOptions(retry: -1)),
        throwsArgumentError,
      );
    });
  });

  test('reverse order reverses the tree', () {
    final plan = _plan(options: const RunOptions(order: PickleOrder.reverse));
    expect(
      [for (final p in plan.pickles) p.name],
      ['Refund', 'Pay with cash', 'Pay with amex', 'Pay with visa', 'Browse'],
    );
    final feature = plan.children.single as FeatureNode;
    expect(feature.children.first, isA<RuleNode>());
    expect(feature.children.last, isA<PickleNode>());
  });

  test('parse errors become plan nodes and fail the run', () async {
    final collector = CollectingPlugin();
    final plan = SuitePlan.create(
      features: [
        const FeatureSource('bad.feature', 'Scenario: no feature\n'),
        const FeatureSource(
          'good.feature',
          'Feature: g\n  Scenario: s\n    Given a step\n',
        ),
      ],
      glue: _glue,
      plugins: [collector],
    );
    expect(plan.parseErrors.single.uri, 'bad.feature');
    expect(plan.children.first, isA<ParseErrorNode>());
    expect(plan.parseErrors.single.message, contains('expected'));
    final result = await const SerialHost().run(plan);
    expect(result.testCases.single.status, Status.passed);
    expect(result.success, isFalse);
    expect(collector.envelopes.where((e) => e.parseError != null), isNotEmpty);
    expect(collector.envelopes.last.testRunFinished!.success, isFalse);
  });

  test('a plan that never starts writes nothing', () async {
    final collector = CollectingPlugin();
    final plan = _plan(plugins: [collector]);
    final result = await plan.finish();
    expect(collector.envelopes, isEmpty);
    expect(collector.isClosed, isTrue);
    expect(result.testCases, isEmpty);
  });

  test('emits messages in the documented order (design §7.1)', () async {
    final run = await runFeature(
      'Feature: f\n  Scenario: s\n    Given a step\n',
      [BeforeAll(() {}), ..._glue, AfterAll(() {})],
    );
    final types = [for (final e in run.envelopes) e.toJson().keys.single];
    expect(types, [
      'meta',
      'source',
      'gherkinDocument',
      'pickle',
      'hook',
      'stepDefinition',
      'hook',
      'testRunStarted',
      'testRunHookStarted',
      'testRunHookFinished',
      'testCase',
      'testCaseStarted',
      'testStepStarted',
      'testStepFinished',
      'testCaseFinished',
      'testRunHookStarted',
      'testRunHookFinished',
      'testRunFinished',
    ]);
    final meta = run.envelopes.first.meta!;
    expect(meta.protocolVersion, protocolVersion);
    expect(meta.implementation.name, 'cucumber-dart');
  });

  test('uses deterministic static IDs by default', () {
    String firstPickleId() => _plan().pickles.first.pickle.id;
    expect(firstPickleId(), firstPickleId());
  });

  test('runPickle starts the run and reports results', () async {
    final plan = _plan();
    final result = await plan.runPickle(plan.pickles.first);
    expect(plan.isStarted, isTrue);
    expect(result.status, Status.passed);
    expect(result.ran, isTrue);
    expect(result.attempts, 1);
    final runResult = await plan.finish();
    expect(runResult.success, isTrue);
    expect(() => plan.runPickle(plan.pickles.last), throwsStateError);
  });
}
