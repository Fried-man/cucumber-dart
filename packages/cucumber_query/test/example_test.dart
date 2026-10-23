import 'dart:io';

import 'package:cucumber_messages/cucumber_messages.dart';
import 'package:test/test.dart';

import '../example/cucumber_query_example.dart';

void main() {
  test('the example describes the final attempt of each test case', () {
    final envelopes = [
      for (final line in File(
        'testdata/src/examples-tables.ndjson',
      ).readAsLinesSync())
        if (line.trim().isNotEmpty) parseEnvelopeJson(line),
    ];
    final feature = 'samples/examples-tables/examples-tables.feature';

    expect(
      describeRun(envelopes),
      'PASSED Eating cucumbers ($feature)\n'
      'PASSED Eating cucumbers ($feature)\n'
      'FAILED Eating cucumbers ($feature)\n'
      'FAILED Eating cucumbers ($feature)\n'
      'PASSED Eating cucumbers with 11 friends ($feature)\n'
      'PASSED Eating cucumbers with 1 friends ($feature)\n'
      'PASSED Eating cucumbers with 0 friends ($feature)\n'
      'Test cases: 7 (5 PASSED, 2 FAILED)\n',
    );
  });
}
