import 'dart:io';

import 'package:cucumber_core/engine.dart';
import 'package:cucumber_html_formatter/cucumber_html_formatter.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;

import 'configuration.dart';
import 'report_merging.dart';
import 'summary.dart';

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
    final sink = _sink ??= _open(path);
    sink
      ..write(messages.envelopeToJsonString(envelope))
      ..write('\n');
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

/// Writes the messages as a standalone HTML report with
/// `package:cucumber_html_formatter` (design §8.2). Its plugin specification
/// is `html:<path>`.
///
/// The messages are streamed into the report as they arrive. The file is
/// created (with its parent directories) when the first message arrives, so
/// a suite whose tests are all filtered out writes nothing; the report is
/// complete once the plugin is closed.
final class HtmlPlugin implements Plugin {
  /// Creates a plugin writing to [path].
  HtmlPlugin(this.path);

  /// The output file.
  final String path;

  IOSink? _sink;
  MessagesToHtmlWriter? _writer;

  @override
  void onMessage(messages.Envelope envelope) {
    (_writer ??= MessagesToHtmlWriter(_sink = _open(path))).write(envelope);
  }

  @override
  Future<void> close() async {
    final writer = _writer;
    final sink = _sink;
    _writer = null;
    _sink = null;
    writer?.close();
    await sink?.close();
  }

  @override
  String toString() => 'html:$path';
}

IOSink _open(String path) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  return file.openWrite();
}

/// The plugin specifications that can be used in code, `cucumber.yaml` and
/// `CUCUMBER_PLUGIN`.
const String pluginSpecifications = 'message:<path>, html:<path>, summary';

/// Creates the plugins for [specs] (design §8.1): `message:<path>` and
/// `html:<path>` strings (paths relative to [packageRoot]), `summary`, and
/// [Plugin] instances.
///
/// Without [merging], `message:` and `html:` become an [NdjsonPlugin] and an
/// [HtmlPlugin] that write the suite's own messages. With [merging] (as under
/// `dart test`), they become the outputs of one [MergedReportPlugin], added
/// last, which writes the suite's report part and rewrites them from the
/// merged parts of the run when the suite ends (design §8.4).
///
/// Throws a [CucumberConfigurationException] for anything else.
List<Plugin> createPlugins(
  List<Object> specs, {
  required String packageRoot,
  ReportMerging? merging,
}) {
  final outputs = <ReportOutput>[];
  final plugins = <Plugin>[];
  for (final spec in specs) {
    final plugin = switch (spec) {
      final Plugin plugin => plugin,
      final String text => _fromSpecification(text.trim(), packageRoot),
      _ => throw CucumberConfigurationException(
        'Plugins must be specifications ($pluginSpecifications) or Plugin '
        'instances, got ${spec.runtimeType}: $spec',
      ),
    };
    switch (plugin) {
      case NdjsonPlugin(:final path) when merging != null && spec is String:
        outputs.add(ReportOutput(ReportFormat.message, path));
      case HtmlPlugin(:final path) when merging != null && spec is String:
        outputs.add(ReportOutput(ReportFormat.html, path));
      default:
        plugins.add(plugin);
    }
  }
  return [
    ...plugins,
    if (merging != null && outputs.isNotEmpty)
      MergedReportPlugin(merging, outputs),
  ];
}

Plugin _fromSpecification(String spec, String packageRoot) {
  final colon = spec.indexOf(':');
  final name = colon < 0 ? spec : spec.substring(0, colon);
  final argument = colon < 0 ? '' : spec.substring(colon + 1).trim();
  String outputFile() {
    if (argument.isEmpty) {
      throw CucumberConfigurationException(
        'Plugin "$spec" needs an output file: $name:<path>. '
        '(dart test owns the console.)',
      );
    }
    return p.normalize(p.join(packageRoot, argument));
  }

  switch (name) {
    case 'message':
      return NdjsonPlugin(outputFile());
    case 'html':
      return HtmlPlugin(outputFile());
    case 'summary':
      if (colon >= 0) {
        throw CucumberConfigurationException(
          'Plugin "$spec" takes no argument: the summary is printed when the '
          'suite ends.',
        );
      }
      return SummaryPlugin();
    default:
      throw CucumberConfigurationException(
        'Unknown plugin "$spec". Available: $pluginSpecifications. Custom '
        'plugins are passed as Plugin instances in code.',
      );
  }
}
