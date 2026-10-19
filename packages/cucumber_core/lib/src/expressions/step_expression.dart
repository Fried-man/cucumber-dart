import 'package:cucumber_expressions/cucumber_expressions.dart' as ce;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import 'parameter_types.dart';
import 'tree_regexp.dart';

/// A compiled step definition expression.
final class StepExpression {
  /// Creates a compiled expression. Use [ParameterTypes.compile].
  StepExpression(this.source, this.expression, this.tree, this.parameterTypes);

  /// The original expression: a `String` or a `RegExp`.
  final Object source;

  /// The expression compiled by `package:cucumber_expressions`.
  final ce.Expression expression;

  /// The analysed regular expression, which reports group offsets.
  final TreeRegexp tree;

  /// The parameter type of each top-level group. `null` means an untyped
  /// regular expression group, whose argument is the group's text.
  final List<ParameterTypeDefinition?> parameterTypes;

  /// Whether this is a regular expression rather than a Cucumber Expression.
  bool get isRegularExpression => source is RegExp;

  /// The pattern source, as reported in `stepDefinition.pattern.source`.
  String get patternSource => expression.source;

  /// The pattern as a Cucumber Messages `StepDefinitionPattern`.
  messages.StepDefinitionPattern toPatternMessage() =>
      messages.StepDefinitionPattern(
        source: patternSource,
        type: isRegularExpression
            ? messages.StepDefinitionPatternType.regularExpression
            : messages.StepDefinitionPatternType.cucumberExpression,
      );

  /// Matches step [text]; returns one argument per parameter, or `null` when
  /// [text] does not match.
  List<StepArgument>? match(String text) {
    final root = tree.match(text);
    if (root == null) return null;
    return [
      for (var i = 0; i < root.children.length; i++)
        StepArgument(root.children[i], parameterTypes[i]),
    ];
  }
}

/// A matched argument of a step.
final class StepArgument {
  /// Creates an argument for [group], typed by [parameterType].
  const StepArgument(this.group, this.parameterType);

  /// The matched group, with offsets.
  final MatchedGroup group;

  /// The parameter type, or `null` for an untyped regular expression group.
  final ParameterTypeDefinition? parameterType;

  /// This argument as a Cucumber Messages `StepMatchArgument`.
  messages.StepMatchArgument toMessage() => messages.StepMatchArgument(
    group: group.toMessage(),
    parameterTypeName: parameterType?.name,
  );
}
