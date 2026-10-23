// Reads the Cucumber Messages of a run from an NDJSON file and prints the
// final status of each test case, then the counts per status.
//
//   dart run example/cucumber_query_example.dart build/cucumber/messages.ndjson
import 'dart:convert';
import 'dart:io';

import 'package:cucumber_messages/cucumber_messages.dart';
import 'package:cucumber_query/cucumber_query.dart';

/// Describes the run whose messages are [envelopes].
String describeRun(Iterable<Envelope> envelopes) {
  final query = Query();
  envelopes.forEach(query.update);

  final description = StringBuffer();
  for (final testCaseStarted in query.findAllTestCaseStarted()) {
    final pickle = query.findPickleBy(testCaseStarted);
    final result = query.findMostSevereTestStepResultBy(testCaseStarted);
    description.writeln(
      '${result?.status.value ?? 'NO STEPS'} '
      '${pickle?.name} (${pickle?.uri})',
    );
  }
  final counts = [
    for (final MapEntry(key: status, value: count)
        in query.countMostSevereTestStepResultStatus().entries)
      if (count > 0) '$count ${status.value}',
  ];
  description.writeln(
    'Test cases: ${query.countTestCasesStarted()} (${counts.join(', ')})',
  );
  return description.toString();
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run example/cucumber_query_example.dart <messages.ndjson>',
    );
    exitCode = 64;
    return;
  }
  final lines = File(
    arguments.single,
  ).openRead().transform(utf8.decoder).transform(const LineSplitter());
  final envelopes = await decodeNdjsonEnvelopes(lines).toList();
  stdout.write(describeRun(envelopes));
}
