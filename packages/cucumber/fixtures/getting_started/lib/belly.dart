/// The code under test in the getting-started guide.
library;

/// A belly that growls when it has eaten enough cucumbers and waited.
class Belly {
  /// How many cucumbers it has eaten.
  int cukes = 0;

  /// How many hours it has waited.
  int hours = 0;

  /// Eats [count] cucumbers.
  void eat(int count) => cukes += count;

  /// Waits [hours] hours.
  void wait(int hours) => this.hours += hours;

  /// Whether it growls: after more than 10 cucumbers and at least an hour.
  bool get isGrowling => cukes > 10 && hours >= 1;
}
