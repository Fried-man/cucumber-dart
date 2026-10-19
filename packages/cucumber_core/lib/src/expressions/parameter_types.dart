import 'dart:async';

import 'package:cucumber_expressions/cucumber_expressions.dart' as ce;

import '../glue/function_shapes.g.dart';
import '../source_reference.dart';
import 'step_expression.dart';
import 'tree_regexp.dart';

/// Captures a type argument so that function shapes and values can be checked
/// against it at run time.
final class TypeWitness<T> {
  /// Creates a witness for [T].
  const TypeWitness();

  /// The captured type.
  Type get type => T;

  /// Whether `T` is nullable.
  bool get isNullable => null is T;

  /// Whether `T` is `dynamic`, `Object` or `Object?`, in which case nothing
  /// is known about the values.
  bool get isUntyped => <Object>[] is List<T>;

  /// Whether parameter [index] of [f], called with [arity] arguments, accepts
  /// a `T`. Always true when `T` [isUntyped], since the values could be of any
  /// type.
  bool acceptedAt(Function f, int index, int arity) =>
      isUntyped || acceptsAt<T>(f, index, arity);

  /// Like [acceptedAt], but without the exception for untyped `T`.
  bool strictlyAcceptedAt(Function f, int index, int arity) =>
      acceptsAt<T>(f, index, arity);

  /// Whether [value] is a `T`.
  bool accepts(Object? value) => value is T;

  @override
  String toString() => '$T';
}

/// Transforms the group values of a matched parameter into an argument.
///
/// [world] is the current World; built-in transformers ignore it.
typedef ArgumentTransformer =
    FutureOr<Object?> Function(List<String?> values, Object world);

/// A parameter type known to the engine: a built-in one or one defined by a
/// `ParameterType` glue value.
final class ParameterTypeDefinition {
  /// Creates a definition.
  ParameterTypeDefinition({
    required this.name,
    required this.regexps,
    required this.typeName,
    required this.witness,
    required this.transform,
    this.useForSnippets = true,
    this.preferForRegexpMatch = false,
    this.isBuiltIn = false,
    this.id,
    this.source,
  });

  /// The name used in Cucumber Expressions (`''` for the anonymous type).
  final String name;

  /// The regular expressions, as pattern strings.
  final List<String> regexps;

  /// The Dart type name used in snippets.
  final String typeName;

  /// The type produced by [transform].
  final TypeWitness<Object?> witness;

  /// Turns group values into the argument value.
  final ArgumentTransformer transform;

  /// Whether snippets may use this type.
  final bool useForSnippets;

  /// Whether this type wins when several match a regular expression group.
  final bool preferForRegexpMatch;

  /// Whether this is one of the built-in types.
  final bool isBuiltIn;

  /// The message ID, for user-defined types.
  final String? id;

  /// Where the glue value was defined, for user-defined types.
  final SourceReference? source;
}

int? _toInt(List<String?> values) {
  final v = values.first;
  return v == null ? null : int.parse(v);
}

double? _toDouble(List<String?> values) {
  final v = values.first;
  return v == null ? null : double.parse(v);
}

BigInt? _toBigInt(List<String?> values) {
  final v = values.first;
  return v == null ? null : BigInt.parse(v);
}

String? _toStringValue(List<String?> values) => values.first;

String? _unquote(List<String?> values) {
  if (values.every((v) => v == null)) return null;
  final s1 = values.isNotEmpty ? values[0] : null;
  final s2 = values.length > 1 ? values[1] : null;
  return (s1 ?? s2 ?? '').replaceAll(r'\"', '"').replaceAll(r"\'", "'");
}

const List<String> _integerRegexps = [r'-?\d+', r'\d+'];
const String _floatRegexp = r'[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:[E][+-]?\d+)?';
const String _stringRegexp =
    r'"([^"\\]*(\\.[^"\\]*)*)"'
    r"|'([^'\\]*(\\.[^'\\]*)*)'";

ParameterTypeDefinition _builtIn<T>(
  String name,
  Object regexps,
  String typeName,
  Object? Function(List<String?>) transform, {
  bool useForSnippets = false,
  bool preferForRegexpMatch = false,
}) => ParameterTypeDefinition(
  name: name,
  regexps: regexps is List<String> ? regexps : [regexps as String],
  typeName: typeName,
  witness: TypeWitness<T>(),
  transform: (values, _) => transform(values),
  useForSnippets: useForSnippets,
  preferForRegexpMatch: preferForRegexpMatch,
  isBuiltIn: true,
);

/// The built-in parameter types, with non-nullable Dart types (design §11.2).
///
/// They mirror the types `package:cucumber_expressions` registers, which are
/// declared nullable there.
final List<ParameterTypeDefinition> builtInParameterTypes = [
  _builtIn<int>(
    'int',
    _integerRegexps,
    'int',
    _toInt,
    useForSnippets: true,
    preferForRegexpMatch: true,
  ),
  _builtIn<double>(
    'float',
    _floatRegexp,
    'double',
    _toDouble,
    useForSnippets: true,
  ),
  _builtIn<String>('word', r'[^\s]+', 'String', _toStringValue),
  _builtIn<String>(
    'string',
    _stringRegexp,
    'String',
    _unquote,
    useForSnippets: true,
  ),
  _builtIn<String>(
    '',
    '.*',
    'String',
    _toStringValue,
    preferForRegexpMatch: true,
  ),
  _builtIn<double>('double', _floatRegexp, 'double', _toDouble),
  _builtIn<String>('bigdecimal', _floatRegexp, 'String', _toStringValue),
  _builtIn<int>('byte', _integerRegexps, 'int', _toInt),
  _builtIn<int>('short', _integerRegexps, 'int', _toInt),
  _builtIn<int>('long', _integerRegexps, 'int', _toInt),
  _builtIn<BigInt>('biginteger', _integerRegexps, 'BigInt', _toBigInt),
];

int _compare(ParameterTypeDefinition a, ParameterTypeDefinition b) {
  if (a.preferForRegexpMatch && !b.preferForRegexpMatch) return -1;
  if (b.preferForRegexpMatch && !a.preferForRegexpMatch) return 1;
  return a.name.compareTo(b.name);
}

/// The parameter types of a suite, and the compiler of step expressions.
///
/// It keeps a `package:cucumber_expressions` registry in sync, in which every
/// type is registered with an identity transformer: the engine calls the
/// user's transformers itself, with the World available (ADR-0015).
final class ParameterTypes {
  /// Creates a registry holding the built-in types.
  ParameterTypes() {
    for (final type in builtInParameterTypes) {
      _index(type);
    }
  }

  /// The `package:cucumber_expressions` registry, used for parsing and for
  /// generating snippet expressions.
  final ce.ParameterTypeRegistry expressionRegistry =
      ce.ParameterTypeRegistry();

  final Map<String, ParameterTypeDefinition> _byName = {};
  final Map<String, List<ParameterTypeDefinition>> _byRegexp = {};

  /// Every parameter type, built-in ones first.
  Iterable<ParameterTypeDefinition> get all => _byName.values;

  /// The parameter type called [name], if any.
  ParameterTypeDefinition? byName(String name) => _byName[name];

  /// Defines a user parameter type.
  ///
  /// [regexps] are the original regular expressions (strings or `RegExp`s),
  /// which are validated by `package:cucumber_expressions`.
  ///
  /// Throws a [ce.CucumberExpressionException] for invalid names, duplicate
  /// names and conflicting preferential types.
  void define(ParameterTypeDefinition type, List<Object> regexps) {
    expressionRegistry.defineParameterType(
      ce.ParameterType<Object?>(
        type.name,
        regexps,
        type.typeName,
        (values) => values,
        useForSnippets: type.useForSnippets,
        preferForRegexpMatch: type.preferForRegexpMatch,
      ),
    );
    _index(type);
  }

  void _index(ParameterTypeDefinition type) {
    _byName[type.name] = type;
    for (final regexp in type.regexps) {
      (_byRegexp[regexp] ??= []).add(type);
      _byRegexp[regexp]!.sort(_compare);
    }
  }

  /// The parameter type whose regular expression is exactly [regexp], used to
  /// type a capture group of a regular expression step definition.
  ///
  /// Throws a [ce.AmbiguousParameterTypeException] when several types match and
  /// none is preferential.
  ParameterTypeDefinition? byRegexp(String regexp, RegExp expression) {
    final candidates = _byRegexp[regexp];
    if (candidates == null || candidates.isEmpty) return null;
    if (candidates.length > 1 && !candidates.first.preferForRegexpMatch) {
      throw ce.AmbiguousParameterTypeException(
        'Your Regular Expression /${expression.pattern}/\n'
        'matches multiple parameter types with regexp $regexp:\n'
        '   ${candidates.map((p) => '{${p.name}}').join('\n   ')}\n'
        '\n'
        "I couldn't decide which one to use. You have two options:\n"
        '\n'
        '1) Use a Cucumber Expression instead of a Regular Expression.\n'
        '\n'
        '2) Make one of the parameter types preferential and continue to use '
        'a Regular Expression.\n',
      );
    }
    return candidates.first;
  }

  /// Compiles a step [expression]: a `String` Cucumber Expression or a
  /// `RegExp`.
  ///
  /// Throws a [ce.UndefinedParameterTypeException] for unknown parameter types,
  /// and other [ce.CucumberExpressionException]s for invalid expressions.
  StepExpression compile(Object expression) {
    final compiled = ce.ExpressionFactory(
      expressionRegistry,
    ).createExpression(expression);
    final tree = TreeRegexp(compiled.regexp);
    final List<ParameterTypeDefinition?> types;
    if (compiled is ce.CucumberExpression) {
      types = [
        for (final name in cucumberExpressionParameterNames(compiled.source))
          _byName[name]!,
      ];
    } else {
      types = [
        for (final group in tree.root.children)
          byRegexp(group.source, compiled.regexp),
      ];
    }
    if (types.length != tree.root.children.length) {
      throw ce.CucumberExpressionException(
        'Expression /${compiled.source}/ has ${tree.root.children.length} '
        'capture groups but ${types.length} parameter types',
      );
    }
    return StepExpression(expression, compiled, tree, types);
  }
}

/// The parameter type names referenced by a Cucumber Expression, in order.
///
/// The expression must already be valid.
List<String> cucumberExpressionParameterNames(String expression) {
  final names = <String>[];
  var i = 0;
  while (i < expression.length) {
    final c = expression[i];
    if (c == r'\') {
      i += 2;
    } else if (c == '{') {
      final end = expression.indexOf('}', i);
      if (end < 0) break;
      names.add(expression.substring(i + 1, end));
      i = end + 1;
    } else {
      i++;
    }
  }
  return names;
}
