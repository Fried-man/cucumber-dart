import 'dart:math';

/// The order in which pickles run (design §5.10).
sealed class PickleOrder {
  const PickleOrder();

  /// The order in which pickles are defined.
  static const PickleOrder defined = DefinedOrder();

  /// The reverse of the defined order.
  static const PickleOrder reverse = ReverseOrder();

  /// Parses `defined`, `reverse`, `random` or `random:<seed>`.
  ///
  /// `random` without a seed picks one; read it from [RandomOrder.seed] to
  /// reproduce the run.
  ///
  /// Throws an [ArgumentError] for anything else.
  static PickleOrder parse(String spec) {
    final value = spec.trim();
    if (value == 'defined') return defined;
    if (value == 'reverse') return reverse;
    if (value == 'random') return RandomOrder();
    if (value.startsWith('random:')) {
      final seed = int.tryParse(value.substring('random:'.length));
      if (seed != null) return RandomOrder(seed);
    }
    throw ArgumentError.value(
      spec,
      'order',
      "Expected 'defined', 'reverse', 'random' or 'random:<seed>'",
    );
  }

  /// Returns [items] in this order.
  List<T> apply<T>(List<T> items);
}

/// Pickles run in the order they are defined.
final class DefinedOrder extends PickleOrder {
  /// Creates the defined order.
  const DefinedOrder();

  @override
  List<T> apply<T>(List<T> items) => [...items];

  @override
  String toString() => 'defined';
}

/// Pickles run in reverse definition order.
final class ReverseOrder extends PickleOrder {
  /// Creates the reverse order.
  const ReverseOrder();

  @override
  List<T> apply<T>(List<T> items) => items.reversed.toList();

  @override
  String toString() => 'reverse';
}

/// Pickles run in a pseudo-random order determined by [seed].
final class RandomOrder extends PickleOrder {
  /// Creates a random order with [seed], or a random seed when omitted.
  RandomOrder([int? seed]) : seed = seed ?? Random().nextInt(0x7fffffff);

  /// The seed. Use `random:<seed>` to reproduce an order.
  final int seed;

  @override
  List<T> apply<T>(List<T> items) => [...items]..shuffle(Random(seed));

  @override
  String toString() => 'random:$seed';
}
