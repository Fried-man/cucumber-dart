import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The ancestors of an element of a Gherkin document, such as a scenario, an
/// examples table or an example row, and so of the pickles made from it.
///
/// Fields that do not apply are `null`: a scenario outside a rule has no
/// [rule], and only an example row has an [example].
final class Lineage {
  /// Creates a lineage.
  const Lineage({
    this.gherkinDocument,
    this.feature,
    this.background,
    this.rule,
    this.ruleBackground,
    this.scenario,
    this.examples,
    this.examplesIndex,
    this.example,
    this.exampleIndex,
  });

  /// The document.
  final messages.GherkinDocument? gherkinDocument;

  /// The feature of the document.
  final messages.Feature? feature;

  /// The background of the feature.
  final messages.Background? background;

  /// The rule that contains the element.
  final messages.Rule? rule;

  /// The background of the [rule].
  final messages.Background? ruleBackground;

  /// The scenario or scenario outline.
  final messages.Scenario? scenario;

  /// The examples table of a scenario outline.
  final messages.Examples? examples;

  /// The index of [examples] among the examples of the [scenario].
  final int? examplesIndex;

  /// The example: a row of the body of [examples].
  final messages.TableRow? example;

  /// The index of [example] in the body of [examples].
  final int? exampleIndex;

  @override
  bool operator ==(Object other) =>
      other is Lineage &&
      gherkinDocument == other.gherkinDocument &&
      feature == other.feature &&
      background == other.background &&
      rule == other.rule &&
      ruleBackground == other.ruleBackground &&
      scenario == other.scenario &&
      examples == other.examples &&
      examplesIndex == other.examplesIndex &&
      example == other.example &&
      exampleIndex == other.exampleIndex;

  @override
  int get hashCode => Object.hash(
    gherkinDocument,
    feature,
    background,
    rule,
    ruleBackground,
    scenario,
    examples,
    examplesIndex,
    example,
    exampleIndex,
  );

  @override
  String toString() {
    final names = [
      if (feature case final feature?) 'feature: ${feature.name}',
      if (rule case final rule?) 'rule: ${rule.name}',
      if (scenario case final scenario?) 'scenario: ${scenario.name}',
      if (examples case final examples?)
        'examples[$examplesIndex]: ${examples.name}',
      if (example != null) 'example[$exampleIndex]',
    ];
    return 'Lineage(${names.join(', ')})';
  }
}

/// Reduces the [Lineage] of an element of a Gherkin document, and optionally
/// a pickle made from it, to a value.
abstract interface class LineageReducer<T> {
  /// Reduces [lineage] and, when given, the [pickle] made from it.
  T reduce(Lineage lineage, [messages.Pickle? pickle]);
}

/// Names pickles and other elements of a Gherkin document.
typedef NamingStrategy = LineageReducer<String>;

/// Whether a name includes the names of all ancestors.
enum NamingStrategyLength {
  /// Includes the names of all ancestors, joined with ` - `.
  long,

  /// Only the name of the element itself.
  short,
}

/// Whether a [NamingStrategyLength.long] name includes the feature name.
enum NamingStrategyFeatureName {
  /// Includes the feature name.
  include,

  /// Leaves the feature name out.
  exclude,
}

/// How a pickle made from an example row is named.
enum NamingStrategyExampleName {
  /// By the number of the example, such as `#1.2` for the second row of the
  /// first examples table.
  number,

  /// By the name of the pickle, such as `Eating 6 cucumbers`.
  pickle,

  /// By the number of the example and, when the scenario outline name has
  /// parameters, the name of the pickle, such as `#1.2: Eating 6 cucumbers`.
  numberAndPickleIfParameterized,
}

/// Creates a built-in [NamingStrategy].
///
/// For the scenario outline `Eating <eat> cucumbers` of the feature
/// `Examples Tables`, with the examples table `These are passing`, the
/// pickle of the second example row is named:
///
/// ```text
/// Examples Tables - Eating <eat> cucumbers - These are passing - #1.2: Eating 6 cucumbers
/// ```
///
/// by the default long strategy, and `Eating 6 cucumbers` by the short
/// strategy with [NamingStrategyExampleName.pickle].
NamingStrategy namingStrategy(
  NamingStrategyLength length, {
  NamingStrategyFeatureName featureName = NamingStrategyFeatureName.include,
  NamingStrategyExampleName exampleName =
      NamingStrategyExampleName.numberAndPickleIfParameterized,
}) => _BuiltinNamingStrategy(length, featureName, exampleName);

final class _BuiltinNamingStrategy implements NamingStrategy {
  const _BuiltinNamingStrategy(this.length, this.featureName, this.exampleName);

  final NamingStrategyLength length;
  final NamingStrategyFeatureName featureName;
  final NamingStrategyExampleName exampleName;

  @override
  String reduce(Lineage lineage, [messages.Pickle? pickle]) {
    final parts = <String>[];
    if (lineage.feature case final feature?
        when featureName == NamingStrategyFeatureName.include ||
            length == NamingStrategyLength.short) {
      parts.add(feature.name);
    }
    if (lineage.rule case final rule?) {
      parts.add(rule.name);
    }
    final scenarioName = lineage.scenario?.name;
    if (scenarioName != null) {
      parts.add(scenarioName);
    }
    if (lineage.examples case final examples?) {
      parts.add(examples.name);
    }
    final isExample = lineage.example != null;
    if (isExample) {
      parts.add(
        '#${(lineage.examplesIndex ?? 0) + 1}.${(lineage.exampleIndex ?? 0) + 1}',
      );
    }

    if (pickle != null) {
      if (scenarioName == null) {
        parts.add(pickle.name);
      } else if (isExample) {
        switch (exampleName) {
          case NamingStrategyExampleName.number:
            break;
          case NamingStrategyExampleName.numberAndPickleIfParameterized:
            if (scenarioName != pickle.name) {
              parts.add('${parts.removeLast()}: ${pickle.name}');
            }
          case NamingStrategyExampleName.pickle:
            parts
              ..removeLast()
              ..add(pickle.name);
        }
      }
    }

    if (length == NamingStrategyLength.short) {
      return parts.isEmpty ? '' : parts.last;
    }
    return parts.where((part) => part.isNotEmpty).join(' - ');
  }
}
