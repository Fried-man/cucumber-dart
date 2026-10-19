import 'dart:io';

import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;

import 'configuration.dart';

/// Writes every message as one line of JSON (NDJSON), the canonical Cucumber
/// Messages stream (design §8.2). Its plugin specification is
/// `message:<path>`.
///
/// The file is created (with its parent directories) when the first message
/// arrives, so a suite whose tests are all filtered out writes nothing.
final class NdjsonPlugin implements Plugin {
  /// Creates a plugin writing to [path].
  NdjsonPlugin(this.path);

  /// The output file.
  final String path;

  IOSink? _sink;

  @override
  void onMessage(messages.Envelope envelope) {
    final sink = _sink ??= _open();
    sink
      ..write(messages.envelopeToJsonString(envelope))
      ..write('\n');
  }

  IOSink _open() {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return file.openWrite();
  }

  @override
  Future<void> close() async {
    final sink = _sink;
    _sink = null;
    await sink?.close();
  }

  @override
  String toString() => 'message:$path';
}

/// The plugin specifications that can be used in code, `cucumber.yaml` and
/// `CUCUMBER_PLUGIN`.
const String pluginSpecifications = 'message:<path>';

/// Creates the plugins for [specs] (design §8.1): `message:<path>` strings
/// (paths relative to [packageRoot]) and [Plugin] instances.
///
/// Throws a [CucumberConfigurationException] for anything else.
List<Plugin> createPlugins(List<Object> specs, {required String packageRoot}) {
  return [
    for (final spec in specs)
      switch (spec) {
        final Plugin plugin => plugin,
        final String text => _fromSpecification(text.trim(), packageRoot),
        _ => throw CucumberConfigurationException(
          'Plugins must be specifications ($pluginSpecifications) or Plugin '
          'instances, got ${spec.runtimeType}: $spec',
        ),
      },
  ];
}

Plugin _fromSpecification(String spec, String packageRoot) {
  final colon = spec.indexOf(':');
  final name = colon < 0 ? spec : spec.substring(0, colon);
  final argument = colon < 0 ? '' : spec.substring(colon + 1).trim();
  switch (name) {
    case 'message':
      if (argument.isEmpty) {
        throw CucumberConfigurationException(
          'Plugin "$spec" needs an output file: message:<path>. '
          '(dart test owns the console.)',
        );
      }
      return NdjsonPlugin(p.normalize(p.join(packageRoot, argument)));
    default:
      throw CucumberConfigurationException(
        'Unknown plugin "$spec". Available: $pluginSpecifications. Custom '
        'plugins are passed as Plugin instances in code.',
      );
  }
}
