// Writes the Cucumber Messages of a run, read from an NDJSON file, as a
// standalone HTML report.
//
//   dart run example/cucumber_html_formatter_example.dart \
//       build/cucumber/messages.ndjson build/cucumber/report.html
import 'dart:convert';
import 'dart:io';

import 'package:cucumber_html_formatter/cucumber_html_formatter.dart';
import 'package:cucumber_messages/cucumber_messages.dart';

/// Writes the report of [envelopes] to [out].
void writeReport(
  Iterable<Envelope> envelopes,
  StringSink out, {
  String title = 'Cucumber',
}) {
  final writer = MessagesToHtmlWriter(out, title: title);
  envelopes.forEach(writer.write);
  writer.close();
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run example/cucumber_html_formatter_example.dart '
      '<messages.ndjson> <report.html>',
    );
    exitCode = 64;
    return;
  }
  final lines = File(
    arguments[0],
  ).openRead().transform(utf8.decoder).transform(const LineSplitter());
  final envelopes = await decodeNdjsonEnvelopes(lines).toList();

  final report = File(arguments[1]);
  await report.parent.create(recursive: true);
  final sink = report.openWrite();
  writeReport(envelopes, sink);
  await sink.close();
  print('Wrote ${envelopes.length} messages to ${report.path}');
}
