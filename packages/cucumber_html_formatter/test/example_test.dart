import 'dart:io';
import 'dart:isolate';

import 'package:cucumber_html_formatter/cucumber_html_formatter.dart';
import 'package:cucumber_messages/cucumber_messages.dart';
import 'package:test/test.dart';

import '../example/cucumber_html_formatter_example.dart' as example;

void main() {
  final minimal = File.fromUri(
    Isolate.resolvePackageUriSync(
      Uri.parse(
        'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
      ),
    )!.resolve('../features/minimal/minimal.ndjson'),
  );

  test('the example writes a report from an NDJSON file', () async {
    final directory = Directory.systemTemp.createTempSync('html_example');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = File('${directory.path}/reports/report.html');

    await example.main([minimal.path, report.path]);

    final html = report.readAsStringSync();
    expect(html, startsWith('<!DOCTYPE html>'));
    expect(html, contains('<title>Cucumber</title>'));
    final messages = [
      for (final line in minimal.readAsLinesSync())
        if (line.isNotEmpty)
          escapeJsonForScript(envelopeToJsonString(parseEnvelopeJson(line))),
    ];
    expect(
      html,
      contains('window.CUCUMBER_MESSAGES = [${messages.join(',')}];'),
    );
    expect(html.trimRight(), endsWith('</html>'));
  });

  test('writeReport uses the title', () {
    final out = StringBuffer();
    example.writeReport(const [], out, title: 'Nightly');
    expect(out.toString(), contains('<title>Nightly</title>'));
  });
}
