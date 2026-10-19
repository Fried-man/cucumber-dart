// Runs `dart test --reporter json` in a fixture project and parses the
// reporter's events.
import 'dart:convert';
import 'dart:io';

import 'package:cucumber/src/suite.dart' show findPackageRoot;
import 'package:path/path.dart' as p;

/// The directory of package:cucumber.
String get cucumberPackageDirectory => findPackageRoot(Directory.current.path);

/// The directory of the fixture project [name] (below `fixtures/`).
String fixtureDirectory(String name) =>
    p.join(cucumberPackageDirectory, 'fixtures', name);

/// Runs `dart test --reporter json [arguments]` in [directory].
///
/// `CUCUMBER_*` variables of this process are cleared, then [environment] is
/// added.
Future<DartTestRun> runDartTest(
  String directory, {
  List<String> arguments = const [],
  Map<String, String> environment = const {},
}) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['test', '--reporter', 'json', ...arguments],
    workingDirectory: directory,
    environment: {
      for (final key in Platform.environment.keys)
        if (key.toUpperCase().startsWith('CUCUMBER_')) key: '',
      ...environment,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return DartTestRun(result.exitCode, '${result.stdout}', '${result.stderr}');
}

/// The outcome of a `dart test --reporter json` run.
final class DartTestRun {
  /// Parses the reporter events in [stdout].
  DartTestRun(this.exitCode, this.stdout, this.stderr) {
    for (final line in const LineSplitter().convert(stdout)) {
      if (!line.startsWith('{')) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;
      _event(decoded);
    }
  }

  /// The process exit code.
  final int exitCode;

  /// The raw output.
  final String stdout;

  /// The error output.
  final String stderr;

  /// Groups by ID.
  final Map<int, ReportedGroup> groups = {};

  /// Tests by ID, in start order.
  final Map<int, ReportedTest> tests = {};

  /// Suite paths (such as `test/cucumber_test.dart`) by suite ID.
  final Map<int, String> suites = {};

  void _event(Map<String, Object?> event) {
    switch (event['type']) {
      case 'suite':
        final suite = event['suite']! as Map<String, Object?>;
        suites[suite['id']! as int] = suite['path']! as String;
      case 'group':
        final group = event['group']! as Map<String, Object?>;
        groups[group['id']! as int] = ReportedGroup(group);
      case 'testStart':
        final test = event['test']! as Map<String, Object?>;
        tests[test['id']! as int] = ReportedTest(
          test,
          suites[test['suiteID']] ?? '',
        );
      case 'testDone':
        final test = tests[event['testID']! as int]!;
        test
          ..result = event['result']! as String
          ..skipped = event['skipped']! as bool;
      case 'error':
        tests[event['testID']! as int]!.errors.add(
          '${event['error']}\n${event['stackTrace']}',
        );
      case 'print':
        tests[event['testID']! as int]!.prints.add('${event['message']}');
    }
  }

  /// The tests located in a `.feature` file: scenarios, example rows and
  /// parse errors.
  List<ReportedTest> get featureTests => [
    for (final test in tests.values)
      if (test.url?.endsWith('.feature') ?? false) test,
  ];

  /// The test named [name]. Fails if there is not exactly one.
  ReportedTest test(String name) {
    final matches = [
      for (final t in tests.values)
        if (t.name == name) t,
    ];
    if (matches.length != 1) {
      throw StateError(
        'Expected one test named "$name", found ${matches.length}. Tests:\n'
        '${tests.values.map((t) => '  ${t.name}').join('\n')}\n\n'
        'stderr:\n$stderr',
      );
    }
    return matches.single;
  }

  /// The group named [name]. Fails if there is not exactly one.
  ReportedGroup group(String name) =>
      groups.values.singleWhere((g) => g.name == name);

  /// A description for failure messages.
  String describe() =>
      'exit code $exitCode\n'
      '${tests.values.map((t) => '  ${t.result} ${t.name}').join('\n')}\n'
      'stderr:\n$stderr';
}

/// A group reported by `package:test`.
final class ReportedGroup {
  ReportedGroup(Map<String, Object?> json)
    : name = json['name']! as String,
      url = json['url'] as String?,
      line = json['line'] as int?,
      column = json['column'] as int?;

  /// The full name.
  final String name;

  /// The location.
  final String? url;

  /// The line.
  final int? line;

  /// The column.
  final int? column;
}

/// A test reported by `package:test`.
final class ReportedTest {
  ReportedTest(Map<String, Object?> json, this.suite)
    : name = json['name']! as String,
      url = json['url'] as String?,
      line = json['line'] as int?,
      column = json['column'] as int?;

  /// The full name.
  final String name;

  /// The path of the test file, such as `test/cucumber_test.dart`.
  final String suite;

  /// The location.
  final String? url;

  /// The line.
  final int? line;

  /// The column.
  final int? column;

  /// `success`, `failure` or `error`; `null` if it never finished.
  String? result;

  /// Whether it was skipped.
  bool skipped = false;

  /// The reported errors, with their stack traces.
  final List<String> errors = [];

  /// The printed messages (including `printOnFailure` and skip reasons).
  final List<String> prints = [];

  /// `passed`, `skipped` or `failed`.
  String get outcome => skipped
      ? 'skipped'
      : result == 'success'
      ? 'passed'
      : 'failed';
}

/// Reads an NDJSON file into JSON maps.
List<Map<String, Object?>> readNdjson(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

/// The envelopes of [type] in [envelopes].
List<Map<String, Object?>> ofType(
  List<Map<String, Object?>> envelopes,
  String type,
) => [
  for (final envelope in envelopes)
    if (envelope[type] case final Map<String, Object?> message) message,
];
