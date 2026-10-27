// The glue of the generated benchmark suite (see generator.dart).
//
// [glueFamilies] families of 8 step definitions each differ only in their
// warehouse number, so every pickle step is matched against every definition
// but matches exactly one, as in a real suite with many steps.
import 'package:cucumber/cucumber.dart';

/// The number of step definition families; feature `f` uses family
/// `f % glueFamilies`.
const int glueFamilies = 25;

/// The step definitions per family.
const int stepsPerFamily = 8;

/// The colours of the `{color}` parameter type.
enum Color {
  /// Red.
  red,

  /// Green.
  green,

  /// Blue.
  blue,

  /// Yellow.
  yellow,
}

/// A row of a stock table.
final class Item {
  /// Creates an item.
  Item(this.name, this.count);

  /// The item's name.
  final String name;

  /// How many there are.
  final int count;
}

/// The state of one scenario attempt.
final class WarehouseWorld extends World {
  /// Crates per warehouse.
  final Map<int, int> crates = {};

  /// Boxes per shelf.
  final Map<String, int> shelves = {};

  /// Colour per warehouse.
  final Map<int, Color> colors = {};

  /// Stock per warehouse.
  final Map<int, List<Item>> stock = {};

  /// How many hooks ran.
  int hooks = 0;
}

void _check(Object? actual, Object? expected) {
  if (actual != expected) {
    throw StateError('Expected $expected, got $actual.');
  }
}

/// The glue of the benchmark suite: 3 types, 6 hooks and
/// [glueFamilies] × [stepsPerFamily] step definitions, both Cucumber
/// Expressions and regular expressions.
List<Glue> warehouseGlue() => [
  ParameterType<Color>(
    'color',
    r'red|green|blue|yellow',
    (String name) => Color.values.byName(name),
  ),
  ParameterType<int>('weight', r'(\d+) kg', (String kilograms) {
    return int.parse(kilograms);
  }),
  DataTableType<Item>.entry(
    (entry) => Item(entry['name']!, int.parse(entry['count']!)),
  ),
  BeforeAll(() {}, name: 'open the warehouses'),
  Before((WarehouseWorld w) => w.hooks++),
  Before(
    (WarehouseWorld w, Scenario s) => w.hooks++,
    tags: '@slow and not @smoke',
    name: 'slow setup',
  ),
  AfterStep((Step s) {}, tags: '@traced'),
  After((WarehouseWorld w, Scenario s) {
    if (s.isFailed) w.log('failed: ${s.name}');
  }),
  AfterAll(() {}, name: 'close the warehouses'),
  for (var i = 0; i < glueFamilies; i++) ..._family(i),
];

List<Glue> _family(int i) => [
  Given('the {word} warehouse $i holds {int} crates', (
    WarehouseWorld w,
    String name,
    int crates,
  ) {
    w.crates[i] = crates;
  }),
  When('I move {int} crate(s) out of warehouse $i', (
    WarehouseWorld w,
    int crates,
  ) async {
    w.crates[i] = w.crates[i]! - crates;
  }),
  Then('warehouse $i holds {int} crates', (WarehouseWorld w, int crates) {
    _check(w.crates[i], crates);
  }),
  Given(RegExp('^shelf ([A-Z]\\d+) of warehouse $i has (\\d+) boxes\$'), (
    WarehouseWorld w,
    String shelf,
    int boxes,
  ) {
    w.shelves['$i/$shelf'] = boxes;
  }),
  When('I paint warehouse $i {color}', (WarehouseWorld w, Color color) {
    w.colors[i] = color;
  }),
  Given('warehouse $i stocks:', (WarehouseWorld w, List<Item> items) {
    w.stock[i] = items;
  }),
  Then('the stock of warehouse $i weighs {weight}', (
    WarehouseWorld w,
    int kilograms,
  ) {
    _check(
      w.stock[i]!.fold<int>(0, (sum, item) => sum + item.count),
      kilograms,
    );
  }),
  Then('the manifest of warehouse $i reads:', (
    WarehouseWorld w,
    DocString manifest,
  ) {
    _check(manifest.content.contains('warehouse $i'), true);
    w.attach(manifest.content, mediaType: 'text/plain');
  }),
];
