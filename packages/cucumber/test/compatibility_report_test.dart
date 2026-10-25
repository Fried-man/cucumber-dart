// Keeps docs/compatibility.md, the published compatibility kit conformance
// report, in step with the synced samples and with the skip lists that the
// conformance tests use: skippedSamples (the SerialHost, in
// packages/cucumber_core/test/compatibility/) and skippedThroughDartTest
// (test/compatibility_host_test.dart). Those tests fail if a sample that is
// not skipped does not pass, so together they keep the report honest.
//
// When a table no longer matches, the failure shows the expected table.
import 'dart:io';

import 'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../cucumber_core/test/compatibility/cck.dart';
import 'support/compatibility_skips.dart';
import 'support/dart_test_runner.dart';

/// The report, relative to the repository root.
const String _reportPath = 'docs/compatibility.md';

const String _summaryHeading = '## Summary';
const String _serialHostSkipsHeading = '### `SerialHost`';
const String _dartTestSkipsHeading = '### `dart test` host';
const String _resultsHeading = '## Results';

void main() {
  final report = File(
    p.join(cucumberPackageDirectory, '..', '..', _reportPath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final sections = _sections(report);
  final names = sampleDirectories().map(sampleName).toList();

  String section(String heading) {
    final body = sections[heading];
    if (body == null) fail('$_reportPath has no "$heading" section');
    return body;
  }

  test('names the pinned compatibility kit and its sample count', () {
    expect(
      report,
      contains(
        '`@cucumber/compatibility-kit` $compatibilityKitVersion '
        '(${names.length} samples)',
      ),
    );
  });

  test('summarises the results of each host', () {
    final serialSkipped = names.where(skippedSamples.containsKey).length;
    final dartTestSkipped = names.where(_skippedThroughDartTest).length;
    _expectTable(
      section(_summaryHeading),
      const ['Host', 'Passing', 'Skipped', 'Samples'],
      _summaryHeading,
      [
        [
          '`SerialHost`',
          '${names.length - serialSkipped}',
          '$serialSkipped',
          '${names.length}',
        ],
        [
          '`dart test` host',
          '${names.length - dartTestSkipped}',
          '$dartTestSkipped',
          '${names.length}',
        ],
      ],
    );
  });

  group('lists the skips', () {
    test('of the SerialHost', () {
      _expectSkips(
        section(_serialHostSkipsHeading),
        _serialHostSkipsHeading,
        skippedSamples.keys,
      );
    });

    test('of the dart test host, on top of the SerialHost ones', () {
      _expectSkips(
        section(_dartTestSkipsHeading),
        _dartTestSkipsHeading,
        skippedThroughDartTest.keys,
      );
    });

    test('of samples that exist', () {
      expect({
        ...skippedSamples.keys,
        ...skippedThroughDartTest.keys,
      }, everyElement(isIn(names)));
      expect(
        skippedThroughDartTest.keys,
        everyElement(isNot(isIn(skippedSamples.keys))),
        reason: 'a sample skipped by the SerialHost is skipped by dart test',
      );
    });
  });

  test('lists every sample with its arguments and results', () {
    String result(bool skipped) => skipped ? 'skipped' : 'passes';
    _expectTable(
      section(_resultsHeading),
      const ['Sample', 'Arguments', '`SerialHost`', '`dart test` host'],
      _resultsHeading,
      [
        for (final dir in sampleDirectories())
          [
            '[`${sampleName(dir)}`](../packages/cucumber_compatibility_kit/'
                'features/${sampleName(dir)}/)',
            switch (File(
              p.join(dir.path, '${sampleName(dir)}.arguments.txt'),
            )) {
              final file when file.existsSync() =>
                '`${file.readAsStringSync().trim()}`',
              _ => '',
            },
            result(skippedSamples.containsKey(sampleName(dir))),
            result(_skippedThroughDartTest(sampleName(dir))),
          ],
      ],
    );
  });
}

/// Whether the dart test host skips [name]: everything the SerialHost skips,
/// and [skippedThroughDartTest].
bool _skippedThroughDartTest(String name) =>
    skippedSamples.containsKey(name) ||
    skippedThroughDartTest.containsKey(name);

/// Checks that the table in [body] lists exactly [samples], each with a
/// reason that links to the upstream gap or design section behind it.
void _expectSkips(String body, String heading, Iterable<String> samples) {
  final table = _table(body);
  if (table == null) {
    expect(samples, isEmpty, reason: '"$heading" has no table of skips');
    return;
  }
  expect(table.header, ['Sample', 'Reason'], reason: heading);
  expect(
    [for (final row in table.rows) row.first],
    [for (final name in samples.toList()..sort()) '`$name`'],
    reason: '"$heading" must list the skipped samples, sorted',
  );
  for (final row in table.rows) {
    expect(
      row.last,
      matches(RegExp(r'\]\(|\]\[')),
      reason:
          'the reason for ${row.first} must link to the upstream gap or '
          'design section behind it',
    );
  }
}

/// Checks that the table in [body] has [header] and [rows].
void _expectTable(
  String body,
  List<String> header,
  String heading,
  List<List<String>> rows,
) {
  final expected = _markdownTable(header, rows);
  final table = _table(body);
  expect(table, isNotNull, reason: '"$heading" needs a table:\n\n$expected');
  expect(
    [table!.header, ...table.rows],
    [header, ...rows],
    reason: '"$heading" should have this table:\n\n$expected',
  );
}

/// The sections of [markdown] by heading line (`## ...` or `### ...`), each
/// up to the next heading.
Map<String, String> _sections(String markdown) {
  final sections = <String, String>{};
  String? heading;
  final body = StringBuffer();
  void close() {
    if (heading != null) sections[heading] = body.toString();
    body.clear();
  }

  for (final line in markdown.split('\n')) {
    if (line.startsWith('#')) {
      close();
      heading = line.trim();
    } else {
      body.writeln(line);
    }
  }
  close();
  return sections;
}

/// The first Markdown table in [body], if any.
({List<String> header, List<List<String>> rows})? _table(String body) {
  final lines = body
      .split('\n')
      .map((line) => line.trim())
      .skipWhile((line) => !line.startsWith('|'))
      .takeWhile((line) => line.startsWith('|'))
      .toList();
  if (lines.length < 2) return null;
  List<String> cells(String line) => [
    for (final cell in line.substring(1, line.length - 1).split('|'))
      cell.trim(),
  ];
  return (
    header: cells(lines.first),
    rows: [for (final line in lines.skip(2)) cells(line)],
  );
}

/// [header] and [rows] as a Markdown table.
String _markdownTable(List<String> header, List<List<String>> rows) {
  String line(List<String> cells) => '| ${cells.join(' | ')} |';
  return [
    line(header),
    '|${List.filled(header.length, '---').join('|')}|',
    for (final row in rows) line(row),
  ].join('\n');
}
