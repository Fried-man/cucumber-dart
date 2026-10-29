# Writing glue

*Glue* is the code behind the features: step definitions, hooks, and the types that turn step text, data tables and
doc strings into Dart values. A suite receives it as a `List<Glue>`. The examples on this page come from the shop in
[`packages/cucumber/fixtures/guide`](../../packages/cucumber/fixtures/guide/): its features are
[`cart.feature`](../../packages/cucumber/fixtures/guide/features/cart.feature) and
[`checkout.feature`](../../packages/cucumber/fixtures/guide/features/checkout.feature), and its glue is
[`test/steps/shop_steps.dart`](../../packages/cucumber/fixtures/guide/test/steps/shop_steps.dart).

Everything on this page is imported with `package:cucumber/cucumber.dart`.

## Glue values

Glue values are immutable values, not registrations: constructing a `Given` does nothing until a suite receives it.
So glue can be split into lists and combined freely:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#glue -->
```dart
final shopGlue = <Glue>[
  ...shopTypes,
  ...cartSteps,
  ...checkoutSteps,
  ...shopHooks,
];
```

- **Order.** The list's order is the *definition order*: hooks of the same kind run in it (see [Hooks](#hooks)), and
  reports list the glue in it.
- **Locations.** Each value records where it was constructed, so reports, IDEs and error messages point at the line of
  your code.
- **Checks.** The glue is checked when the suite is declared. Invalid expressions, duplicate parameter type names,
  invalid tag expressions, and bodies with the wrong number or types of parameters throw a `GlueException` that lists
  every problem with its location, and `dart test` reports it as a load error of the test file.

## Steps

`Given`, `When` and `Then` define steps. Each takes an expression and a body:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#steps -->
```dart
Given('the catalogue:', (ShopWorld w, List<Product> products) {
  for (final product in products) {
    w.catalogue[product.name] = product;
  }
}),
When('I add {int} {product} to the cart', (
  ShopWorld w,
  int quantity,
  Product product,
) {
  w.cart.add(product, quantity);
}),
Then('the cart contains {int} {product}', (
  ShopWorld w,
  int quantity,
  Product product,
) {
  expect(w.cart.quantityOf(product.name), quantity);
}),
Then('the total is {money}', (ShopWorld w, Money total) {
  expect(w.cart.total, total);
}),
```

As in every Cucumber implementation, the keyword does not affect matching: `Given('the catalogue:', …)` also matches
`And the catalogue:` or `When the catalogue:`. A step that no definition matches is *undefined*, and one that several
definitions match is *ambiguous*. Both fail the scenario.

### Cucumber Expressions

A `String` expression is a [Cucumber Expression](https://github.com/cucumber/cucumber-expressions#readme): text with
`{parameters}`, optional text in parentheses (`item(s)`) and alternatives separated by `/` (`cart/basket`). These
parameter types are built in:

| Parameter | Matches | Dart type |
|---|---|---|
| `{int}`, `{byte}`, `{short}`, `{long}` | `42`, `-1` | `int` |
| `{biginteger}` | `12345678901234567890` | `BigInt` |
| `{float}`, `{double}` | `3.14`, `-.5`, `1E3` | `double` |
| `{bigdecimal}` | the same as `{float}` | `String` |
| `{word}` | a word without whitespace | `String` |
| `{string}` | `"text"` or `'text'`, without the quotes | `String` |
| `{}` | anything | `String` |

`{money}` and `{product}` are [parameter types](#parameter-types) of the shop.

### Regular expressions

A `RegExp` expression is matched as a regular expression. Each capture group is a parameter. A group whose pattern is
the pattern of a parameter type is converted by that type, so `(\d+)` gives an `int`. The others give a `String`:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#regexp -->
```dart
Then(RegExp(r'^the cart has (\d+) items?$'), (ShopWorld w, int items) {
  expect(w.cart.items, items);
}),
```

Anchor regular expressions with `^` and `$`: unlike a Cucumber Expression, a regular expression may match part of
the step text.

### Step bodies

A body takes these positional parameters, in this order:

1. optionally, the World ([see below](#the-world));
2. one parameter for each parameter of the expression;
3. the step's data table or doc string, if it has one.

The types are checked when the glue loads: `{int}` needs a parameter that accepts an `int`, and the World parameter
must accept the suite's World type. Bodies can be `async`: the step finishes when the returned `Future` completes.
Return values are ignored.

## Parameter types

`ParameterType<T>` defines a `{name}` parameter. Its regular expression says what it matches, and its transformer
turns the match into a `T`:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#types -->
```dart
final shopTypes = <Glue>[
  // {money}: two capture groups, so the transformer takes two Strings.
  ParameterType<Money>('money', r'€(\d+)\.(\d{2})', (
    String euros,
    String cents,
  ) {
    return Money(int.parse(euros) * 100 + int.parse(cents));
  }),
  // {product}: the transformer can take the World first.
  ParameterType<Product>('product', r'"([^"]*)"', (ShopWorld w, String name) {
    return w.catalogue[name] ?? (throw ArgumentError('No product "$name"'));
  }),
  // A step parameter List<Product> receives one Product per data row.
  DataTableType<Product>.entry(
    (row) => Product(row['name']!, Money.parse(row['price']!)),
  ),
  // A step parameter Map<String, Object?> receives application/json content.
  DocStringType<Map<String, Object?>>(
    (content) => jsonDecode(content) as Map<String, Object?>,
    contentType: 'application/json',
  ),
];
```

- **The transformer** takes one `String` for each capture group of the regular expression, or a single `String`
  (the whole match) when it has none. A group that does not take part in the match is passed as `null`, so declare
  such parameters as `String?`.
- **The World.** The transformer may take the World first, like `{product}`, which looks the product up in the
  scenario's catalogue.
- **Async.** It may return a `Future<T>`, which is awaited before the step runs.
- **The regular expression** is a `String`, a `RegExp`, or a list of either. The `i` and `m` flags are not supported.
- **Snippets** use the type when it matches part of an undefined step, unless `useForSnippets: false`.
- **`preferForRegexpMatch: true`** makes the type win when several types match a regular expression group.

A step definition whose expression uses a parameter type that is not defined is left out, as in other Cucumber
implementations: the steps it would match are undefined, and the reports name the missing type.

## Data tables

A step followed by a table receives a data table as its last parameter:

<!-- excerpt: packages/cucumber/fixtures/guide/features/cart.feature#data-table -->
```gherkin
Then the cart is:
  | product | quantity |
  | apple   | 1        |
  | banana  | 4        |
```

The parameter's type decides what the step receives. The first of these that the parameter accepts is used:

1. `DataTable`: the table itself.
2. `List<List<String>>`: the cells.
3. A conversion registered with a `DataTableType`:
   - `List<T>` with `DataTableType<T>.entry` (one `T` per data row, from a map of the header to the row's cells) or
     `.row` (one `T` per row), or with `.cell` for a single column;
   - `List<List<T>>` with `DataTableType<T>.cell`;
   - `T` with `DataTableType<T>.table`, which converts the whole table.
4. `Map` and `List<Map>` of the built-in cell types `String`, `int`, `double`, `num`, `bool` and `BigInt`.

The catalogue step above takes a `List<Product>`, converted by the entry type in `shopTypes`. This step takes the
`DataTable` and compares it with the cart:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#data-table -->
```dart
Then('the cart is:', (ShopWorld w, DataTable expected) {
  expected.diff([
    ['product', 'quantity'],
    for (final (name, quantity) in w.cart.lines) [name, '$quantity'],
  ]);
}),
```

`diff` throws a `TableDiffException` that describes the differences when the tables differ. A `DataTable`
also has `raw`, `cell`, `row`, `column`, `rows`, `columns` and `transpose`, and converts with `asList<T>()`,
`asLists<T>()`, `asMaps<K, V>()`, `asMap<K, V>()` and `convert<T>()`. Without type arguments, these return strings.
Converting an empty cell to a nullable type gives `null`, and `replaceWithEmptyString: '[blank]'` on a
`DataTableType` turns the cells `[blank]` into empty strings. A conversion that fails throws a
`ConversionException`, which fails the step.

## Doc strings

A step followed by a doc string receives it as its last parameter:

<!-- excerpt: packages/cucumber/fixtures/guide/features/cart.feature#doc-string -->
```gherkin
Then the receipt is:
  """application/json
  {"items": [{"name": "melon", "quantity": 2}], "total": 400}
  """
```

The parameter can be a `DocString` (its `content` and `mediaType`), a `String` (its content), or a type that a
`DocStringType` produces. When several `DocStringType`s produce the same type, the one whose `contentType` is the doc
string's media type is used. This step receives the receipt as JSON, converted by the doc string type in `shopTypes`:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#doc-string -->
```dart
Then('the receipt is:', (ShopWorld w, Map<String, Object?> receipt) {
  expect(w.cart.receipt(), receipt);
}),
```

A step can have both a data table and a doc string. They are passed in the order they appear in the feature.

## The World

The World holds the state of one scenario. The suite creates a new one for every scenario, and again for every retry
of it, so scenarios never share state:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#world -->
```dart
/// The state of one scenario attempt.
class ShopWorld extends World {
  final catalogue = <String, Product>{};
  final cart = Cart();
  PaymentService? payments;
}
```

The suite's `world` option creates it (`world: ShopWorld.new`). Steps, hooks and parameter type transformers can
take it as their first parameter. Any class can be the World. Extending (or mixing in) `World` adds:

- `parameters`: the world parameters, set with the `worldParameters` option ([Configuration](configuration.md)).
  Each scenario gets its own deep copy.
- `scenario`: the [`Scenario`](#hooks) that is running, with its name, tags and attempt.
- `attach`, `log` and `link`: see [Attachments](#attachments).

These members work while the scenario's steps and hooks run, including after an `await`, and throw a `StateError`
anywhere else. Without a `world` option, steps that take a World receive a `DefaultWorld`.

## Hooks

Hooks run code around scenarios, steps and the whole run:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#hooks -->
```dart
final shopHooks = <Glue>[
  BeforeAll((TestRun run) {
    // The default when no profile sets the world parameter.
    run.parameters['currency'] ??= 'EUR';
  }, name: 'default currency'),
  Before((ShopWorld w, Scenario s) {
    w.log('Starting "${s.name}", attempt ${s.attempt + 1}');
  }, name: 'log the scenario'),
  Before(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
    tags: '@slow',
    name: 'warm up the payment service',
    order: 10,
  ),
  AfterStep((Step step) {
    if (step.status == Status.failed) log('Failed: ${step.text}');
  }),
  After((ShopWorld w, Scenario s) {
    if (s.isFailed) {
      w.attach('${w.cart.receipt()}', mediaType: 'text/plain');
    }
  }),
  AfterAll((TestRun run) {
    run.log('Currency: ${run.parameters['currency']}');
  }),
];
```

| Hook | Runs | Accepted bodies |
|---|---|---|
| `Before`, `After` | Before and after each scenario | `()`, `(World)`, `(Scenario)`, `(World, Scenario)` |
| `BeforeStep`, `AfterStep` | Before and after each step | `()`, `(World)`, `(Step)`, `(World, Step)` |
| `BeforeAll`, `AfterAll` | Once, before the first scenario and after the last one | `()`, `(TestRun)` |

- **`tags`** is a tag expression that selects the scenarios the hook runs for, such as `'@slow'` or
  `'@db and not @readonly'`. Test-run hooks have no tags.
- **`name`** names the hook in reports.
- **Order.** Hooks of one kind are sorted by `order` (default 0), then by definition order. `Before` hooks run in
  ascending order and `After` hooks in descending order, so by default `After` hooks run in reverse definition order.
- **`Scenario`** has the scenario's `id`, `name`, `uri`, `line`, `tags`, `language` and `attempt`, and in `After`
  hooks its `status` so far, `isFailed` and the first `error`. **`Step`** has its `text`, `keyword`, `line`,
  `scenario`, and in `AfterStep` its `status` and `error`. **`TestRun`** has the world parameters, which `BeforeAll`
  hooks may change before any scenario copies them.
- **Failures.** When a `Before` hook fails (or skips), the scenario's steps are skipped, but its `After` hooks still
  run. A failing `After` hook fails the scenario. When a `BeforeAll` hook fails, every `BeforeAll` and `AfterAll` hook
  still runs, but no scenario does, and the run fails.

## Attachments

Steps and hooks can attach data to the report, where it appears under the step:

<!-- excerpt: packages/cucumber/fixtures/guide/test/steps/shop_steps.dart#checkout -->
```dart
final checkoutSteps = <Glue>[
  Given('the payment service restarts once', (ShopWorld w) {
    // Fails the first attempt. With `retry: 1`, the scenario runs again.
    if (w.scenario.attempt == 0) {
      throw StateError('The payment service is restarting');
    }
  }),
  Given('I pay in {word}', (ShopWorld w, String currency) {
    if (currency != w.parameters['currency']) {
      skip('Payments in $currency are not supported yet');
    }
  }),
  When('I pay', (ShopWorld w) async {
    final service = w.payments = PaymentService('${w.parameters['currency']}');
    service.pay(w.cart.total);
    w.attach(
      jsonEncode(w.cart.receipt()),
      mediaType: 'application/json',
      fileName: 'receipt.json',
    );
    log('Paid ${w.cart.total} in ${service.currency}');
    link('https://shop.example/orders/42', title: 'The order');
  }, timeout: const Duration(seconds: 5)),
  Then('the payment of {money} is accepted', (ShopWorld w, Money amount) {
    expect(w.payments!.payments, [amount]);
  }),
  Then('the invoice is emailed', () {
    pending('Invoices are not emailed yet');
  }),
];
```

| Call | Attaches | Media type |
|---|---|---|
| `attach(String data)` | The text | `text/plain`, or `mediaType` |
| `attach(List<int> data)` | The bytes, Base64-encoded | `application/octet-stream`, or `mediaType` |
| `log(String text)` | A log line | `text/x.cucumber.log+plain` |
| `link(String url, {String? title})` | A link | `text/uri-list` |
| `attachFile(String path)` | The file's bytes, Base64-encoded | From the file's extension (`image/png` for `.png`), `application/octet-stream` if it is not known, or `mediaType` |

`fileName` names an attachment in the report; for `attachFile` it defaults to the file's name. `attachFile` reads the
file when it is called, so the file can be deleted afterwards, and a relative path is relative to the package root. The top-level `attach`, `log` and `link` work anywhere in a step or
hook, including in helper functions, and so do the World's members of the same names, the `Scenario`'s and the
`TestRun`'s (in test-run hooks). The top-level `log` clashes with `log` from `dart:math`: import
`dart:math hide log`, or import one of them with a prefix.

## Pending, skipped and failed steps

The checkout steps above show the outcomes a step can have:

| The step | Status | Effect on the scenario |
|---|---|---|
| Returns (or its `Future` completes) | passed | Continues |
| Calls `pending()` or throws `PendingException` | pending | Fails; the remaining steps are skipped |
| Calls `skip()` or throws `SkippedException` | skipped | Skipped; the remaining steps are skipped |
| Throws anything else, such as a failed `expect` | failed | Fails; the remaining steps are skipped |

`After` hooks run in every case. A run succeeds only if no scenario ended failed, pending, undefined or ambiguous:
there is no non-strict mode. A skipped scenario is reported to `package:test` as skipped, with the reason given to
`skip()`.

## Timeouts and retries

- **Step and hook timeouts.** `timeout:` on a step or hook, like `When('I pay', …)` above, fails it with a
  `TimeoutException` when it takes longer. There is none by default.
- **Scenario timeouts.** Each scenario is a `package:test` test, with `package:test`'s timeout (30 seconds by
  default). The `scenarioTimeout` option changes it ([Configuration](configuration.md)).
- **Retries.** The `retry` option runs a failed scenario again, up to that many more times, each time with a new
  World. `Scenario.attempt` is 0 for the first attempt. Only failed scenarios are retried: pending, undefined and
  ambiguous ones would fail again. The scenario's final attempt decides the outcome, and the reports keep every
  attempt.

[`checkout_test.dart`](../../packages/cucumber/fixtures/guide/test/checkout_test.dart) sets `retry: 1`, so the scenario
whose payment service restarts once passes on its second attempt.

## Sharing glue between entry files

A project can have several entry files, for example one per area. `CucumberOptions` holds the options they share,
and `merge` refines them:

<!-- excerpt: packages/cucumber/fixtures/guide/test/support/options.dart -->
```dart
import 'package:cucumber/cucumber.dart';

import '../steps/shop_steps.dart';

/// The options that every entry file of the project shares.
final shopOptions = CucumberOptions(world: ShopWorld.new, glue: shopGlue);
```

<!-- excerpt: packages/cucumber/fixtures/guide/test/checkout_test.dart -->
```dart
import 'package:cucumber/cucumber.dart';

import 'steps/shop_steps.dart';
import 'support/options.dart';

void main() => CucumberSuite<ShopWorld>(
  shopOptions.merge(
    CucumberOptions(features: ['features/checkout.feature'], retry: 1),
  ),
).declare();
```

`cucumber(...)` is shorthand for `CucumberSuite(CucumberOptions(...)).declare()`. With `CucumberSuite`, give the World
type explicitly (`CucumberSuite<ShopWorld>`): it is the type that the bodies' World parameters are checked against.
Each entry file runs in its own isolate. When several of them write the same report, the reports are merged
([Reports](reports.md#reports-of-several-test-files)).
