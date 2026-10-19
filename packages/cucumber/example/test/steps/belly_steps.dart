import 'package:cucumber/cucumber.dart';
import 'package:cucumber_example/belly.dart';
import 'package:test/test.dart';

/// The World: fresh state for each scenario attempt. Extending [World] is
/// optional; it adds `parameters`, `attach`, `log` and `link`.
class BellyWorld extends World {
  /// The belly under test.
  final belly = Belly();
}

/// A row of a meal plan table.
class CukeOrder {
  /// Creates an order.
  CukeOrder(this.color, this.count);

  /// The colour.
  final Color color;

  /// How many.
  final int count;
}

/// The step definitions, hooks and types of the example.
final bellyGlue = <Glue>[
  ParameterType<Color>(
    'color',
    r'red|green|blue',
    (String name) => Color.values.byName(name),
  ),
  DataTableType<CukeOrder>.entry(
    (entry) => CukeOrder(
      Color.values.byName(entry['color']!),
      int.parse(entry['count']!),
    ),
  ),

  Before((BellyWorld w, Scenario s) {
    w.log('${w.parameters['greeting'] ?? 'Hello'}, ${s.name}!');
  }, name: 'greet'),

  Given('an empty belly', (BellyWorld w) {
    expect(w.belly.cukes, 0);
  }),
  Given('I have {int} cuke(s) in my belly', (BellyWorld w, int cukes) {
    w.belly.eat(cukes);
  }),
  Given('I have {int} {color} cukes in my belly', (
    BellyWorld w,
    int cukes,
    Color color,
  ) {
    w.belly.eat(cukes, color);
  }),
  Given('I eat these cukes:', (BellyWorld w, List<CukeOrder> orders) {
    for (final order in orders) {
      w.belly.eat(order.count, order.color);
    }
  }),
  When('I wait {int} hour(s)', (BellyWorld w, int hours) async {
    await Future<void>.delayed(Duration.zero);
    w.belly.wait(hours);
  }),
  Then('my belly should growl', (BellyWorld w) {
    expect(w.belly.isGrowling, isTrue);
  }),
  Then('my belly should not growl', (BellyWorld w) {
    expect(w.belly.isGrowling, isFalse);
  }),
  Then('my belly should contain {int} cukes', (BellyWorld w, int cukes) {
    expect(w.belly.cukes, cukes);
  }),
  Then('the meal plan notes are:', (BellyWorld w, DocString notes) {
    expect(notes.mediaType, 'markdown');
    w.attach(notes.content, mediaType: 'text/markdown');
  }),
];
