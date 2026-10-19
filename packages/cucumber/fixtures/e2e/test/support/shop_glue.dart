import 'dart:convert';
import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The fixture's World.
class ShopWorld extends World {
  /// Payment methods used.
  final List<String> payments = [];
}

var _flakyAttempts = 0;

/// Steps for every outcome the host maps.
final List<Glue> shopGlue = [
  Given('a shop', (ShopWorld w) {}),
  Given('a step passes', () {}),
  When('a step fails with {string}', (String message) {
    throw StateError(message);
  }),
  Given('a pending step', () => pending('not built yet')),
  Given('an ambiguous step', () {}),
  Given(RegExp(r'^an ambiguous (.*)$'), (String what) {}),
  Given('a step skips', () => skip('not today')),
  Given('a step that passes the second time', () {
    if (++_flakyAttempts < 2) throw StateError('flaky');
  }),
  Then('the world parameters are logged', (ShopWorld w) {
    w.log(jsonEncode(w.parameters));
  }),
  Given('I pay with {string}', (ShopWorld w, String method) {
    w.payments.add(method);
  }),
];

/// A custom plugin: counts the messages of each type and writes the counts
/// as JSON to [path] when the run ends.
final class CountingPlugin implements Plugin {
  /// Creates a plugin writing to [path].
  CountingPlugin(this.path);

  /// The output file.
  final String path;

  final Map<String, int> _counts = {};

  @override
  void onMessage(messages.Envelope envelope) {
    final type = envelope.toJson().keys.single;
    _counts[type] = (_counts[type] ?? 0) + 1;
  }

  @override
  void close() {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(_counts));
  }
}
