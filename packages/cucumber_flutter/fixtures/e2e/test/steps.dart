import 'package:cucumber_flutter/cucumber_flutter.dart';
import 'package:cucumber_flutter_e2e/counter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final glue = <Glue>[
  Given('the counter is shown', (FlutterWorld w) async {
    await w.tester.pumpWidget(const Counter());
  }),
  When('I tap the button', (FlutterWorld w) async {
    await w.tester.tap(find.byKey(const Key('increment')));
    await w.tester.pump();
  }),
  Then('the counter shows {string}', (FlutterWorld w, String text) {
    expect(find.text(text), findsOneWidget);
  }),
  Given('a widget that throws while building', (FlutterWorld w) async {
    // Flutter catches the error and shows an ErrorWidget: the step itself
    // returns normally, but the error fails it.
    await w.tester.pumpWidget(
      Builder(builder: (_) => throw StateError('broken widget')),
    );
  }),
  Given('a pending step', () => pending('not yet')),
  Given('a skipped step', () => skip('not here')),
  Given('a step that fails the first attempt', (FlutterWorld w) {
    if (w.scenario.attempt == 0) throw StateError('first attempt');
  }),
  After((FlutterWorld w, Scenario s) {
    w.log('After ${s.name}: ${find.byType(Counter).evaluate().length}');
  }),
];
