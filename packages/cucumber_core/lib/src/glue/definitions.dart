import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../expressions/parameter_types.dart';
import '../expressions/step_expression.dart';
import '../tag_expressions/tag_expression.dart';
import 'glue.dart';

/// Where the World and the multiline arguments go in a step body.
final class StepLayout {
  /// Creates a layout.
  const StepLayout({
    required this.world,
    required this.multilineCount,
    this.problem,
  });

  /// Whether the World is the first parameter.
  final bool world;

  /// How many multiline arguments (data table, doc string) follow the
  /// expression arguments.
  final int multilineCount;

  /// Why the body cannot be called with this layout (a type mismatch found at
  /// load time), or `null` when it can.
  final String? problem;
}

/// A loaded step definition.
final class StepDefinition {
  /// Creates a loaded step definition.
  StepDefinition({
    required this.id,
    required this.glue,
    required this.expression,
    required this.arity,
    required this.layouts,
  });

  /// The message ID.
  final String id;

  /// The glue value.
  final StepGlue glue;

  /// The compiled expression.
  final StepExpression expression;

  /// The number of positional parameters the body takes.
  final int arity;

  /// The layouts the body's arity allows, with any type problem found at load
  /// time.
  final List<StepLayout> layouts;

  /// The number of expression parameters.
  int get parameterCount => expression.parameterTypes.length;

  /// The layout for a step with [multilineCount] multiline arguments, or
  /// `null` when the body's arity does not fit (design §4.5).
  StepLayout? layoutFor(int multilineCount) {
    for (final layout in layouts) {
      if (layout.multilineCount == multilineCount) return layout;
    }
    return null;
  }

  /// Matches [text].
  List<StepArgument>? match(String text) => expression.match(text);

  /// This definition as a message.
  messages.StepDefinition toMessage() => messages.StepDefinition(
    id: id,
    pattern: expression.toPatternMessage(),
    sourceReference:
        glue.source?.toMessage() ?? const messages.SourceReference(),
  );
}

/// What a hook body receives.
enum HookLayout {
  /// Nothing.
  none,

  /// The World.
  world,

  /// The context object (`Scenario`, `Step` or `TestRun`).
  context,

  /// The World and the context object.
  worldAndContext,
}

/// A loaded hook.
final class HookDefinition {
  /// Creates a loaded hook.
  HookDefinition({
    required this.id,
    required this.glue,
    required this.index,
    required this.layout,
    this.tagExpression,
  });

  /// The message ID.
  final String id;

  /// The glue value.
  final HookGlue glue;

  /// The definition index among all glue values.
  final int index;

  /// What the body receives.
  final HookLayout layout;

  /// The parsed tag expression, if the hook has one.
  final TagExpression? tagExpression;

  /// The kind of hook.
  HookKind get kind => glue.kind;

  /// Whether this hook runs for a scenario with [tags].
  bool appliesTo(Iterable<String> tags) =>
      tagExpression?.evaluate(tags) ?? true;

  /// This hook as a message.
  messages.Hook toMessage() => messages.Hook(
    id: id,
    name: glue.name,
    sourceReference:
        glue.source?.toMessage() ?? const messages.SourceReference(),
    tagExpression: glue.tags,
    type: switch (kind) {
      HookKind.before => messages.HookType.beforeTestCase,
      HookKind.after => messages.HookType.afterTestCase,
      HookKind.beforeStep => messages.HookType.beforeTestStep,
      HookKind.afterStep => messages.HookType.afterTestStep,
      HookKind.beforeAll => messages.HookType.beforeTestRun,
      HookKind.afterAll => messages.HookType.afterTestRun,
    },
  );
}

/// A user parameter type with its transformer layout.
final class UserParameterType {
  /// Creates a loaded parameter type.
  UserParameterType({
    required this.id,
    required this.glue,
    required this.definition,
  });

  /// The message ID.
  final String id;

  /// The glue value.
  final ParameterType<Object?> glue;

  /// The engine's definition.
  final ParameterTypeDefinition definition;

  /// This parameter type as a message.
  messages.ParameterType toMessage() => messages.ParameterType(
    id: id,
    name: definition.name,
    regularExpressions: definition.regexps,
    preferForRegularExpressionMatch: definition.preferForRegexpMatch,
    useForSnippets: definition.useForSnippets,
    sourceReference: glue.source?.toMessage(),
  );
}
