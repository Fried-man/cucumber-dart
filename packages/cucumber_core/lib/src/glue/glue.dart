import 'package:meta/meta.dart';

import '../data/data_table.dart';
import '../data/table_converter.dart';
import '../expressions/parameter_types.dart';
import '../source_reference.dart';

/// A glue value: a step definition, hook, parameter type, data table type or
/// doc string type (design §4.2, ADR-0002).
///
/// Glue values are immutable and side-effect free. A suite receives them as an
/// ordered `List<Glue>`; that order is the definition order used for hooks and
/// messages. Each value records where it was constructed, which messages
/// report as its source reference.
sealed class Glue {
  Glue._() : source = SourceReference.capture();

  /// Where this value was constructed: the first stack frame outside the
  /// cucumber packages, when available.
  final SourceReference? source;
}

// ---------------------------------------------------------------------------
// Step definitions
// ---------------------------------------------------------------------------

/// A step definition: [Given], [When] or [Then].
///
/// As in every Cucumber implementation, the keyword does not affect matching.
sealed class StepGlue extends Glue {
  StepGlue._(this.expression, this.body, this.timeout) : super._();

  /// A Cucumber Expression (`String`) or a regular expression (`RegExp`).
  final Object expression;

  /// The step body. Its positional parameters are laid out as
  /// `[World] expressionArguments… [dataTable/docString…]` (design §4.5).
  final Function body;

  /// Fails the step with a `TimeoutException` if it runs longer than this.
  final Duration? timeout;

  /// The keyword this step was defined with.
  String get keyword;

  @override
  String toString() =>
      "$keyword(${expression is RegExp ? '/${(expression as RegExp).pattern}/' : "'$expression'"})";
}

/// Defines a step that sets up context.
///
/// ```dart
/// Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) {
///   w.belly.eat(cukes);
/// }),
/// ```
final class Given extends StepGlue {
  /// Defines a step matching [expression] that runs [body].
  Given(Object expression, Function body, {Duration? timeout})
    : super._(expression, body, timeout);

  @override
  String get keyword => 'Given';
}

/// Defines a step that performs an action.
final class When extends StepGlue {
  /// Defines a step matching [expression] that runs [body].
  When(Object expression, Function body, {Duration? timeout})
    : super._(expression, body, timeout);

  @override
  String get keyword => 'When';
}

/// Defines a step that checks an outcome.
final class Then extends StepGlue {
  /// Defines a step matching [expression] that runs [body].
  Then(Object expression, Function body, {Duration? timeout})
    : super._(expression, body, timeout);

  @override
  String get keyword => 'Then';
}

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------

/// The kinds of hooks.
enum HookKind {
  /// Runs before each scenario.
  before,

  /// Runs after each scenario.
  after,

  /// Runs before each step.
  beforeStep,

  /// Runs after each step.
  afterStep,

  /// Runs once before all scenarios.
  beforeAll,

  /// Runs once after all scenarios.
  afterAll;

  /// Whether hooks of this kind run in descending order (ADR-0014).
  bool get isAfter => this == after || this == afterStep || this == afterAll;

  /// Whether this is a test-run hook.
  bool get isTestRun => this == beforeAll || this == afterAll;

  /// Whether this is a step hook.
  bool get isStep => this == beforeStep || this == afterStep;
}

/// A hook: [Before], [After], [BeforeStep], [AfterStep], [BeforeAll] or
/// [AfterAll].
///
/// Hooks are stably sorted by `(order, definition index)`; before-hooks run in
/// ascending order and after-hooks in descending order (ADR-0014).
sealed class HookGlue extends Glue {
  HookGlue._(this.body, this.tags, this.name, this.order, this.timeout)
    : super._();

  /// The hook body.
  final Function body;

  /// A tag expression selecting the scenarios this hook runs for, or `null`
  /// for all.
  final String? tags;

  /// A name, reported as `Hook.name` in messages.
  final String? name;

  /// The position relative to other hooks of the same kind.
  final int order;

  /// Fails the hook with a `TimeoutException` if it runs longer than this.
  final Duration? timeout;

  /// The kind of hook.
  HookKind get kind;

  @override
  String toString() =>
      '${switch (kind) {
        HookKind.before => 'Before',
        HookKind.after => 'After',
        HookKind.beforeStep => 'BeforeStep',
        HookKind.afterStep => 'AfterStep',
        HookKind.beforeAll => 'BeforeAll',
        HookKind.afterAll => 'AfterAll',
      }}(${name ?? ''})';
}

/// Runs before each scenario whose tags match [tags].
///
/// Accepted bodies: `()`, `(W world)`, `(Scenario scenario)` and
/// `(W world, Scenario scenario)`.
final class Before extends HookGlue {
  /// Defines a hook running [body].
  Before(
    Function body, {
    String? tags,
    String? name,
    int order = 0,
    Duration? timeout,
  }) : super._(body, tags, name, order, timeout);

  @override
  HookKind get kind => HookKind.before;
}

/// Runs after each scenario whose tags match [tags], even when it failed.
///
/// Accepted bodies: `()`, `(W world)`, `(Scenario scenario)` and
/// `(W world, Scenario scenario)`.
final class After extends HookGlue {
  /// Defines a hook running [body].
  After(
    Function body, {
    String? tags,
    String? name,
    int order = 0,
    Duration? timeout,
  }) : super._(body, tags, name, order, timeout);

  @override
  HookKind get kind => HookKind.after;
}

/// Runs before each step of the scenarios whose tags match [tags].
///
/// Accepted bodies: `()`, `(W world)`, `(Step step)` and
/// `(W world, Step step)`.
final class BeforeStep extends HookGlue {
  /// Defines a hook running [body].
  BeforeStep(
    Function body, {
    String? tags,
    String? name,
    int order = 0,
    Duration? timeout,
  }) : super._(body, tags, name, order, timeout);

  @override
  HookKind get kind => HookKind.beforeStep;
}

/// Runs after each step of the scenarios whose tags match [tags].
///
/// Accepted bodies: `()`, `(W world)`, `(Step step)` and
/// `(W world, Step step)`.
final class AfterStep extends HookGlue {
  /// Defines a hook running [body].
  AfterStep(
    Function body, {
    String? tags,
    String? name,
    int order = 0,
    Duration? timeout,
  }) : super._(body, tags, name, order, timeout);

  @override
  HookKind get kind => HookKind.afterStep;
}

/// Runs once before the first scenario.
///
/// Accepted bodies: `()` and `(TestRun run)`.
final class BeforeAll extends HookGlue {
  /// Defines a hook running [body].
  BeforeAll(Function body, {String? name, int order = 0, Duration? timeout})
    : super._(body, null, name, order, timeout);

  @override
  HookKind get kind => HookKind.beforeAll;
}

/// Runs once after the last scenario, even when scenarios or other hooks
/// failed.
///
/// Accepted bodies: `()` and `(TestRun run)`.
final class AfterAll extends HookGlue {
  /// Defines a hook running [body].
  AfterAll(Function body, {String? name, int order = 0, Duration? timeout})
    : super._(body, null, name, order, timeout);

  @override
  HookKind get kind => HookKind.afterAll;
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A parameter type for Cucumber Expressions (ADR-0015).
///
/// [transformer] takes one `String` parameter per capture group of [regexp]
/// (or a single `String` when it has none), optionally preceded by the World,
/// and returns a `T` or a `Future<T>`. Groups that do not participate in a
/// match are passed as `null`.
///
/// ```dart
/// ParameterType<Flight>('flight', r'([A-Z]{3})-([A-Z]{3})',
///     (String from, String to) => Flight(from, to)),
/// ```
final class ParameterType<T> extends Glue {
  /// Defines the parameter type `{name}`.
  ///
  /// [regexp] is a `String`, a `RegExp`, or a `List` of either. The `i` and
  /// `m` flags are rejected.
  ParameterType(
    this.name,
    this.regexp,
    this.transformer, {
    this.useForSnippets = true,
    this.preferForRegexpMatch = false,
  }) : super._();

  /// The name used in expressions, as in `{name}`.
  final String name;

  /// The regular expression(s) matching this type.
  final Object regexp;

  /// Turns the matched groups into a `T`.
  final Function transformer;

  /// Whether snippets may use this type.
  final bool useForSnippets;

  /// Whether this type wins when several match a regular expression group.
  final bool preferForRegexpMatch;

  /// A witness of `T`, used by the engine for type checks.
  @internal
  TypeWitness<T> get witness => TypeWitness<T>();

  @override
  String toString() => 'ParameterType<$T>($name)';
}

/// Converts data tables to `T` (design §4.6, ADR-0011).
///
/// A step parameter of type `List<T>`, `List<List<T>>` or `T` (depending on
/// the kind) receives the converted table.
final class DataTableType<T> extends Glue {
  /// Converts each data row, keyed by the header row, to a `T`; a step
  /// parameter `List<T>` receives one item per data row.
  ///
  /// Cells equal to [replaceWithEmptyString] become `''`.
  DataTableType.entry(
    T Function(Map<String, String> entry) transformer, {
    String? replaceWithEmptyString,
  }) : spec = EntryTypeSpec<T>(transformer, replaceWithEmptyString),
       super._();

  /// Converts each row to a `T`; a step parameter `List<T>` receives one item
  /// per row.
  DataTableType.row(
    T Function(List<String> row) transformer, {
    String? replaceWithEmptyString,
  }) : spec = RowTypeSpec<T>(transformer, replaceWithEmptyString),
       super._();

  /// Converts each cell to a `T`; step parameters `List<List<T>>` (and
  /// `List<T>` for single-column tables) receive the converted cells.
  DataTableType.cell(
    T Function(String cell) transformer, {
    String? replaceWithEmptyString,
  }) : spec = CellTypeSpec<T>(transformer, replaceWithEmptyString),
       super._();

  /// Converts the whole table to a `T`.
  DataTableType.table(T Function(DataTable table) transformer)
    : spec = TableTypeSpec<T>(transformer),
      super._();

  /// How tables are converted.
  @internal
  final DataTableTypeSpec<T> spec;

  /// A marker that converts to the empty string, such as `'[blank]'`.
  String? get replaceWithEmptyString => spec.replaceWithEmptyString;

  @override
  String toString() =>
      'DataTableType<$T>.${switch (spec) {
        EntryTypeSpec() => 'entry',
        RowTypeSpec() => 'row',
        CellTypeSpec() => 'cell',
        TableTypeSpec() => 'table',
      }}';
}

/// Converts doc strings to `T` (design §4.6, ADR-0011).
///
/// A step parameter of type `T` receives the converted doc string. When
/// several types produce the same `T`, the one whose [contentType] matches the
/// doc string's media type is used.
final class DocStringType<T> extends Glue {
  /// Defines a conversion of doc string content to `T`, for doc strings with
  /// [contentType] (any when `null`).
  DocStringType(T Function(String content) transformer, {String? contentType})
    : spec = DocStringTypeSpec<T>(transformer, contentType),
      super._();

  /// How doc strings are converted.
  @internal
  final DocStringTypeSpec<T> spec;

  /// The media type this conversion is for, or `null` for any.
  String? get contentType => spec.contentType;

  @override
  String toString() => 'DocStringType<$T>(${contentType ?? ''})';
}
