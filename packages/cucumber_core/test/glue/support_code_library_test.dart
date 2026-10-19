import 'package:cucumber_core/engine.dart';
import 'package:cucumber_core/src/glue/definitions.dart';
import 'package:test/test.dart';

class ShopWorld extends World {
  final List<String> events = [];
}

class OtherWorld {}

class Color {
  Color(this.name);
  final String name;
}

SupportCodeLibrary load<W extends Object>(List<Glue> glue) =>
    SupportCodeLibrary.load<W>(glue, ids: IdScheme.incrementing());

Matcher throwsGlueError(Object message) => throwsA(
  isA<GlueException>().having(
    (e) => e.errors.map((e) => e.message).join('\n'),
    'messages',
    message,
  ),
);

void main() {
  group('step definitions', () {
    test('accept bodies with and without the World', () {
      final library = load<ShopWorld>([
        Given('a', () {}),
        Given('b {int}', (int n) {}),
        Given('c {int}', (ShopWorld w, int n) {}),
        Given('d', (DataTable t) {}),
        Given('e', (World w, DocString d, DataTable t) {}),
      ]);
      final layouts = {
        for (final step in library.stepDefinitions)
          step.expression.patternSource: [
            for (final l in step.layouts)
              if (l.problem == null) (l.world, l.multilineCount),
          ],
      };
      expect(layouts['a'], [(false, 0)]);
      expect(layouts['b {int}'], [(false, 0)]);
      expect(layouts['c {int}'], [(true, 0)]);
      expect(layouts['d'], [(false, 1)]);
      expect(layouts['e'], [(true, 2)]);
    });

    test('reject impossible arities', () {
      expect(
        () => load([Given('a {int} {int}', (int a) {})]),
        throwsGlueError(contains('must take the 2 expression arguments')),
      );
      expect(
        () => load([Given('a', (int a, int b, int c, int d) {})]),
        throwsGlueError(contains('it takes 4 parameters')),
      );
      expect(
        () => load([Given('a', ({required int x}) {})]),
        throwsGlueError(contains('named parameters')),
      );
    });

    test('reject parameters that do not accept the expression types', () {
      expect(
        () => load([Given('I have {int} cukes', (String n) {})]),
        throwsGlueError(contains('parameter 1 must accept int')),
      );
      expect(
        () => load<ShopWorld>([Given('a {int}', (OtherWorld w, int n) {})]),
        throwsGlueError(contains('must accept the World (ShopWorld)')),
      );
      expect(
        () => load([Given(RegExp(r'^(\d+) and (.*)$'), (int a, int b) {})]),
        throwsGlueError(contains('parameter 2 must accept String')),
      );
    });

    test('type regular expression groups by parameter type', () {
      final library = load([
        Given(RegExp(r'^(\d+) cukes$'), (int n) {}),
        Given(RegExp(r'^(.*) things$'), (String s) {}),
        Given(RegExp(r'^(x+)$'), (String s) {}),
      ]);
      expect(
        [
          for (final s in library.stepDefinitions)
            s.expression.parameterTypes.single?.name,
        ],
        ['int', '', null],
      );
    });

    test('reject invalid expressions and expression types', () {
      expect(
        () => load([Given('a (b', () {})]),
        throwsGlueError(contains("The '(' does not have a matching ')'")),
      );
      expect(
        () => load([Given(42, () {})]),
        throwsGlueError(contains('must be a String or a RegExp')),
      );
    });

    test('report undefined parameter types instead of failing', () {
      final library = load([Given('{airport} is closed', (Object a) {})]);
      expect(library.stepDefinitions, isEmpty);
      expect(library.undefinedParameterTypes.single.name, 'airport');
      expect(
        library.envelopes.single.undefinedParameterType?.expression,
        '{airport} is closed',
      );
    });

    test('collect every problem', () {
      expect(
        () => load([Given('a {int}', () {}), Before(() {}, tags: 'a and')]),
        throwsA(
          isA<GlueException>().having((e) => e.errors, 'errors', hasLength(2)),
        ),
      );
    });
  });

  group('parameter types', () {
    test('can be used before they are defined', () {
      final library = load([
        Given('{color} light', (Color c) {}),
        ParameterType<Color>('color', 'red|green', (String s) => Color(s)),
      ]);
      expect(library.stepDefinitions, hasLength(1));
      expect(
        library.envelopes.map((e) => e.parameterType != null),
        [false, true],
        reason: 'messages keep definition order',
      );
    });

    test('check transformers', () {
      expect(
        () => load([
          ParameterType<Color>('color', '(r)(g)', (String s) => Color(s)),
        ]),
        throwsGlueError(contains('must take 2 String parameters')),
      );
      expect(
        () => load([
          ParameterType<Color>('color', 'red', (int s) => Color('$s')),
        ]),
        throwsGlueError(contains('parameter 1 must accept a String')),
      );
      expect(
        () => load<ShopWorld>([
          ParameterType<Color>(
            'color',
            'red',
            (OtherWorld w, String s) => Color(s),
          ),
        ]),
        throwsGlueError(contains('must accept the World')),
      );
      load<ShopWorld>([
        ParameterType<Color>(
          'color',
          'red',
          (ShopWorld w, String s) => Color(s),
        ),
      ]);
    });

    test('reject duplicates and invalid regular expressions', () {
      expect(
        () => load([
          ParameterType<Color>('color', 'red', (String s) => Color(s)),
          ParameterType<Color>('color', 'blue', (String s) => Color(s)),
        ]),
        throwsGlueError(
          contains('There is already a parameter type with name color'),
        ),
      );
      expect(
        () => load([
          ParameterType<Color>(
            'color',
            RegExp('red', caseSensitive: false),
            (String s) => Color(s),
          ),
        ]),
        throwsGlueError(contains("can't use flag 'i'")),
      );
      expect(
        () => load([ParameterType<int>('int', r'\d+', int.parse)]),
        throwsGlueError(
          contains('There is already a parameter type with name int'),
        ),
      );
    });

    test('check steps against the declared type', () {
      expect(
        () => load([
          ParameterType<Color>('color', 'red', (String s) => Color(s)),
          Given('{color}', (String s) {}),
        ]),
        throwsGlueError(contains('parameter 1 must accept Color')),
      );
    });
  });

  group('hooks', () {
    test('resolve their bodies', () {
      final library = load<ShopWorld>([
        Before(() {}),
        Before((ShopWorld w) {}),
        Before((Scenario s) {}),
        Before((ShopWorld w, Scenario s) {}),
        AfterStep((Step s) {}),
        BeforeAll((TestRun r) {}),
      ]);
      expect(library.beforeHooks.map((h) => h.layout), [
        HookLayout.none,
        HookLayout.world,
        HookLayout.context,
        HookLayout.worldAndContext,
      ]);
      expect(library.afterStepHooks.single.layout, HookLayout.context);
      expect(library.beforeAllHooks.single.layout, HookLayout.context);
    });

    test('reject other bodies', () {
      expect(
        () => load<ShopWorld>([Before((int x) {})]),
        throwsGlueError(contains('must be one of')),
      );
      expect(
        () => load([BeforeAll((Scenario s) {})]),
        throwsGlueError(contains('() or (TestRun)')),
      );
      expect(
        () => load([AfterStep((Scenario s, Step x, int y) {})]),
        throwsGlueError(contains('must be one of')),
      );
    });

    test('are sorted by order, then definition index (ADR-0014)', () {
      final library = load([
        Before(() {}, name: 'b1'),
        Before(() {}, name: 'b2', order: -1),
        Before(() {}, name: 'b3'),
        After(() {}, name: 'a1'),
        After(() {}, name: 'a2'),
        After(() {}, name: 'a3', order: 10),
        AfterAll(() {}, name: 'z1'),
        AfterAll(() {}, name: 'z2'),
      ]);
      expect(library.beforeHooks.map((h) => h.glue.name), ['b2', 'b1', 'b3']);
      expect(library.afterHooks.map((h) => h.glue.name), ['a3', 'a2', 'a1']);
      expect(library.afterAllHooks.map((h) => h.glue.name), ['z2', 'z1']);
    });

    test('evaluate tag expressions', () {
      final hook = load([
        Before(() {}, tags: '@a and not @b'),
      ]).beforeHooks.single;
      expect(hook.appliesTo(['@a']), isTrue);
      expect(hook.appliesTo(['@a', '@b']), isFalse);
      expect(hook.toMessage().tagExpression, '@a and not @b');
    });
  });

  group('data table and doc string types', () {
    test('reject conflicting registrations', () {
      expect(
        () => load([
          DataTableType<Color>.entry((e) => Color(e['name']!)),
          DataTableType<Color>.row((r) => Color(r.first)),
        ]),
        throwsGlueError(contains('already a data table type')),
      );
      expect(
        () => load([
          DocStringType<Color>(Color.new, contentType: 'json'),
          DocStringType<Color>(Color.new, contentType: 'json'),
        ]),
        throwsGlueError(contains('already a doc string type')),
      );
      load([
        DataTableType<Color>.entry((e) => Color(e['name']!)),
        DataTableType<Color>.cell(Color.new),
        DocStringType<Color>(Color.new, contentType: 'json'),
        DocStringType<Color>(Color.new),
      ]);
    });
  });
}
