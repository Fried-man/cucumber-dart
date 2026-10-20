import 'package:cucumber_messages/cucumber_messages.dart';

import 'assets.g.dart';

/// Writes Cucumber Messages as a standalone HTML report.
///
/// The report is [indexMustache] with its placeholders filled, written as a
/// stream, as the upstream wrappers (JavaScript `CucumberHtmlStream`, Java
/// `MessagesToHtmlWriter`, Ruby `Formatter`) do:
///
/// 1. the template up to `{{messages}}`, with the title, icon and style
///    sheets, when the first message is written (or on [close]);
/// 2. each message as JSON, separated by commas, as an element of the
///    `window.CUCUMBER_MESSAGES` array literal. Every `<` is written as
///    `\x3C`, so no message can end the `<script>` element early;
/// 3. on [close], the rest of the template, with the report script.
///
/// ```dart
/// final sink = File('report.html').openWrite();
/// final writer = MessagesToHtmlWriter(sink);
/// envelopes.forEach(writer.write);
/// writer.close();
/// await sink.close();
/// ```
///
/// The writer never closes [out]; that is up to its owner.
final class MessagesToHtmlWriter {
  /// Creates a writer to [out].
  ///
  /// The values are inserted verbatim, as upstream does:
  ///
  /// - [title]: the report's `<title>`. Default: `Cucumber`.
  /// - [icon]: the favicon, any `href` value. Default: [iconUrl].
  /// - [css]: the style sheet. Default: [mainCss]. To restyle the report,
  ///   prefer [customCss].
  /// - [customCss]: a style sheet applied after [css].
  /// - [script]: the script rendering `window.CUCUMBER_MESSAGES`. Default:
  ///   [mainJs]. To extend the report, prefer [customScript].
  /// - [customScript]: a script run after [script].
  MessagesToHtmlWriter(
    this.out, {
    String title = 'Cucumber',
    String icon = iconUrl,
    String css = mainCss,
    String customCss = '',
    String script = mainJs,
    String customScript = '',
  }) : _title = title,
       _icon = icon,
       _css = css,
       _customCss = customCss,
       _script = script,
       _customScript = customScript;

  /// Where the report is written.
  final StringSink out;

  final String _title;
  final String _icon;
  final String _css;
  final String _customCss;
  final String _script;
  final String _customScript;

  bool _preMessageWritten = false;
  bool _firstMessageWritten = false;
  bool _closed = false;

  /// Writes [envelope] to the report.
  ///
  /// Throws a [StateError] once the writer is closed.
  void write(Envelope envelope) {
    if (_closed) {
      throw StateError('MessagesToHtmlWriter is closed');
    }
    _writePreMessage();
    if (_firstMessageWritten) {
      out.write(',');
    } else {
      _firstMessageWritten = true;
    }
    out.write(escapeJsonForScript(envelopeToJsonString(envelope)));
  }

  /// Completes the report. Closing a closed writer has no effect.
  ///
  /// A writer closed without messages writes a report of an empty run.
  void close() {
    if (_closed) return;
    _closed = true;
    _writePreMessage();
    out
      ..write(_between('{{messages}}', '{{script}}'))
      ..write(_script)
      ..write(_between('{{script}}', '{{custom_script}}'))
      ..write(_customScript)
      ..write(_between('{{custom_script}}', null));
  }

  void _writePreMessage() {
    if (_preMessageWritten) return;
    _preMessageWritten = true;
    out
      ..write(_between(null, '{{title}}'))
      ..write(_title)
      ..write(_between('{{title}}', '{{icon}}'))
      ..write(_icon)
      ..write(_between('{{icon}}', '{{css}}'))
      ..write(_css)
      ..write(_between('{{css}}', '{{custom_css}}'))
      ..write(_customCss)
      ..write(_between('{{custom_css}}', '{{messages}}'));
  }

  /// The part of [indexMustache] between the placeholders [begin] and [end]
  /// (the start and the end of the template when `null`).
  static String _between(String? begin, String? end) {
    const template = indexMustache;
    final start = begin == null ? 0 : template.indexOf(begin) + begin.length;
    final stop = end == null ? template.length : template.indexOf(end);
    return template.substring(start, stop);
  }
}

/// [json] with every `<` replaced by `\x3C`, so it can be embedded in a
/// `<script>` element as a JavaScript expression.
///
/// In JSON, `<` can only occur in strings, where `\x3C` is the same character
/// in JavaScript. This keeps `</script>` and `<!--` out of the element (see
/// the HTML specification's
/// [restrictions for contents of script elements](https://html.spec.whatwg.org/multipage/scripting.html#restrictions-for-contents-of-script-elements)).
String escapeJsonForScript(String json) => json.replaceAll('<', r'\x3C');
