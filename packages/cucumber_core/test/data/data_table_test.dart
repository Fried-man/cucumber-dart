import 'dart:convert';

import 'package:cucumber_core/engine.dart';
import 'package:cucumber_core/src/data/table_converter.dart';
import 'package:test/test.dart';

import '../support.dart';

class Person {
  Person(this.name, this.age);
  final String name;
  final int? age;

  @override
  bool operator ==(Object other) =>
      other is Person && other.name == name && other.age == age;

  @override
  int get hashCode => Object.hash(name, age);

  @override
  String toString() => 'Person($name, $age)';
}

class Money {
  Money(this.cents);
  final int cents;

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;
}

class Matrix {
  Matrix(this.rows);
  final List<List<String>> rows;
}

DataTable table(List<List<String>> rows, [List<Glue> types = const []]) =>
    DataTable.withConverter(
      rows,
      TableConverter(
        tableTypes: [
          for (final t in types)
            if (t is DataTableType<Object?>) t.spec,
        ],
        docStringTypes: [
          for (final t in types)
            if (t is DocStringType<Object?>) t.spec,
        ],
      ),
    );

void main() {
  final people = [
    ['name', 'age'],
    ['Ada', '36'],
    ['Linus', ''],
  ];

  group('DataTable', () {
    test('exposes rows, columns and cells', () {
      final t = DataTable(people);
      expect(t.width, 2);
      expect(t.height, 3);
      expect(t.isEmpty, isFalse);
      expect(t.cell(1, 0), 'Ada');
      expect(t.row(1), ['Ada', '36']);
      expect(t.column(1), ['age', '36', '']);
      expect(t.rows(1).raw, people.sublist(1));
      expect(t.columns(1, 2).raw, [
        ['age'],
        ['36'],
        [''],
      ]);
      expect(t.transpose().raw, [
        ['name', 'Ada', 'Linus'],
        ['age', '36', ''],
      ]);
      expect(() => t.raw.add([]), throwsUnsupportedError);
    });

    test('rejects ragged rows', () {
      expect(
        () => DataTable([
          ['a', 'b'],
          ['c'],
        ]),
        throwsArgumentError,
      );
    });

    test('compares by value', () {
      expect(DataTable(people), DataTable(people));
      expect(DataTable(people).hashCode, DataTable(people).hashCode);
      expect(DataTable(people), isNot(DataTable(people.sublist(1))));
    });

    test('untyped conversions return strings', () {
      final t = DataTable(people);
      expect(t.asList(), ['name', 'age', 'Ada', '36', 'Linus', '']);
      expect(t.asLists(), people);
      expect(t.asMaps(), [
        {'name': 'Ada', 'age': '36'},
        {'name': 'Linus', 'age': ''},
      ]);
    });

    test('converts to built-in cell types', () {
      final numbers = DataTable([
        ['1', '2'],
        ['3', ''],
      ]);
      expect(numbers.asLists<int?>(), [
        [1, 2],
        [3, null],
      ]);
      expect(numbers.rows(0, 1).asList<double>(), [1.0, 2.0]);
      expect(
        DataTable([
          ['1.5', 'true', '12345678901234567890'],
        ]).asLists<Object>(),
        [
          ['1.5', 'true', '12345678901234567890'],
        ],
      );
      expect(
        DataTable([
          ['true', 'FALSE'],
        ]).asList<bool>(),
        [true, false],
      );
      expect(
        DataTable([
          ['1.5', '2'],
        ]).asList<num>(),
        [1.5, 2],
      );
      expect(
        DataTable([
          ['12345678901234567890'],
        ]).asList<BigInt>(),
        [BigInt.parse('12345678901234567890')],
      );
      expect(
        DataTable([
          ['', 'x'],
        ]).asList<String?>(),
        [null, 'x'],
      );
      expect(
        DataTable([
          ['', 'x'],
        ]).asList<String>(),
        ['', 'x'],
      );
      expect(
        () => numbers.asLists<int>(),
        throwsA(isA<ConversionException>()),
        reason: 'an empty cell is not an int',
      );
    });

    test('converts to maps', () {
      final t = DataTable([
        ['KMSY', '29.993333'],
        ['KSFO', '37.618889'],
      ]);
      expect(t.asMap<String, double>(), {'KMSY': 29.993333, 'KSFO': 37.618889});
      expect(DataTable(people).asMaps<String, String?>().last, {
        'name': 'Linus',
        'age': null,
      });
      expect(
        () => DataTable(people).transpose().asMap<String, String>(),
        throwsA(isA<ConversionException>()),
      );
      expect(
        () => DataTable([
          ['a', '1'],
          ['a', '2'],
        ]).asMap<String, int>(),
        throwsA(isA<ConversionException>()),
      );
    });

    test('user-built tables only know the built-in types', () {
      expect(
        () => DataTable(people).asList<Person>(),
        throwsA(isA<ConversionException>()),
      );
    });

    test('uses registered entry, row, cell and table types', () {
      final entry = DataTableType<Person>.entry(
        (e) => Person(e['name']!, int.tryParse(e['age']!)),
      );
      expect(table(people, [entry]).asList<Person>(), [
        Person('Ada', 36),
        Person('Linus', null),
      ]);

      final row = DataTableType<Person>.row(
        (r) => Person(r[0], int.tryParse(r[1])),
      );
      expect(table(people.sublist(1), [row]).asList<Person>(), [
        Person('Ada', 36),
        Person('Linus', null),
      ]);

      final cell = DataTableType<Money>.cell(
        (c) => Money(int.parse(c)),
        replaceWithEmptyString: '[blank]',
      );
      expect(
        table(
          [
            ['1', ''],
          ],
          [cell],
        ).asLists<Money?>(),
        [
          [Money(1), null],
        ],
      );

      final blank = DataTableType<String>.cell(
        (c) => c,
        replaceWithEmptyString: '[blank]',
      );
      expect(
        table(
          [
            ['[blank]', ''],
          ],
          [blank],
        ).asList<String?>(),
        ['', null],
      );

      final matrix = DataTableType<Matrix>.table((t) => Matrix(t.raw));
      expect(table(people, [matrix]).convert<Matrix>().rows, people);
      expect(table(people, [entry]).convert<List<Person>>(), hasLength(2));
      expect(DataTable(people).convert<List<List<String>>>(), people);
    });

    test('entry types replace the empty-string marker in keys and values', () {
      final entry = DataTableType<Map<String, String>>.entry(
        (e) => e,
        replaceWithEmptyString: '[blank]',
      );
      expect(
        table(
          [
            ['a', '[blank]'],
            ['[blank]', 'x'],
          ],
          [entry],
        ).asList<Map<String, String>>(),
        [
          {'a': '', '': 'x'},
        ],
      );
    });

    test('wraps transformer errors', () {
      final entry = DataTableType<Person>.entry(
        (e) => throw const FormatException('bad'),
      );
      expect(
        () => table(people, [entry]).asList<Person>(),
        throwsA(
          isA<ConversionException>().having(
            (e) => e.cause,
            'cause',
            isA<FormatException>(),
          ),
        ),
      );
    });

    test('diff passes for equal tables and describes differences', () {
      DataTable(people).diff(DataTable(people));
      DataTable(people).diff(people);
      expect(
        () => DataTable([
          ['name', 'age'],
          ['Ada', '37'],
          ['Grace', '45'],
        ]).diff(people),
        throwsA(
          isA<TableDiffException>().having(
            (e) => e.diff,
            'diff',
            '    | name  | age |\n'
                '  - | Ada   | 36  |\n'
                '  - | Linus |     |\n'
                '  + | Ada   | 37  |\n'
                '  + | Grace | 45  |',
          ),
        ),
      );
    });

    test('formats as a Gherkin table', () {
      expect(
        DataTable([
          ['a|b', 'c'],
          ['long value', ''],
        ]).toString(),
        '| a\\|b       | c |\n| long value |   |',
      );
    });
  });

  group('DocString', () {
    final json = DocStringType<Map<String, Object?>>(
      (s) => jsonDecode(s) as Map<String, Object?>,
      contentType: 'application/json',
    );

    test('converts to String and registered types', () {
      final converter = TableConverter(docStringTypes: [json.spec]);
      final doc = DocString.withConverter(
        '{"a": 1}',
        converter,
        mediaType: 'application/json',
      );
      expect(doc.convert<String>(), '{"a": 1}');
      expect(doc.convert<DocString>(), same(doc));
      expect(doc.convert<Map<String, Object?>>(), {'a': 1});
      expect(
        () => DocString('x').convert<Map<String, Object?>>(),
        throwsA(isA<ConversionException>()),
      );
    });

    test('picks the type for the content type, else the only one', () {
      final upper = DocStringType<String>(
        (s) => s.toUpperCase(),
        contentType: 'upper',
      );
      final lower = DocStringType<String>(
        (s) => s.toLowerCase(),
        contentType: 'lower',
      );
      final converter = TableConverter(
        docStringTypes: [upper.spec, lower.spec],
      );
      // String needs no registration.
      expect(
        DocString.withConverter(
          'Ab',
          converter,
          mediaType: 'upper',
        ).convert<String>(),
        'Ab',
      );

      final a = DocStringType<Person>((s) => Person(s, 1), contentType: 'a');
      final b = DocStringType<Person>((s) => Person(s, 2), contentType: 'b');
      final people = TableConverter(docStringTypes: [a.spec, b.spec]);
      expect(
        DocString.withConverter(
          'x',
          people,
          mediaType: 'b',
        ).convert<Person>().age,
        2,
      );
      expect(
        () => DocString.withConverter('x', people).convert<Person>(),
        throwsA(isA<ConversionException>()),
      );
    });

    test('compares by value', () {
      expect(DocString('a', mediaType: 'b'), DocString('a', mediaType: 'b'));
      expect(DocString('a'), isNot(DocString('a', mediaType: 'b')));
    });
  });

  group('step parameters', () {
    const feature = '''
Feature: tables
  Scenario: s
    Given these people:
      | name  | age |
      | Ada   | 36  |
      | Linus |     |
''';

    Future<Object?> convert<T>(List<Glue> types) async {
      Object? received;
      void capture(T value) => received = value;
      final run = await runFeature(feature, [
        ...types,
        Given('these people:', capture),
      ]);
      final failure = run.result.testCases.single.decisiveStep;
      expect(run.result.success, isTrue, reason: '${failure?.error}');
      return received;
    }

    test('get the converted table chosen by their declared type', () async {
      expect(await convert<Object?>([]), isA<DataTable>());
      expect(await convert<DataTable>([]), isA<DataTable>());
      expect(await convert<List<List<String>>>([]), [
        ['name', 'age'],
        ['Ada', '36'],
        ['Linus', ''],
      ]);
      expect(await convert<List<Map<String, String?>>>([]), [
        {'name': 'Ada', 'age': '36'},
        {'name': 'Linus', 'age': null},
      ]);
      final entry = DataTableType<Person>.entry(
        (e) => Person(e['name']!, int.tryParse(e['age']!)),
      );
      expect(await convert<List<Person>>([entry]), [
        Person('Ada', 36),
        Person('Linus', null),
      ]);
      final matrix = DataTableType<Matrix>.table((t) => Matrix(t.raw));
      expect((await convert<Matrix>([matrix]))! as Matrix, isA<Matrix>());
    });

    test('fail clearly when no conversion fits', () async {
      final run = await runFeature(feature, [
        Given('these people:', (Person p) {}),
      ]);
      final step = run.result.testCases.single.steps.single;
      expect(step.status, Status.failed);
      expect(step.error, isA<ConversionException>());
    });

    test('single-column tables convert to lists of cells', () async {
      Object? received;
      final run = await runFeature(
        '''
Feature: f
  Scenario: s
    Given the numbers:
      | 1 |
      |   |
      | 3 |
''',
        [Given('the numbers:', (List<int?> numbers) => received = numbers)],
      );
      expect(run.result.success, isTrue);
      expect(received, [1, null, 3]);
    });

    test('doc strings convert by declared type and content type', () async {
      Object? received;
      final run = await runFeature(
        '''
Feature: f
  Scenario: s
    Given the payload:
      """application/json
      {"ok": true}
      """
''',
        [
          DocStringType<Map<String, Object?>>(
            (s) => jsonDecode(s) as Map<String, Object?>,
            contentType: 'application/json',
          ),
          Given('the payload:', (Map<String, Object?> json) => received = json),
        ],
      );
      expect(run.result.success, isTrue);
      expect(received, {'ok': true});
    });
  });
}
