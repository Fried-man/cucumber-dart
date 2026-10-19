import 'package:cucumber_core/src/expressions/parameter_types.dart';
import 'package:cucumber_expressions/cucumber_expressions.dart' as ce;
import 'package:test/test.dart';

void main() {
  test('finds parameter names, ignoring escapes', () {
    expect(cucumberExpressionParameterNames(r'I have {int} \{x} {} {word}s'), [
      'int',
      '',
      'word',
    ]);
  });

  test('compiles Cucumber Expressions with offsets for every argument', () {
    final expression = ParameterTypes().compile('I have {int} {string} cukes');
    final arguments = expression.match('I have 42 "red" cukes')!;
    expect(
      [for (final a in arguments) a.parameterType!.name],
      ['int', 'string'],
    );
    expect([for (final a in arguments) a.group.start], [7, 10]);
    expect(arguments[1].group.values, ['red', null]);
    expect(expression.match('I have many cukes'), isNull);
    expect(expression.isRegularExpression, isFalse);
  });

  test('built-in transformers return non-nullable values', () async {
    final types = ParameterTypes();
    Future<Object?> transform(String name, List<String?> values) async =>
        types.byName(name)!.transform(values, Object());
    expect(await transform('int', ['-3']), -3);
    expect(await transform('float', ['1.5']), 1.5);
    expect(await transform('biginteger', ['9']), BigInt.from(9));
    expect(await transform('string', [null, r"it\'s"]), "it's");
    expect(types.byName('int')!.witness.type, int);
  });

  test('reports undefined parameter types', () {
    expect(
      () => ParameterTypes().compile('{airport} is closed'),
      throwsA(
        isA<ce.UndefinedParameterTypeException>().having(
          (e) => e.undefinedParameterTypeName,
          'name',
          'airport',
        ),
      ),
    );
  });

  test('rejects regular expression groups matching several types', () {
    final types = ParameterTypes();
    expect(
      () => types.compile(
        RegExp(
          r'^('
          r'[-+]?(?:\d+(?:\.\d+)?|\.\d+)(?:[E][+-]?\d+)?'
          r')$',
        ),
      ),
      throwsA(isA<ce.AmbiguousParameterTypeException>()),
    );
  });
}
