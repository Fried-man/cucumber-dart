// Generates the benchmark suite: deterministic feature files that the glue in
// glue.dart implements, so every scenario passes.
import 'dart:io';

import 'package:path/path.dart' as p;

import 'glue.dart';

/// The size of a generated suite.
final class SuiteShape {
  /// Creates a shape of [features] feature files with [scenarios] pickles
  /// each.
  const SuiteShape({required this.features, required this.scenarios})
    : assert(features > 0),
      assert(scenarios > 0);

  /// The number of feature files.
  final int features;

  /// The number of pickles per feature file: scenarios, plus (from 4) a rule
  /// with a scenario outline of 3 example rows.
  final int scenarios;

  /// The number of example rows per feature.
  int get outlineRows => scenarios >= 4 ? 3 : 0;

  @override
  String toString() =>
      '$features features × $scenarios scenarios ($outlineRows of them '
      'example rows)';
}

/// The features per subdirectory of the generated `features/`.
const int featuresPerDirectory = 50;

/// Writes the feature files of [shape] to [directory], replacing its contents.
///
void generateSuite(SuiteShape shape, String directory) {
  final root = Directory(directory);
  if (root.existsSync()) root.deleteSync(recursive: true);
  for (var f = 0; f < shape.features; f++) {
    final file = File(
      p.join(
        directory,
        'area_${(f ~/ featuresPerDirectory).toString().padLeft(2, '0')}',
        'warehouse_${f.toString().padLeft(4, '0')}.feature',
      ),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(featureText(f, shape));
  }
}

/// Writes a one-scenario suite to [directory], to measure the fixed cost of a
/// `dart test` run.
void generateBaseline(String directory) {
  final root = Directory(directory);
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);
  File(p.join(directory, 'baseline.feature')).writeAsStringSync('''
Feature: Baseline
  Scenario: one step
    Given the main warehouse 0 holds 1 crates
''');
}

/// The text of feature [f] of [shape].
String featureText(int f, SuiteShape shape) {
  final i = f % glueFamilies;
  final buffer = StringBuffer()
    ..writeln('@warehouse @area-${f ~/ featuresPerDirectory} @issue:$f')
    ..writeln('Feature: Warehouse $f')
    ..writeln('  Moving crates around warehouse $i.')
    ..writeln()
    ..writeln('  Background:')
    ..writeln('    Given the main warehouse $i holds 100 crates')
    ..writeln();
  final plain = shape.scenarios - shape.outlineRows;
  for (var s = 0; s < plain; s++) {
    final tags = [
      if (s % 3 == 0) '@smoke',
      if (s % 5 == 0) '@slow',
      if (s % 7 == 0) '@traced',
    ];
    if (tags.isNotEmpty) buffer.writeln('  ${tags.join(' ')}');
    buffer.writeln('  Scenario: warehouse $f, scenario $s');
    for (final line in _scenarioSteps(s % 4, i, s)) {
      buffer.writeln('    $line');
    }
    buffer.writeln();
  }
  if (shape.outlineRows > 0) {
    buffer
      ..writeln('  Rule: crates can be moved in bulk')
      ..writeln()
      ..writeln('    @slow')
      ..writeln('    Scenario Outline: moving <count> crates')
      ..writeln('      When I move <count> crates out of warehouse $i')
      ..writeln('      Then warehouse $i holds <left> crates')
      ..writeln()
      ..writeln('      Examples:')
      ..writeln('        | count | left |');
    for (var r = 0; r < shape.outlineRows; r++) {
      final count = 10 * (r + 1) + f % 10;
      buffer.writeln(
        '        | ${'$count'.padRight(5)} | ${'${100 - count}'.padRight(4)} |',
      );
    }
  }
  return buffer.toString();
}

List<String> _scenarioSteps(int kind, int i, int s) {
  switch (kind) {
    case 0:
      final a = 1 + s % 9;
      final b = 2 + s % 7;
      return [
        'When I move $a crates out of warehouse $i',
        'And I move $b crates out of warehouse $i',
        'Then warehouse $i holds ${100 - a - b} crates',
      ];
    case 1:
      final color = Color.values[s % Color.values.length].name;
      return [
        'Given shelf A${s % 10} of warehouse $i has ${s + 3} boxes',
        'When I paint warehouse $i $color',
        'And I move 1 crate out of warehouse $i',
        'Then warehouse $i holds 99 crates',
      ];
    case 2:
      return [
        'Given warehouse $i stocks:',
        '  | name    | count |',
        '  | bolts   | ${'${s + 1}'.padRight(5)} |',
        '  | nuts    | 4     |',
        '  | washers | 7     |',
        'Then the stock of warehouse $i weighs ${s + 12} kg',
      ];
    default:
      return [
        'When I move 5 crates out of warehouse $i',
        'Then the manifest of warehouse $i reads:',
        '  """text',
        '  Crates leaving warehouse $i: 5',
        '  Scenario $s',
        '  """',
      ];
  }
}
