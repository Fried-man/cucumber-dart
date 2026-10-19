import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// Where a scenario sits in its document.
final class ScenarioLocation {
  ScenarioLocation._(this.feature, this.rule, this.scenario);

  /// The feature.
  final messages.Feature feature;

  /// The rule, if the scenario is inside one.
  final messages.Rule? rule;

  /// The scenario or scenario outline.
  final messages.Scenario scenario;
}

/// Where an example row sits in its document.
final class ExampleRowLocation {
  ExampleRowLocation._(
    this.examples,
    this.examplesIndex,
    this.row,
    this.rowIndex,
  );

  /// The `Examples` section.
  final messages.Examples examples;

  /// The 0-based index of [examples] in its scenario outline.
  final int examplesIndex;

  /// The row.
  final messages.TableRow row;

  /// The 0-based index of [row] in the examples' body.
  final int rowIndex;
}

/// An index of the AST nodes of a Gherkin document, by ID.
final class GherkinIndex {
  /// Indexes [document].
  GherkinIndex(this.document) {
    final feature = document.feature;
    if (feature == null) return;
    for (final child in feature.children) {
      if (child.background case final background?) {
        _steps(background.steps);
      }
      if (child.scenario case final scenario?) {
        _scenario(feature, null, scenario);
      }
      if (child.rule case final rule?) {
        for (final ruleChild in rule.children) {
          if (ruleChild.background case final background?) {
            _steps(background.steps);
          }
          if (ruleChild.scenario case final scenario?) {
            _scenario(feature, rule, scenario);
          }
        }
      }
    }
  }

  /// The indexed document.
  final messages.GherkinDocument document;

  final Map<String, ScenarioLocation> _scenarios = {};
  final Map<String, messages.Step> _stepsById = {};
  final Map<String, ExampleRowLocation> _rows = {};

  void _steps(List<messages.Step> steps) {
    for (final step in steps) {
      _stepsById[step.id] = step;
    }
  }

  void _scenario(
    messages.Feature feature,
    messages.Rule? rule,
    messages.Scenario scenario,
  ) {
    _scenarios[scenario.id] = ScenarioLocation._(feature, rule, scenario);
    _steps(scenario.steps);
    for (var e = 0; e < scenario.examples.length; e++) {
      final examples = scenario.examples[e];
      for (var r = 0; r < examples.tableBody.length; r++) {
        final row = examples.tableBody[r];
        _rows[row.id] = ExampleRowLocation._(examples, e, row, r);
      }
    }
  }

  /// The feature, if the document has one.
  messages.Feature? get feature => document.feature;

  /// The scenario a pickle was compiled from.
  ScenarioLocation? scenarioOf(messages.Pickle pickle) {
    for (final id in pickle.astNodeIds) {
      final location = _scenarios[id];
      if (location != null) return location;
    }
    return null;
  }

  /// The example row a pickle was compiled from, for scenario outlines.
  ExampleRowLocation? exampleRowOf(messages.Pickle pickle) {
    for (final id in pickle.astNodeIds.reversed) {
      final location = _rows[id];
      if (location != null) return location;
    }
    return null;
  }

  /// The Gherkin step a pickle step was compiled from.
  messages.Step? stepOf(messages.PickleStep step) {
    for (final id in step.astNodeIds) {
      final gherkinStep = _stepsById[id];
      if (gherkinStep != null) return gherkinStep;
    }
    return null;
  }
}
