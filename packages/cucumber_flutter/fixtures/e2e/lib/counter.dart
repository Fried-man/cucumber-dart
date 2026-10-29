import 'package:flutter/widgets.dart';

/// A counter with a button, without Material.
class Counter extends StatefulWidget {
  /// Creates the counter.
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        Text('$_count'),
        GestureDetector(
          key: const Key('increment'),
          onTap: () => setState(() => _count++),
          child: const Text('+'),
        ),
      ],
    ),
  );
}
