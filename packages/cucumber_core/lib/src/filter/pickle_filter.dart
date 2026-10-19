import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../gherkin/gherkin_index.dart';
import '../tag_expressions/tag_expression.dart';

/// Selects pickles by tag expression, name and line (design §5.10).
///
/// A pickle is selected when it matches the tag expression, at least one of
/// the name patterns (if any), and at least one of the lines given for its
/// file (if any).
final class PickleFilter {
  /// Creates a filter.
  ///
  /// - [tags]: a Cucumber tag expression, such as `@smoke and not @wip`.
  /// - [names]: regular expressions, at least one of which must match the
  ///   pickle name.
  /// - [lines]: lines per feature file URI. A pickle matches a line when it is
  ///   the line of its scenario, one of the scenario's steps, its example row,
  ///   its `Examples`, its rule or its feature.
  ///
  /// Throws an [ArgumentError] for an invalid tag expression or name pattern.
  factory PickleFilter({
    String? tags,
    List<String> names = const [],
    Map<String, Set<int>> lines = const {},
  }) {
    TagExpression? tagExpression;
    if (tags != null) {
      try {
        tagExpression = TagExpression.parse(tags);
      } on TagExpressionException catch (e) {
        throw ArgumentError.value(tags, 'tags', e.message);
      }
    }
    final patterns = <RegExp>[];
    for (final name in names) {
      try {
        patterns.add(RegExp(name));
      } on FormatException catch (e) {
        throw ArgumentError.value(name, 'names', e.message);
      }
    }
    return PickleFilter._(tagExpression, patterns, {
      for (final entry in lines.entries) entry.key: {...entry.value},
    });
  }

  PickleFilter._(this._tags, this._names, this._lines);

  final TagExpression? _tags;
  final List<RegExp> _names;
  final Map<String, Set<int>> _lines;

  /// Whether [pickle] is selected. [index] is the index of its document.
  bool matches(messages.Pickle pickle, GherkinIndex? index) {
    final tags = _tags;
    if (tags != null && !tags.evaluate([for (final t in pickle.tags) t.name])) {
      return false;
    }
    if (_names.isNotEmpty && !_names.any((n) => n.hasMatch(pickle.name))) {
      return false;
    }
    final lines = _lines[pickle.uri];
    if (lines != null && lines.isNotEmpty) {
      return pickleLines(pickle, index).any(lines.contains);
    }
    return true;
  }

  /// The lines that select [pickle].
  static Set<int> pickleLines(messages.Pickle pickle, GherkinIndex? index) {
    final lines = <int>{};
    if (pickle.location case final location?) lines.add(location.line);
    final scenario = index?.scenarioOf(pickle);
    if (scenario != null) {
      lines
        ..add(scenario.feature.location.line)
        ..add(scenario.scenario.location.line);
      if (scenario.rule case final rule?) lines.add(rule.location.line);
      for (final step in scenario.scenario.steps) {
        lines.add(step.location.line);
      }
    }
    final row = index?.exampleRowOf(pickle);
    if (row != null) {
      lines
        ..add(row.row.location.line)
        ..add(row.examples.location.line);
    }
    return lines;
  }
}
