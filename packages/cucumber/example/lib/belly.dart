/// The code under test in the example: a belly that growls when it has eaten
/// enough cucumbers and waited long enough.
library;

/// A colour of cucumber.
enum Color {
  /// Red.
  red,

  /// Green.
  green,

  /// Blue.
  blue,
}

/// A belly.
class Belly {
  final List<Color> _eaten = [];
  int _hoursWaited = 0;

  /// How many cucumbers have been eaten.
  int get cukes => _eaten.length;

  /// The colours of the cucumbers eaten, in order.
  List<Color> get colors => List.unmodifiable(_eaten);

  /// Eats [count] cucumbers of [color].
  void eat(int count, [Color color = Color.green]) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'Must be >= 0');
    _eaten.addAll(List.filled(count, color));
  }

  /// Waits [hours].
  void wait(int hours) => _hoursWaited += hours;

  /// Whether the belly growls: more than 10 cucumbers and at least an hour.
  bool get isGrowling => cukes > 10 && _hoursWaited >= 1;
}
