import 'package:cucumber_expressions/cucumber_expressions.dart' as ce;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../expressions/parameter_types.dart';

/// Generates Dart step definition snippets for undefined steps (design §7.5).
///
/// ```dart
/// Given('I have {int} cukes in my belly', (BellyWorld world, int int1) {
///   // Write code here that turns the phrase above into concrete actions
///   throw PendingException();
/// }),
/// ```
final class SnippetGenerator {
  /// Creates a generator using [parameterTypes]. When [worldTypeName] is given,
  /// snippets take the World as their first parameter.
  SnippetGenerator(this.parameterTypes, {this.worldTypeName})
    : _generator = ce.CucumberExpressionGenerator(
        parameterTypes.expressionRegistry,
      );

  /// The parameter types used to generate expressions.
  final ParameterTypes parameterTypes;

  /// The World type name, or `null` to leave the World out.
  final String? worldTypeName;

  final ce.CucumberExpressionGenerator _generator;

  /// The keyword for a pickle step [type].
  static String keyword(messages.PickleStepType? type) => switch (type) {
    messages.PickleStepType.action => 'When',
    messages.PickleStepType.outcome => 'Then',
    messages.PickleStepType.context ||
    messages.PickleStepType.unknown ||
    null => 'Given',
  };

  /// One snippet per generated expression, as reported in `suggestion`
  /// messages.
  List<String> generateAll(messages.PickleStep step) => [
    for (final head in _heads(step)) [head, ..._body].join('\n'),
  ];

  /// The snippet for [step] shown to users: the first generated expression as
  /// code, the others as comments.
  String generate(messages.PickleStep step) => present(generateAll(step));

  /// Combines the snippets of one step (as in a `suggestion` message, one per
  /// expression) into the snippet shown to users: the first as code, and the
  /// first line of each other as a comment (design §7.5).
  ///
  /// Returns an empty string when [snippets] is empty.
  static String present(List<String> snippets) {
    if (snippets.isEmpty) return '';
    final alternatives = [
      for (final snippet in snippets.skip(1)) '// ${snippet.split('\n').first}',
    ];
    return [
      snippets.first,
      if (alternatives.isNotEmpty) '// Or use one of these expressions:',
      ...alternatives,
    ].join('\n');
  }

  static const List<String> _body = [
    '  // Write code here that turns the phrase above into concrete actions',
    '  throw PendingException();',
    '}),',
  ];

  List<String> _heads(messages.PickleStep step) {
    final keyword = SnippetGenerator.keyword(step.type);
    final multiline = _multilineParameters(step.argument);
    return [
      for (final expression in _generator.generateExpressions(step.text))
        "$keyword('${_escape(expression.source)}', (${[if (worldTypeName != null) '$worldTypeName world', ..._parameters(expression), ...multiline].join(', ')}) {",
    ];
  }

  List<String> _parameters(ce.GeneratedExpression expression) {
    final counts = <String, int>{};
    return [
      for (final type in expression.parameterTypes)
        () {
          final name = type.name ?? '';
          final definition = parameterTypes.byName(name);
          final base = _identifier(name.isEmpty ? 'arg' : name);
          final count = counts[base] = (counts[base] ?? 0) + 1;
          return '${definition?.typeName ?? 'String'} $base$count';
        }(),
    ];
  }

  static List<String> _multilineParameters(
    messages.PickleStepArgument? argument,
  ) {
    if (argument == null) return const [];
    final table = argument.dataTable;
    final docString = argument.docString;
    final parameters = <(int, String)>[
      if (table != null) (table.argumentIndex ?? 0, 'DataTable dataTable'),
      if (docString != null)
        (docString.argumentIndex ?? 0, 'DocString docString'),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final p in parameters) p.$2];
  }

  static String _identifier(String name) {
    final cleaned = name.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    return RegExp('^[0-9]').hasMatch(cleaned) ? 'arg$cleaned' : cleaned;
  }

  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');
}
