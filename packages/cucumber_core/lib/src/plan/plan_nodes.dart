import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../gherkin/gherkin_index.dart';

/// A node of a SuitePlan tree, which hosts declare as groups and tests
/// (design §6).
///
/// Names follow cucumber-jvm's "short" strategy: a node's name, or its keyword
/// when it has no name.
sealed class PlanNode {
  const PlanNode();

  /// The feature file URI.
  String get uri;

  /// The Gherkin keyword, such as `Feature` or `Scenario Outline`.
  String get keyword;

  /// The name, which may be empty.
  String get name;

  /// The location in the feature file.
  messages.Location get location;

  /// The name to show in test runners.
  String get displayName => name.trim().isEmpty ? keyword : name.trim();
}

/// A node with children.
sealed class PlanGroup extends PlanNode {
  const PlanGroup(this.children);

  /// The child nodes, in run order.
  final List<PlanNode> children;
}

/// A feature.
final class FeatureNode extends PlanGroup {
  /// Creates a feature node.
  const FeatureNode(this.uri, this.feature, super.children);

  @override
  final String uri;

  /// The feature.
  final messages.Feature feature;

  @override
  String get keyword => feature.keyword;

  @override
  String get name => feature.name;

  @override
  messages.Location get location => feature.location;
}

/// A rule.
final class RuleNode extends PlanGroup {
  /// Creates a rule node.
  const RuleNode(this.uri, this.rule, super.children);

  @override
  final String uri;

  /// The rule.
  final messages.Rule rule;

  @override
  String get keyword => rule.keyword;

  @override
  String get name => rule.name;

  @override
  messages.Location get location => rule.location;
}

/// A scenario outline, whose children are [ExamplesNode]s.
final class OutlineNode extends PlanGroup {
  /// Creates an outline node.
  const OutlineNode(this.uri, this.scenario, super.children);

  @override
  final String uri;

  /// The scenario outline.
  final messages.Scenario scenario;

  @override
  String get keyword => scenario.keyword;

  @override
  String get name => scenario.name;

  @override
  messages.Location get location => scenario.location;
}

/// An `Examples` section, whose children are [PickleNode]s.
final class ExamplesNode extends PlanGroup {
  /// Creates an examples node.
  const ExamplesNode(this.uri, this.examples, this.index, super.children);

  @override
  final String uri;

  /// The examples.
  final messages.Examples examples;

  /// The 0-based index of the examples in the outline.
  final int index;

  @override
  String get keyword => examples.keyword;

  @override
  String get name => examples.name;

  @override
  messages.Location get location => examples.location;
}

/// A pickle: a scenario or an example row. Hosts declare one test per pickle
/// and run it with `SuitePlan.runPickle`.
final class PickleNode extends PlanNode {
  /// Creates a pickle node.
  PickleNode(this.pickle, this.index)
    : scenario = index?.scenarioOf(pickle),
      exampleRow = index?.exampleRowOf(pickle);

  /// The pickle.
  final messages.Pickle pickle;

  /// The index of the pickle's Gherkin document.
  final GherkinIndex? index;

  /// The scenario the pickle was compiled from.
  final ScenarioLocation? scenario;

  /// The example row, for scenario outlines.
  final ExampleRowLocation? exampleRow;

  @override
  String get uri => pickle.uri;

  @override
  String get keyword => scenario?.scenario.keyword ?? 'Scenario';

  @override
  String get name => pickle.name;

  /// The tags, with their `@`.
  List<String> get tags => [for (final tag in pickle.tags) tag.name];

  @override
  messages.Location get location =>
      pickle.location ??
      scenario?.scenario.location ??
      const messages.Location(line: 1);

  /// For scenarios, the name (or keyword). For example rows,
  /// `Example #<examples>.<row>`, followed by `: <pickle name>` when the
  /// name differs from the outline's (cucumber-jvm
  /// `number-and-pickle-if-parameterized`).
  @override
  String get displayName {
    final row = exampleRow;
    if (row == null) return super.displayName;
    final number = 'Example #${row.examplesIndex + 1}.${row.rowIndex + 1}';
    final outlineName = scenario?.scenario.name ?? '';
    return pickle.name == outlineName ? number : '$number: ${pickle.name}';
  }
}

/// A feature file that failed to parse. Hosts declare a failing test for it
/// (design §5.9).
final class ParseErrorNode extends PlanNode {
  /// Creates a parse error node.
  const ParseErrorNode(this.uri, this.errors);

  @override
  final String uri;

  /// The parse errors.
  final List<messages.ParseError> errors;

  @override
  String get keyword => 'Feature';

  @override
  String get name => uri;

  @override
  messages.Location get location =>
      errors.first.source.location ?? const messages.Location(line: 1);

  /// The parse errors, one per line.
  String get message => errors.map((e) => e.message).join('\n');
}

/// Arranges [pickles] (in run order) into a tree. Consecutive pickles that
/// share a feature, rule, outline or examples are grouped together.
List<PlanNode> buildPlanTree(List<PickleNode> pickles) {
  final root = _Builder(null, null);
  for (final node in pickles) {
    var level = root;
    for (final (key, create) in _ancestors(node)) {
      final last = level.children.isEmpty ? null : level.children.last;
      if (last is _Builder && last.key == key) {
        level = last;
      } else {
        final child = _Builder(key, create);
        level.children.add(child);
        level = child;
      }
    }
    level.children.add(node);
  }
  return root.build();
}

typedef _Create = PlanGroup Function(List<PlanNode> children);

List<(String, _Create)> _ancestors(PickleNode node) {
  final location = node.scenario;
  if (location == null) return const [];
  final uri = node.uri;
  final row = node.exampleRow;
  return [
    ('feature:$uri', (c) => FeatureNode(uri, location.feature, c)),
    if (location.rule case final rule?)
      ('rule:$uri:${rule.id}', (c) => RuleNode(uri, rule, c)),
    if (row != null) ...[
      (
        'outline:$uri:${location.scenario.id}',
        (c) => OutlineNode(uri, location.scenario, c),
      ),
      (
        'examples:$uri:${row.examples.id}',
        (c) => ExamplesNode(uri, row.examples, row.examplesIndex, c),
      ),
    ],
  ];
}

final class _Builder {
  _Builder(this.key, this.create);

  final String? key;
  final _Create? create;
  final List<Object> children = [];

  List<PlanNode> build() => List.unmodifiable([
    for (final child in children)
      if (child is _Builder)
        child.create!(child.build())
      else
        child as PlanNode,
  ]);
}
