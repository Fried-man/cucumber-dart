// Dart glue equivalent to each compatibility kit sample's reference `.ts`
// step definitions (design §10, ADR-0019).
import 'dart:io';

import 'package:cucumber_core/cucumber_core.dart';

/// The World used by every sample: free-form state, like `this` in the
/// TypeScript glue.
class CckWorld extends World {
  /// Scenario state.
  final Map<String, Object?> state = {};
}

/// A failed assertion in sample glue.
class AssertionFailed implements Exception {
  AssertionFailed(this.message);

  final String message;

  @override
  String toString() => 'AssertionFailed: $message';
}

void check(bool condition, [String message = 'assertion failed']) {
  if (!condition) throw AssertionFailed(message);
}

/// A sample error, standing in for JavaScript's `Error`.
class SampleError implements Exception {
  SampleError(this.message);

  final String message;

  @override
  String toString() => message;
}

class Flight {
  Flight(this.from, this.to);

  final String from;
  final String to;
}

/// The glue for each sample. [dir] is the sample's directory.
final Map<String, List<Glue> Function(Directory dir)> sampleGlue = {
  'all-statuses': (_) => [
    Given(RegExp(r'^a step$'), () {}),
    Given(RegExp(r'^a failing step$'), () => throw SampleError('whoops')),
    Given(RegExp(r'^a pending step$'), () => pending()),
    Given(RegExp(r'^a skipped step$'), () => skip()),
    Given(RegExp(r'^an ambiguous (.*?)$'), (String _) {}),
    Given(RegExp(r'^(.*?) ambiguous step$'), (String _) {}),
  ],
  'ambiguous': (_) => [
    Given(RegExp(r'^a (.*?) with (.*?)$'), (String a, String b) {}),
    Given(RegExp(r'^a step with (.*?)$'), (String a) {}),
  ],
  'attachments': (dir) => [
    When(
      'the string {string} is attached as {string}',
      (CckWorld w, String text, String mediaType) =>
          w.attach(text, mediaType: mediaType),
    ),
    When('the string {string} is logged', (CckWorld w, String text) {
      w.log(text);
    }),
    When('text with ANSI escapes is logged', (CckWorld w) {
      w.log(
        'This displays a \x1b[31mr\x1b[0m\x1b[91ma\x1b[0m\x1b[33mi\x1b[0m'
        '\x1b[32mn\x1b[0m\x1b[34mb\x1b[0m\x1b[95mo\x1b[0m\x1b[35mw\x1b[0m',
      );
    }),
    When(
      'the following string is attached as {string}:',
      (CckWorld w, String mediaType, String text) =>
          w.attach(text, mediaType: mediaType),
    ),
    When(
      'an array with {int} bytes is attached as {string}',
      (CckWorld w, int size, String mediaType) =>
          w.attach(List<int>.generate(size, (i) => i), mediaType: mediaType),
    ),
    When('a PDF document is attached and renamed', (CckWorld w) {
      w.attach(
        File('${dir.path}/document.pdf').readAsBytesSync(),
        mediaType: 'application/pdf',
        fileName: 'renamed.pdf',
      );
    }),
    When('a link to {string} is attached', (CckWorld w, String uri) {
      w.link(uri);
    }),
    When('the string {string} is attached as {string} before a failure', (
      CckWorld w,
      String text,
      String mediaType,
    ) {
      w.attach(text, mediaType: mediaType);
      throw SampleError('whoops');
    }),
  ],
  'backgrounds': (_) => _orderActionOutcome(),
  'cdata': (_) => [
    Given('I have {int} <![CDATA[cukes]]> in my belly', (int count) {}),
  ],
  'data-tables': (_) => [
    When('the following table is transposed:', (CckWorld w, DataTable table) {
      w.state['transposed'] = table.transpose();
    }),
    Then('it should be:', (CckWorld w, DataTable expected) {
      (w.state['transposed']! as DataTable).diff(expected);
    }),
  ],
  'data-tables-doc-strings': (_) => [
    Given('a step with a data table a doc string', (
      DataTable table,
      String string,
    ) {
      check(
        table ==
            DataTable([
              ['hello'],
            ]),
      );
      check(string == 'world');
    }),
    Given('a step with a doc string a data table', (
      String string,
      DataTable table,
    ) {
      check(string == 'hello');
      check(
        table ==
            DataTable([
              ['world'],
            ]),
      );
    }),
  ],
  'data-tables-with-expression': (_) => [
    Given('a {string} with a table', (String string, DataTable table) {
      check(string == 'Cucumber');
      check(
        table ==
            DataTable([
              ['Species', 'Cucumis sativus'],
            ]),
      );
    }),
  ],
  'doc-strings': (_) => [Given('a doc string:', (String docString) {})],
  'doc-strings-with-expression': (_) => [
    Given('a {string} with a doc string:', (String string, String docString) {
      check(string == 'Cucumber');
      check(docString == 'Cucumis sativus');
    }),
  ],
  'empty': (_) => [],
  'examples-tables': (_) => [
    ..._cucumbers().take(1),
    Given('there are {int} friends', (CckWorld w, int friends) {
      w.state['friends'] = friends;
    }),
    ..._cucumbers().skip(1),
    Then('each person can eat {int} cucumbers', (CckWorld w, int share) {
      final count = w.state['count']! as int;
      final friends = w.state['friends']! as int;
      check((count / (1 + friends)).floor() == share);
    }),
  ],
  'examples-tables-attachment': (dir) => [
    When('a JPEG image is attached', (CckWorld w) {
      w.attach(
        File('${dir.path}/cucumber.jpeg').readAsBytesSync(),
        mediaType: 'image/jpeg',
      );
    }),
    When('a PNG image is attached', (CckWorld w) {
      w.attach(
        File('${dir.path}/cucumber.png').readAsBytesSync(),
        mediaType: 'image/png',
      );
    }),
  ],
  'examples-tables-undefined': (_) => _cucumbers(),
  'examples-tables-undefined-multiple': (_) => _cucumbers(),
  'failedish-combinations': (_) => [
    Given(RegExp(r'^a step$'), () {}),
    Given(RegExp(r'^a skipped step$'), () => skip()),
    Given(RegExp(r'^a pending step$'), () => pending()),
    Given(RegExp(r'^an ambiguous (.*?)$'), (String _) {}),
    Given(RegExp(r'^(.*?) ambiguous step$'), (String _) {}),
    Given(RegExp(r'^a failing step$'), () => throw SampleError('whoops')),
  ],
  'global-hooks': (_) => [
    BeforeAll(() {}),
    BeforeAll(() {}),
    When('a step passes', () {}),
    When('a step fails', () => throw SampleError('Exception in step')),
    AfterAll(() {}),
    AfterAll(() {}),
  ],
  'global-hooks-afterall-error': (_) => [
    BeforeAll(() {}),
    BeforeAll(() {}),
    When('a step passes', () {}),
    AfterAll(() {}),
    AfterAll(() => throw SampleError('AfterAll hook went wrong')),
    AfterAll(() {}),
  ],
  'global-hooks-attachments': (_) => [
    BeforeAll((TestRun run) async {
      run.attach('Attachment from BeforeAll hook', mediaType: 'text/plain');
    }),
    When('a step passes', () {}),
    AfterAll((TestRun run) async {
      run.attach('Attachment from AfterAll hook', mediaType: 'text/plain');
    }),
  ],
  'global-hooks-beforeall-error': (_) => [
    BeforeAll(() {}),
    BeforeAll(() => throw SampleError('BeforeAll hook went wrong')),
    BeforeAll(() {}),
    When('a step passes', () {}),
    AfterAll(() {}),
    AfterAll(() {}),
  ],
  'hooks': (_) => [
    Before(() {}),
    When('a step passes', () {}),
    When('a step fails', () => throw SampleError('Exception in step')),
    After(() {}),
  ],
  'hooks-attachment': (dir) => [
    Before((CckWorld w) async {
      w.attach(
        File('${dir.path}/cucumber.svg').readAsBytesSync(),
        mediaType: 'image/svg+xml',
      );
    }),
    When('a step passes', () {}),
    After((CckWorld w) async {
      w.attach(
        File('${dir.path}/cucumber.svg').readAsBytesSync(),
        mediaType: 'image/svg+xml',
      );
    }),
  ],
  'hooks-conditional': (_) => [
    Before(() async {}, tags: '@passing-hook'),
    Before(
      () => throw SampleError('Exception in conditional hook'),
      tags: '@fail-before',
    ),
    When('a step passes', () {}),
    After(
      () => throw SampleError('Exception in conditional hook'),
      tags: '@fail-after',
    ),
    After(() async {}, tags: '@passing-hook'),
  ],
  'hooks-named': (_) => [
    Before(() {}, name: 'A named before hook'),
    When('a step passes', () {}),
    After(() {}, name: 'A named after hook'),
  ],
  'hooks-skipped': (_) => [
    Before(() {}),
    Before(() => skip(), tags: '@skip-before'),
    Before(() {}),
    Given('a normal step', () {}),
    Given('a step that skips', () => skip()),
    After(() {}),
    After(() => skip(), tags: '@skip-after'),
    After(() {}),
  ],
  'hooks-undefined': (_) => [Before(() {}), After(() {})],
  'minimal': (_) => [Given('I have {int} cukes in my belly', (int count) {})],
  'multiple-features': (_) => [Given('an order for {string}', (String _) {})],
  'multiple-features-reversed': (_) => [
    Given('an order for {string}', (String _) {}),
  ],
  'parameter-types': (_) => [
    ParameterType<Flight>(
      'flight',
      RegExp(r'([A-Z]{3})-([A-Z]{3})'),
      (String from, String to) => Flight(from, to),
    ),
    Given('{flight} has been delayed', (Flight flight) {
      check(flight.from == 'LHR');
      check(flight.to == 'CDG');
    }),
  ],
  'pending': (_) => [
    Given('an implemented non-pending step', () {}),
    Given('an implemented step that is skipped', () {}),
    Given('an unimplemented pending step', () => pending()),
  ],
  'pending-exception': (_) => [
    Given(
      'an unimplemented pending step',
      () => throw PendingException('TODO'),
    ),
  ],
  'regular-expression': (_) => [
    Given(
      RegExp(r'^a (.*?)(?: and a (.*?))?(?: and a (.*?))?$'),
      (String vegetable1, String? vegetable2, String? vegetable3) {},
    ),
  ],
  'retry': (_) {
    var secondTimePass = 0;
    var thirdTimePass = 0;
    return [
      Given('a step that always passes', () {}),
      Given('a step that passes the second time', () {
        secondTimePass++;
        if (secondTimePass < 2) throw SampleError('Exception in step');
      }),
      Given('a step that passes the third time', () {
        thirdTimePass++;
        if (thirdTimePass < 3) throw SampleError('Exception in step');
      }),
      Given(
        'a step that always fails',
        () => throw SampleError('Exception in step'),
      ),
    ];
  },
  'retry-ambiguous': (_) => [
    Given('an ambiguous step', () {}),
    Given('an ambiguous step', () {}),
  ],
  'retry-pending': (_) => [Given('a pending step', () => pending())],
  'retry-undefined': (_) => [],
  'rules': (_) => [
    Given('the customer has {int} cents', (CckWorld w, int money) {
      w.state['money'] = money;
    }),
    Given('there are chocolate bars in stock', (CckWorld w) {
      w.state['stock'] = ['Mars'];
    }),
    Given('there are no chocolate bars in stock', (CckWorld w) {
      w.state['stock'] = <String>[];
    }),
    When('the customer tries to buy a {int} cent chocolate bar', (
      CckWorld w,
      int price,
    ) {
      final stock = w.state['stock']! as List<String>;
      if ((w.state['money']! as int) >= price && stock.isNotEmpty) {
        w.state['chocolate'] = stock.removeLast();
      }
    }),
    Then('the sale should not happen', (CckWorld w) {
      check(w.state['chocolate'] == null);
    }),
    Then('the sale should happen', (CckWorld w) {
      check(w.state['chocolate'] != null);
    }),
  ],
  'rules-backgrounds': (_) => _orderActionOutcome(),
  'skipped': (_) => [
    Given('a step that does not skip', () {}),
    Given('a step that is skipped', () {}),
    Given('I skip a step', () => skip()),
  ],
  'skipped-exception': (_) => [
    Given('I skip a step', () => throw SkippedException('skipping')),
  ],
  'skipped-failing-hook': (_) => [
    Given('a step that skips', () => skip()),
    After(() => throw SampleError('whoops')),
  ],
  'stack-traces': (_) => [
    When('a step throws an exception', () => throw SampleError('BOOM')),
  ],
  'undefined': (_) => [
    Given('an implemented step', () {}),
    Given('a step that will be skipped', () {}),
  ],
  'undefined-multiple': (_) => [
    Given('an implemented step', () {}),
    Given('a step that will be skipped', () {}),
  ],
  'unknown-parameter-type': (_) => [
    Given(
      '{airport} is closed because of a strike',
      (Object airport) => throw SampleError(
        'Should not be called because airport parameter type has not been '
        'defined',
      ),
    ),
  ],
  'unused-steps': (_) => [
    Given('a step that is used', () {}),
    Given('a step that is not used', () {}),
  ],
};

List<Glue> _orderActionOutcome() => [
  Given('an order for {string}', (String _) {}),
  When('an action', () {}),
  Then('an outcome', () {}),
];

List<Glue> _cucumbers() => [
  Given('there are {int} cucumbers', (CckWorld w, int count) {
    w.state['count'] = count;
  }),
  When('I eat {int} cucumbers', (CckWorld w, int eat) {
    w.state['count'] = (w.state['count']! as int) - eat;
  }),
  Then('I should have {int} cucumbers', (CckWorld w, int left) {
    check(w.state['count'] == left, 'expected $left, was ${w.state['count']}');
  }),
];
