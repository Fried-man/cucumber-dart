/// The code under test in the guide: a shop with a catalogue, carts and
/// payments.
library;

/// An amount of money, in cents.
final class Money implements Comparable<Money> {
  /// Creates an amount of [cents].
  const Money(this.cents);

  /// Parses an amount such as `€2.50`.
  factory Money.parse(String text) {
    final match = RegExp(r'^€(\d+)\.(\d{2})$').firstMatch(text.trim());
    if (match == null) throw FormatException('Not an amount: $text');
    return Money(int.parse(match[1]!) * 100 + int.parse(match[2]!));
  }

  /// The amount in cents.
  final int cents;

  /// The sum of this and [other].
  Money operator +(Money other) => Money(cents + other.cents);

  /// This amount [times] times.
  Money operator *(int times) => Money(cents * times);

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => '€${cents ~/ 100}.${'${cents % 100}'.padLeft(2, '0')}';
}

/// A product of the catalogue.
final class Product {
  /// Creates a product.
  const Product(this.name, this.price);

  /// The name.
  final String name;

  /// The price of one.
  final Money price;
}

/// A shopping cart.
final class Cart {
  final Map<String, (Product, int)> _lines = {};

  /// Adds [quantity] of [product].
  void add(Product product, int quantity) {
    final current = _lines[product.name]?.$2 ?? 0;
    _lines[product.name] = (product, current + quantity);
  }

  /// How many of the product called [name] are in the cart.
  int quantityOf(String name) => _lines[name]?.$2 ?? 0;

  /// The number of items.
  int get items => _lines.values.fold(0, (sum, line) => sum + line.$2);

  /// The cart's lines: each product's name and quantity, in the order they
  /// were first added.
  List<(String, int)> get lines => [
    for (final (product, quantity) in _lines.values) (product.name, quantity),
  ];

  /// The total: 10% off from €10.00.
  Money get total {
    final sum = _lines.values.fold(
      const Money(0),
      (sum, line) => sum + line.$1.price * line.$2,
    );
    return sum.cents >= 1000 ? Money(sum.cents * 9 ~/ 10) : sum;
  }

  /// The receipt, as JSON-like values.
  Map<String, Object?> receipt() => {
    'items': [
      for (final (name, quantity) in lines)
        {'name': name, 'quantity': quantity},
    ],
    'total': total.cents,
  };
}

/// Takes payments.
final class PaymentService {
  /// Creates a service for payments in [currency].
  PaymentService(this.currency);

  /// The currency it accepts, such as `EUR`.
  final String currency;

  /// The payments taken, in order.
  final List<Money> payments = [];

  /// Takes a payment of [amount].
  void pay(Money amount) => payments.add(amount);
}
