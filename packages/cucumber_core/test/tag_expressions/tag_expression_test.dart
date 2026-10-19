import 'dart:io';

import 'package:cucumber_core/src/tag_expressions/tag_expression.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

List<Map<Object?, Object?>> _load(String name) {
  final file = File('test/tag_expressions/testdata/$name');
  final yaml = loadYaml(file.readAsStringSync()) as YamlList;
  return [
    for (final entry in yaml) (entry as YamlMap).cast<Object?, Object?>(),
  ];
}

void main() {
  group('parsing.yml', () {
    for (final entry in _load('parsing.yml')) {
      final expression = entry['expression']! as String;
      final formatted = entry['formatted']! as String;
      test('"$expression" is formatted as "$formatted"', () {
        final parsed = TagExpression.parse(expression);
        expect(parsed.toString(), formatted);
        // The formatted form parses back to itself.
        expect(TagExpression.parse(formatted).toString(), formatted);
      });
    }
  });

  group('evaluations.yml', () {
    for (final entry in _load('evaluations.yml')) {
      final expression = entry['expression']! as String;
      final tests = entry['tests']! as YamlList;
      for (final t in tests.cast<YamlMap>()) {
        final variables = (t['variables'] as YamlList).cast<String>().toList();
        final result = t['result'] as bool;
        test('"$expression" with $variables is $result', () {
          expect(TagExpression.parse(expression).evaluate(variables), result);
        });
      }
    }
  });

  group('errors.yml', () {
    for (final entry in _load('errors.yml')) {
      final expression = entry['expression']! as String;
      final error = entry['error']! as String;
      test('"$expression" fails', () {
        expect(
          () => TagExpression.parse(expression),
          throwsA(
            isA<TagExpressionException>().having(
              (e) => e.message,
              'message',
              error,
            ),
          ),
        );
      });
    }
  });

  test('blank expressions match everything', () {
    expect(TagExpression.parse('   ').evaluate(const []), isTrue);
  });

  test('tags are matched with their @', () {
    final expression = TagExpression.parse('@fast and not @wip');
    expect(expression.evaluate(['@fast']), isTrue);
    expect(expression.evaluate(['@fast', '@wip']), isFalse);
    expect(expression.evaluate(['fast']), isFalse);
  });
}
