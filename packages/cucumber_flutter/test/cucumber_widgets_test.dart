// Declares widget-test suites in this file and checks what their steps and
// hooks saw. Failing scenarios are run by end_to_end_test.dart instead.
import 'package:cucumber_flutter/cucumber_flutter.dart';
import 'package:flutter/material.dart' hide DataTable;
import 'package:flutter_test/flutter_test.dart';

class TapWorld extends FlutterWorld {
  TapWorld() {
    worlds.add(this);
  }

  static final worlds = <TapWorld>[];
  final testers = <WidgetTester>[];
}

/// A World with a superclass of its own, mixing in FlutterWorld.
class Base {}

class MixedWorld extends Base with FlutterWorld {}

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: TextButton(
      onPressed: () => setState(() => _taps++),
      child: Text('$_taps'),
    ),
  );
}

List<Glue> glue<W extends FlutterWorld>(List<String> seen) => [
  BeforeAll(() {
    try {
      DefaultFlutterWorld().tester;
    } on StateError catch (e) {
      seen.add('BeforeAll: ${e.message}');
    }
  }),
  Before((W w) => seen.add('Before: ${w.tester.runtimeType}')),
  Given('a button that counts taps', (W w) async {
    await w.tester.pumpWidget(const Counter());
    w.log('pumped');
  }),
  When('I tap it {int} times', (W w, int times) async {
    for (var i = 0; i < times; i++) {
      await w.tester.tap(find.byType(TextButton));
      await w.tester.pump();
    }
  }),
  Then('it shows {string}', (W w, String text) {
    expect(find.text(text), findsOneWidget);
  }),
  Then('there is no button', (W w) {
    expect(find.byType(TextButton), findsNothing);
    seen.add('scenario: ${w.scenario.name}');
  }),
  After((W w) => seen.add('After: ${w.tester.runtimeType}')),
];

void main() {
  final typed = <String>[];
  final messages = CollectingPlugin();
  group('with a FlutterWorld', () {
    cucumberWidgets(
      features: ['test/features/widgets.feature'],
      world: TapWorld.new,
      glue: [
        ...glue<TapWorld>(typed),
        BeforeStep((TapWorld w) => w.testers.add(w.tester)),
      ],
      plugins: [messages],
      suiteName: 'typed',
    );
  });

  test('steps and hooks get the scenario\'s WidgetTester', () {
    expect(typed, [
      'BeforeAll: FlutterWorld.tester can only be used while a scenario of a '
          'cucumberWidgets suite is running.',
      'Before: WidgetTester',
      'After: WidgetTester',
      'Before: WidgetTester',
      'scenario: a new widget tree',
      'After: WidgetTester',
    ]);
    final [first, second] = TapWorld.worlds;
    expect(first.testers, hasLength(3));
    expect(first.testers.toSet(), hasLength(1), reason: 'one tester');
    expect(second.testers, hasLength(1));
  });

  test('reports passed scenarios and World attachments', () {
    final statuses = [
      for (final e in messages.envelopes)
        if (e.testStepFinished case final finished?)
          finished.testStepResult.status.value,
    ];
    expect(statuses, everyElement('PASSED'));
    // Before, 3 steps and After; Before, 1 step and After.
    expect(statuses, hasLength(5 + 3));
    expect(
      [
        for (final e in messages.envelopes)
          if (e.attachment case final attachment?) attachment.body,
      ],
      ['pumped'],
    );
    expect(messages.envelopes.last.testRunFinished?.success, isTrue);
  });

  final defaulted = <String>[];
  group('without a world', () {
    cucumberWidgets(
      features: ['test/features/widgets.feature'],
      glue: glue<FlutterWorld>(defaulted),
      suiteName: 'default',
    );
  });

  test('each scenario gets a DefaultFlutterWorld', () {
    expect(defaulted, contains('scenario: a new widget tree'));
    expect(defaulted.where((s) => s.startsWith('After')), hasLength(2));
  });

  final mixed = <String>[];
  group('with FlutterWorld mixed in', () {
    cucumberWidgets(
      features: ['test/features/widgets.feature'],
      world: MixedWorld.new,
      glue: glue<MixedWorld>(mixed),
      suiteName: 'mixed',
    );
  });

  test('the mixin gives the tester and the World members', () {
    expect(mixed, contains('scenario: a new widget tree'));
    expect(mixed.where((s) => s.startsWith('Before:')), hasLength(2));
  });
}
