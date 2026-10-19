import 'dart:async';

import 'package:cucumber_expressions/cucumber_expressions.dart' as ce;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../data/table_converter.dart';
import '../exceptions.dart';
import '../expressions/parameter_types.dart';
import '../expressions/step_expression.dart';
import '../expressions/tree_regexp.dart';
import '../runtime/ids.dart';
import '../tag_expressions/tag_expression.dart';
import '../world/scenario.dart';
import '../world/world.dart';
import 'definitions.dart';
import 'function_shapes.g.dart';
import 'glue.dart';

/// The smallest number of positional arguments [f] can be called with, or
/// `null` if it needs more than [maxArity] or has required named parameters.
int? minimumArity(Function f) {
  for (var arity = 0; arity <= maxArity; arity++) {
    if (hasArity(f, arity)) return arity;
  }
  return null;
}

/// Validated glue: compiled step definitions, sorted hooks, parameter types,
/// data table and doc string types, and the glue messages (design §3.3,
/// §4.5).
final class SupportCodeLibrary {
  SupportCodeLibrary._({
    required this.worldType,
    required this.worldTypeName,
    required this.parameterTypes,
    required this.userParameterTypes,
    required this.stepDefinitions,
    required List<HookDefinition> hooks,
    required this.converter,
    required this.envelopes,
    required this.undefinedParameterTypes,
  }) : beforeHooks = _sorted(hooks, HookKind.before),
       afterHooks = _sorted(hooks, HookKind.after),
       beforeStepHooks = _sorted(hooks, HookKind.beforeStep),
       afterStepHooks = _sorted(hooks, HookKind.afterStep),
       beforeAllHooks = _sorted(hooks, HookKind.beforeAll),
       afterAllHooks = _sorted(hooks, HookKind.afterAll);

  /// Loads [glue], allocating message IDs from [ids].
  ///
  /// `W` is the suite's World type; bodies that take a World are checked
  /// against it.
  ///
  /// Throws a [GlueException] listing every invalid glue value.
  static SupportCodeLibrary load<W extends Object>(
    List<Glue> glue, {
    required IdScheme ids,
  }) => _Loader<W>(glue, ids).load();

  /// The World type.
  final TypeWitness<Object> worldType;

  /// The World type's name for snippets, or `null` when the suite uses the
  /// default World.
  final String? worldTypeName;

  /// The parameter types, built-in and user-defined.
  final ParameterTypes parameterTypes;

  /// The user-defined parameter types, in definition order.
  final List<UserParameterType> userParameterTypes;

  /// The step definitions, in definition order.
  final List<StepDefinition> stepDefinitions;

  /// `Before` hooks, in run order (ascending).
  final List<HookDefinition> beforeHooks;

  /// `After` hooks, in run order (descending).
  final List<HookDefinition> afterHooks;

  /// `BeforeStep` hooks, in run order (ascending).
  final List<HookDefinition> beforeStepHooks;

  /// `AfterStep` hooks, in run order (descending).
  final List<HookDefinition> afterStepHooks;

  /// `BeforeAll` hooks, in run order (ascending).
  final List<HookDefinition> beforeAllHooks;

  /// `AfterAll` hooks, in run order (descending).
  final List<HookDefinition> afterAllHooks;

  /// Converts data tables and doc strings with the registered types.
  final TableConverter converter;

  /// The glue messages (`parameterType`, `stepDefinition`, `hook` and
  /// `undefinedParameterType`), in definition order.
  final List<messages.Envelope> envelopes;

  /// The parameter types that were referenced but not defined.
  final List<messages.UndefinedParameterType> undefinedParameterTypes;

  static List<HookDefinition> _sorted(
    List<HookDefinition> hooks,
    HookKind kind,
  ) {
    final selected = hooks.where((h) => h.kind == kind).toList()
      ..sort((a, b) {
        final order = a.glue.order.compareTo(b.glue.order);
        return order != 0 ? order : a.index.compareTo(b.index);
      });
    return List.unmodifiable(kind.isAfter ? selected.reversed : selected);
  }
}

final class _Loader<W extends Object> {
  _Loader(this.glue, this.ids);

  final List<Glue> glue;
  final IdScheme ids;
  final TypeWitness<W> world = TypeWitness<W>();
  final ParameterTypes parameterTypes = ParameterTypes();
  final List<GlueError> errors = [];
  final Map<ParameterType<Object?>, ParameterTypeDefinition> defined = {};
  final List<DataTableTypeSpec<Object?>> tableTypes = [];
  final List<DocStringTypeSpec<Object?>> docStringTypes = [];

  void _error(Glue value, String message) =>
      errors.add(GlueError('$value: $message', source: value.source));

  String _key(Glue value, String pattern) =>
      '${value.source ?? ''}|${value.runtimeType}|$pattern';

  SupportCodeLibrary load() {
    // Types first, so steps can use parameter types defined after them.
    for (final value in glue) {
      switch (value) {
        case ParameterType<Object?>():
          _defineParameterType(value);
        case DataTableType<Object?>():
          _defineTableType(value);
        case DocStringType<Object?>():
          _defineDocStringType(value);
        case StepGlue() || HookGlue():
          break;
      }
    }

    final envelopes = <messages.Envelope>[];
    final userTypes = <UserParameterType>[];
    final steps = <StepDefinition>[];
    final hooks = <HookDefinition>[];
    final undefined = <messages.UndefinedParameterType>[];
    for (var index = 0; index < glue.length; index++) {
      final value = glue[index];
      switch (value) {
        case ParameterType<Object?>():
          final definition = defined[value];
          if (definition == null) continue;
          final type = UserParameterType(
            id: ids.forGlue(index, _key(value, value.name)),
            glue: value,
            definition: definition,
          );
          userTypes.add(type);
          envelopes.add(messages.Envelope(parameterType: type.toMessage()));
        case StepGlue():
          final step = _loadStep(value, index, undefined, envelopes);
          if (step != null) {
            steps.add(step);
            envelopes.add(messages.Envelope(stepDefinition: step.toMessage()));
          }
        case HookGlue():
          final hook = _loadHook(value, index);
          if (hook != null) {
            hooks.add(hook);
            envelopes.add(messages.Envelope(hook: hook.toMessage()));
          }
        case DataTableType<Object?>() || DocStringType<Object?>():
          break;
      }
    }

    if (errors.isNotEmpty) throw GlueException(errors);

    return SupportCodeLibrary._(
      worldType: world,
      worldTypeName: world.isUntyped || W == DefaultWorld || W == World
          ? null
          : '$W',
      parameterTypes: parameterTypes,
      userParameterTypes: List.unmodifiable(userTypes),
      stepDefinitions: List.unmodifiable(steps),
      hooks: hooks,
      converter: TableConverter(
        tableTypes: tableTypes,
        docStringTypes: docStringTypes,
      ),
      envelopes: List.unmodifiable(envelopes),
      undefinedParameterTypes: List.unmodifiable(undefined),
    );
  }

  // -------------------------------------------------------------------------
  // Parameter, data table and doc string types
  // -------------------------------------------------------------------------

  void _defineParameterType(ParameterType<Object?> value) {
    final regexps = <Object>[];
    final raw = value.regexp;
    for (final r in raw is List ? raw : [raw]) {
      if (r is String || r is RegExp) {
        regexps.add(r as Object);
      } else {
        _error(value, 'regexp must be a String, a RegExp or a List of them.');
        return;
      }
    }
    if (regexps.isEmpty) {
      _error(value, 'regexp must not be empty.');
      return;
    }
    final patterns = [
      for (final r in regexps) r is RegExp ? r.pattern : r as String,
    ];

    // One String per capture group, or one String when there are none.
    var groups = 0;
    for (final pattern in patterns) {
      try {
        groups += TreeRegexp(RegExp(pattern)).root.children.length;
      } on FormatException catch (e) {
        _error(value, 'invalid regexp /$pattern/: ${e.message}');
        return;
      }
    }
    final expected = groups == 0 ? 1 : groups;
    final transformer = value.transformer;
    final arity = minimumArity(transformer);
    final bool takesWorld;
    if (arity == expected) {
      takesWorld = false;
    } else if (arity == expected + 1) {
      takesWorld = true;
      if (!world.acceptedAt(transformer, 0, arity!)) {
        _error(
          value,
          'the transformer takes ${expected + 1} parameters, so its first '
          'parameter must accept the World ($W).',
        );
        return;
      }
    } else {
      _error(
        value,
        'the transformer must take $expected String parameter'
        '${expected == 1 ? '' : 's'} (one per capture group), optionally '
        'preceded by the World, but it takes '
        '${arity ?? 'more than $maxArity or named'} parameters.',
      );
      return;
    }
    final offset = takesWorld ? 1 : 0;
    for (var i = 0; i < expected; i++) {
      if (!acceptsAt<String>(transformer, i + offset, arity!)) {
        _error(
          value,
          'transformer parameter ${i + offset + 1} must accept a String.',
        );
        return;
      }
    }

    final witness = value.witness;
    final definition = ParameterTypeDefinition(
      name: value.name,
      regexps: patterns,
      typeName: witness.isUntyped ? 'Object?' : '${witness.type}',
      witness: witness,
      transform: (values, worldValue) {
        final arguments = takesWorld ? [worldValue, ...values] : values;
        return Function.apply(transformer, arguments) as FutureOr<Object?>;
      },
      useForSnippets: value.useForSnippets,
      preferForRegexpMatch: value.preferForRegexpMatch,
      source: value.source,
    );
    try {
      parameterTypes.define(definition, regexps);
      defined[value] = definition;
    } on ce.CucumberExpressionException catch (e) {
      _error(value, e.message);
    }
  }

  void _defineTableType(DataTableType<Object?> value) {
    final spec = value.spec;
    bool conflicts(DataTableTypeSpec<Object?> other) {
      if (other.type != spec.type) return false;
      return switch ((spec, other)) {
        (EntryTypeSpec() || RowTypeSpec(), EntryTypeSpec() || RowTypeSpec()) =>
          true,
        (CellTypeSpec(), CellTypeSpec()) => true,
        (TableTypeSpec(), TableTypeSpec()) => true,
        _ => false,
      };
    }

    if (tableTypes.any(conflicts)) {
      _error(
        value,
        'there is already a data table type that converts to ${spec.type} '
        'this way.',
      );
      return;
    }
    tableTypes.add(spec);
  }

  void _defineDocStringType(DocStringType<Object?> value) {
    final spec = value.spec;
    if (docStringTypes.any(
      (t) => t.type == spec.type && t.contentType == spec.contentType,
    )) {
      _error(
        value,
        'there is already a doc string type for ${spec.type} and content type '
        '"${spec.contentType ?? '(any)'}".',
      );
      return;
    }
    docStringTypes.add(spec);
  }

  // -------------------------------------------------------------------------
  // Steps
  // -------------------------------------------------------------------------

  StepDefinition? _loadStep(
    StepGlue value,
    int index,
    List<messages.UndefinedParameterType> undefined,
    List<messages.Envelope> envelopes,
  ) {
    final expression = value.expression;
    if (expression is! String && expression is! RegExp) {
      _error(value, 'the expression must be a String or a RegExp.');
      return null;
    }
    final StepExpression compiled;
    try {
      compiled = parameterTypes.compile(expression);
    } on ce.UndefinedParameterTypeException catch (e) {
      // Not a glue error: steps using this definition become UNDEFINED.
      final message = messages.UndefinedParameterType(
        expression: expression is RegExp ? expression.pattern : '$expression',
        name: e.undefinedParameterTypeName,
      );
      undefined.add(message);
      envelopes.add(messages.Envelope(undefinedParameterType: message));
      return null;
    } on ce.CucumberExpressionException catch (e) {
      _error(value, e.message);
      return null;
    } on FormatException catch (e) {
      _error(value, 'invalid regular expression: ${e.message}');
      return null;
    }

    final body = value.body;
    final arity = minimumArity(body);
    final n = compiled.parameterTypes.length;
    if (arity == null || arity < n || arity > n + 3) {
      _error(
        value,
        'the body must take the $n expression argument'
        '${n == 1 ? '' : 's'}, optionally preceded by the World and followed '
        'by up to two multiline arguments (a data table and/or doc string), '
        'but it takes ${arity ?? 'more than $maxArity or named'} parameters.',
      );
      return null;
    }

    final layouts = <StepLayout>[];
    for (final takesWorld in [false, true]) {
      final m = arity - n - (takesWorld ? 1 : 0);
      if (m < 0 || m > 2) continue;
      layouts.add(
        StepLayout(
          world: takesWorld,
          multilineCount: m,
          problem: _checkStepTypes(
            compiled.parameterTypes,
            body,
            arity,
            takesWorld,
          ),
        ),
      );
    }
    if (layouts.every((l) => l.problem != null)) {
      _error(value, layouts.map((l) => l.problem).join('\nor '));
      return null;
    }

    return StepDefinition(
      id: ids.forGlue(index, _key(value, compiled.patternSource)),
      glue: value,
      expression: compiled,
      arity: arity,
      layouts: List.unmodifiable(layouts),
    );
  }

  String? _checkStepTypes(
    List<ParameterTypeDefinition?> types,
    Function body,
    int arity,
    bool takesWorld,
  ) {
    if (takesWorld && !world.acceptedAt(body, 0, arity)) {
      return 'parameter 1 must accept the World ($W)';
    }
    final offset = takesWorld ? 1 : 0;
    for (var i = 0; i < types.length; i++) {
      final type = types[i];
      final witness = type?.witness ?? const TypeWitness<String>();
      if (!witness.acceptedAt(body, i + offset, arity)) {
        final name = type == null
            ? 'regular expression group'
            : '{${type.name}}';
        return 'parameter ${i + offset + 1} must accept $witness (the type of '
            '$name ${i + 1})';
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Hooks
  // -------------------------------------------------------------------------

  HookDefinition? _loadHook(HookGlue value, int index) {
    TagExpression? tagExpression;
    final tags = value.tags;
    if (tags != null) {
      try {
        tagExpression = TagExpression.parse(tags);
      } on TagExpressionException catch (e) {
        _error(value, e.message);
        return null;
      }
    }
    final layout = _hookLayout(value);
    if (layout == null) return null;
    return HookDefinition(
      id: ids.forGlue(index, _key(value, value.tags ?? '')),
      glue: value,
      index: index,
      layout: layout,
      tagExpression: tagExpression,
    );
  }

  HookLayout? _hookLayout(HookGlue value) {
    final body = value.body;
    final arity = minimumArity(body);
    final (TypeWitness<Object> context, String accepted) = switch (value.kind) {
      HookKind.before || HookKind.after => (
        const TypeWitness<Scenario>(),
        '(), (World), (Scenario) or (World, Scenario)',
      ),
      HookKind.beforeStep || HookKind.afterStep => (
        const TypeWitness<Step>(),
        '(), (World), (Step) or (World, Step)',
      ),
      HookKind.beforeAll ||
      HookKind.afterAll => (const TypeWitness<TestRun>(), '() or (TestRun)'),
    };
    HookLayout? fail() {
      _error(
        value,
        'the body must be one of $accepted, but it takes '
        '${arity ?? 'more than $maxArity or named'} parameters'
        '${arity == null || arity == 0 ? '' : ' of other types'}.',
      );
      return null;
    }

    if (arity == 0) return HookLayout.none;
    if (arity == 1) {
      final acceptsContext = context.strictlyAcceptedAt(body, 0, 1);
      if (value.kind.isTestRun) {
        return acceptsContext ? HookLayout.context : fail();
      }
      final acceptsWorld = world.strictlyAcceptedAt(body, 0, 1);
      if (acceptsWorld) return HookLayout.world;
      if (acceptsContext) return HookLayout.context;
      if (world.isUntyped) return HookLayout.world;
      return fail();
    }
    if (arity == 2 &&
        !value.kind.isTestRun &&
        world.acceptedAt(body, 0, 2) &&
        context.strictlyAcceptedAt(body, 1, 2)) {
      return HookLayout.worldAndContext;
    }
    return fail();
  }
}
