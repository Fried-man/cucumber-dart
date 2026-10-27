// The glue of the guide's shop. docs/guide/writing-glue.md shows the regions
// between `#docregion` and `#enddocregion` comments.
import 'dart:convert';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber_guide/shop.dart';
import 'package:test/test.dart';

// #docregion world
/// The state of one scenario attempt.
class ShopWorld extends World {
  final catalogue = <String, Product>{};
  final cart = Cart();
  PaymentService? payments;
}
// #enddocregion world

// #docregion types
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
// #enddocregion types

final cartSteps = <Glue>[
  // #docregion steps
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
  // #enddocregion steps
  // #docregion regexp
  Then(RegExp(r'^the cart has (\d+) items?$'), (ShopWorld w, int items) {
    expect(w.cart.items, items);
  }),
  // #enddocregion regexp
  // #docregion data-table
  Then('the cart is:', (ShopWorld w, DataTable expected) {
    expected.diff([
      ['product', 'quantity'],
      for (final (name, quantity) in w.cart.lines) [name, '$quantity'],
    ]);
  }),
  // #enddocregion data-table
  // #docregion doc-string
  Then('the receipt is:', (ShopWorld w, Map<String, Object?> receipt) {
    expect(w.cart.receipt(), receipt);
  }),
  // #enddocregion doc-string
];

// #docregion checkout
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
// #enddocregion checkout

// #docregion hooks
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
// #enddocregion hooks

// #docregion glue
final shopGlue = <Glue>[
  ...shopTypes,
  ...cartSteps,
  ...checkoutSteps,
  ...shopHooks,
];
// #enddocregion glue
