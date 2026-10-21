import 'package:cucumber/cucumber.dart';

/// The glue of every entry file. Loaded from the same place, it gets the same
/// IDs in every isolate, so the merged report lists it once.
final List<Glue> glue = [
  BeforeAll(() {}, name: 'open the shop'),
  // Slow enough that the entry files run at the same time.
  Given('a step passes', () => Future<void>.delayed(_pause)),
  Given('another step passes', () => Future<void>.delayed(_pause)),
];

const Duration _pause = Duration(milliseconds: 50);
