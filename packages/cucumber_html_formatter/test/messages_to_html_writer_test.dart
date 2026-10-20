import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:cucumber_html_formatter/cucumber_html_formatter.dart';
import 'package:cucumber_html_formatter/src/assets.g.dart' show assetSha256;
import 'package:cucumber_messages/cucumber_messages.dart';
import 'package:test/test.dart';

const _placeholders = [
  '{{title}}',
  '{{icon}}',
  '{{css}}',
  '{{custom_css}}',
  '{{messages}}',
  '{{script}}',
  '{{custom_script}}',
];

const _messagesStart = 'window.CUCUMBER_MESSAGES = [';
const _messagesEnd = '];\n</script>';

/// Writes [envelopes] with a new [MessagesToHtmlWriter] and returns the
/// report.
String _report(
  Iterable<Envelope> envelopes, {
  String title = 'Cucumber',
  String customCss = '',
  String customScript = '',
}) {
  final out = StringBuffer();
  final writer = MessagesToHtmlWriter(
    out,
    title: title,
    customCss: customCss,
    customScript: customScript,
  );
  envelopes.forEach(writer.write);
  writer.close();
  return out.toString();
}

/// [indexMustache] with its placeholders replaced by [values].
String _render(Map<String, String> values) {
  var html = indexMustache;
  for (final placeholder in _placeholders) {
    html = html.replaceFirst(placeholder, values[placeholder] ?? '');
  }
  return html;
}

/// The text of the `window.CUCUMBER_MESSAGES` array literal of [html].
String _messagesText(String html) {
  final start = html.indexOf(_messagesStart);
  expect(start, isNonNegative, reason: 'no $_messagesStart');
  final end = html.indexOf(_messagesEnd, start);
  expect(end, isNonNegative, reason: 'no $_messagesEnd');
  return html.substring(start + _messagesStart.length, end);
}

/// Evaluates the `window.CUCUMBER_MESSAGES` array literal of [html] as
/// JavaScript would: JSON, except for the `\x3C` escape.
List<Object?> _messages(String html) {
  final text = _messagesText(html);
  // Escape sequences are matched left to right, so `\\x3C` (a backslash, then
  // `x3C`) stays as it is.
  final json = text.replaceAllMapped(
    RegExp(r'\\(x3C|.)'),
    (match) => match[1] == 'x3C' ? r'\u003C' : match[0]!,
  );
  return jsonDecode('[$json]') as List<Object?>;
}

Object? _json(Envelope envelope) => jsonDecode(envelopeToJsonString(envelope));

Envelope _source(String data) => Envelope(
  source: Source(
    uri: 'features/a.feature',
    data: data,
    mediaType: SourceMediaType.textXCucumberGherkinPlain,
  ),
);

Directory get _cckFeatures => Directory.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse(
      'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
    ),
  )!.resolve('../features/'),
);

void main() {
  group('assets', () {
    test('are embedded byte for byte', () {
      final assets = {
        'index.mustache': indexMustache,
        'main.js': mainJs,
        'main.js.LICENSE.txt': mainJsLicense,
        'main.css': mainCss,
        'icon.url': iconUrl,
      };
      expect(assetSha256.keys, unorderedEquals(assets.keys));
      for (final MapEntry(key: name, value: content) in assets.entries) {
        expect(
          '${sha256.convert(utf8.encode(content))}',
          assetSha256[name],
          reason: name,
        );
      }
    });

    test('the template has every placeholder once, in order', () {
      var from = 0;
      for (final placeholder in _placeholders) {
        final index = indexMustache.indexOf(placeholder, from);
        expect(index, isNonNegative, reason: placeholder);
        expect(indexMustache.indexOf(placeholder, index + 1), -1);
        from = index;
      }
      expect(indexMustache, contains('$_messagesStart{{messages}}];'));
    });

    test('the version matches the package version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('\nversion: $htmlFormatterVersion\n'));
    });
  });

  group('MessagesToHtmlWriter', () {
    test('fills the template, with the messages separated by commas', () {
      final envelopes = [_source('Feature: a\n'), _source('Feature: b\n')];
      expect(
        _report(envelopes),
        _render({
          '{{title}}': 'Cucumber',
          '{{icon}}': iconUrl,
          '{{css}}': mainCss,
          '{{messages}}': envelopes.map(envelopeToJsonString).join(','),
          '{{script}}': mainJs,
        }),
      );
    });

    test('an empty run is the template without messages', () {
      final html = _report(const []);
      expect(
        html,
        _render({
          '{{title}}': 'Cucumber',
          '{{icon}}': iconUrl,
          '{{css}}': mainCss,
          '{{script}}': mainJs,
        }),
      );
      expect(html, contains('window.CUCUMBER_MESSAGES = [];'));
      expect(_messages(html), isEmpty);
    });

    test('escapes < as \\x3C so messages cannot end the script', () {
      const data =
          'Feature: </script><script>alert(1)</script>\n'
          '  Scenario: <!-- a comment <b>\n'
          r'    Given a literal \x3C and a "quote"'
          '\n';
      final envelope = _source(data);
      final html = _report([envelope]);
      final text = _messagesText(html);

      expect(text, isNot(contains('<')));
      expect(text, contains(r'\x3C/script>\x3Cscript>alert(1)\x3C/script>'));
      expect(text, contains(r'\x3C!-- a comment \x3Cb>'));
      expect(text, contains(r'a literal \\x3C and a \"quote\"'));
      expect(
        '</script>'.allMatches(html),
        hasLength('</script>'.allMatches(_report(const [])).length),
        reason: 'the messages close no script element',
      );
      expect(_messages(html), [_json(envelope)]);
    });

    test('takes a title, an icon, style sheets and scripts', () {
      final out = StringBuffer();
      MessagesToHtmlWriter(
        out,
        title: 'My report',
        icon: 'favicon.ico',
        css: 'body {}',
        customCss: '.custom {}',
        script: 'render();',
        customScript: 'extend();',
      ).close();
      expect(
        out.toString(),
        _render({
          '{{title}}': 'My report',
          '{{icon}}': 'favicon.ico',
          '{{css}}': 'body {}',
          '{{custom_css}}': '.custom {}',
          '{{script}}': 'render();',
          '{{custom_script}}': 'extend();',
        }),
      );
    });

    test('streams: the head with the first message, the tail on close', () {
      final out = StringBuffer();
      final writer = MessagesToHtmlWriter(out);
      expect(out.toString(), isEmpty);

      writer.write(_source('Feature: a\n'));
      final head = out.toString();
      expect(head, startsWith('<!DOCTYPE html>'));
      expect(
        head,
        endsWith(
          '$_messagesStart${envelopeToJsonString(_source('Feature: a\n'))}',
        ),
      );
      expect(head, isNot(contains(mainJs)));

      writer.close();
      expect(out.toString(), startsWith(head));
      expect(out.toString(), endsWith('</html>\n'));
    });

    test('close is idempotent; write after close throws', () {
      final out = StringBuffer();
      final writer = MessagesToHtmlWriter(out)..close();
      final length = out.length;
      writer.close();
      expect(out.length, length);
      expect(() => writer.write(_source('')), throwsStateError);
      expect(out.length, length);
    });
  });

  group('Compatibility Kit samples', () {
    final emptyReport = _report(const []);
    final samples = [
      for (final file in _cckFeatures.listSync(recursive: true))
        if (file is File && file.path.endsWith('.ndjson')) file,
    ]..sort((a, b) => a.path.compareTo(b.path));

    test(
      'there are samples',
      () => expect(samples, hasLength(greaterThan(40))),
    );

    for (final file in samples) {
      final name = file.uri.pathSegments.last;
      test(name, () {
        final lines = [
          for (final line in file.readAsLinesSync())
            if (line.trim().isNotEmpty) line,
        ];
        final envelopes = [
          for (final line in lines)
            Envelope.fromJson(jsonDecode(line) as Map<String, Object?>),
        ];
        final html = _report(envelopes);

        expect(html, startsWith('<!DOCTYPE html>\n<html lang="en">\n'));
        expect(html, endsWith('</body>\n</html>\n'));
        expect(html, contains('<title>Cucumber</title>'));
        expect(html, contains('<link rel="icon" href="$iconUrl">'));
        expect(html.indexOf(mainCss), lessThan(html.indexOf(_messagesStart)));
        expect(
          html.indexOf(mainJs),
          greaterThan(html.indexOf(_messagesEnd)),
          reason: 'the script runs after the messages are defined',
        );
        // The messages are the only difference from the report of an empty
        // run, and they hold no tag that could end the script element.
        final text = _messagesText(html);
        expect(text, isNot(contains('<')));
        expect(
          html,
          emptyReport.replaceFirst('$_messagesStart]', '$_messagesStart$text]'),
        );

        final embedded = _messages(html);
        expect(embedded, hasLength(lines.length));
        for (var i = 0; i < lines.length; i++) {
          expect(embedded[i], jsonDecode(lines[i]), reason: 'envelope $i');
        }
      });
    }
  });
}
