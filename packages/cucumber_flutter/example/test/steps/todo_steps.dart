import 'package:cucumber_flutter/cucumber_flutter.dart';
import 'package:cucumber_flutter_example/main.dart';
import 'package:flutter/material.dart' hide DataTable;
import 'package:flutter_test/flutter_test.dart';

/// The state of one scenario attempt: FlutterWorld adds the WidgetTester.
class TodoWorld extends FlutterWorld {
  /// Types [title] into the field and taps the add button.
  Future<void> add(String title) async {
    await tester.enterText(find.byKey(const Key('new-todo')), title);
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
  }
}

final todoGlue = <Glue>[
  Given('the app is running', (TodoWorld w) async {
    await w.tester.pumpWidget(const TodoApp());
  }),
  Given('the list has:', (TodoWorld w, List<String> titles) async {
    for (final title in titles) {
      await w.add(title);
    }
  }),
  When('I add {string}', (TodoWorld w, String title) => w.add(title)),
  When('I add {int} items', (TodoWorld w, int count) async {
    for (var i = 1; i <= count; i++) {
      await w.add('Item $i');
    }
  }),
  When('I complete {string}', (TodoWorld w, String title) async {
    await w.tester.tap(find.widgetWithText(CheckboxListTile, title));
    await w.tester.pump();
  }),
  Then('the list shows:', (TodoWorld w, List<String> titles) {
    final tiles = w.tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect([for (final tile in tiles) (tile.title! as Text).data], titles);
  }),
  Then('the list is empty', (TodoWorld w) {
    expect(find.byType(CheckboxListTile), findsNothing);
  }),
  Then('I see {string}', (TodoWorld w, String text) {
    expect(find.text(text), findsOneWidget);
  }),
  After((TodoWorld w, Scenario s) {
    if (s.isFailed) w.log(w.tester.allWidgets.take(30).join('\n'));
  }),
];
