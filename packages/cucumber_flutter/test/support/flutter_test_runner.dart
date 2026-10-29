// Runs `flutter test --reporter json` in a project and parses the reporter's
// events.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The directory of package:cucumber_flutter: `flutter test` runs in the
/// package root.
final String packageDirectory = Directory.current.path;

/// The directory of the project [relative] to [packageDirectory].
String projectDirectory(String relative) =>
    p.normalize(p.join(packageDirectory, relative));

/// Runs `flutter test --reporter json [arguments]` in [directory].
///
/// `CUCUMBER_*` variables of this process are removed, then [environment] is
/// added.
Future<FlutterTestRun> runFlutterTest(
  String directory, {
  List<String> arguments = const [],
  Map<String, String> environment = const {},
}) async {
  final result = await Process.run(
    'flutter',
    ['test', '--reporter', 'json', ...arguments],
    workingDirectory: directory,
    runInShell: Platform.isWindows,
    includeParentEnvironment: false,
    environment: {
      for (final MapEntry(:key, :value) in Platform.environment.entries)
        if (!key.toUpperCase().startsWith('CUCUMBER_')) key: value,
      ...environment,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return FlutterTestRun(
    result.exitCode,
    '${result.stdout}',
    '${result.stderr}',
  );
}

/// The outcome of a `flutter test --reporter json` run.
final class FlutterTestRun {
  /// Parses the reporter events in [stdout].
  FlutterTestRun(this.exitCode, this.stdout, this.stderr) {
    for (final line in const LineSplitter().convert(stdout)) {
      if (!line.startsWith('{')) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is Map<String, Object?>) _event(decoded);
    }
  }

  /// The process exit code.
  final int exitCode;

  /// The raw output.
  final String stdout;

  /// The error output.
  final String stderr;

  /// Groups by ID.
  final Map<int, Reported> groups = {};

  /// Tests by ID, in start order.
  final Map<int, ReportedTest> tests = {};

  void _event(Map<String, Object?> event) {
    switch (event['type']) {
      case 'group':
        final group = event['group']! as Map<String, Object?>;
        groups[group['id']! as int] = Reported(group);
      case 'testStart':
        final test = event['test']! as Map<String, Object?>;
        tests[test['id']! as int] = ReportedTest(test);
      case 'testDone':
        tests[event['testID']! as int]!
          ..result = event['result']! as String
          ..skipped = event['skipped']! as bool;
      case 'error':
        tests[event['testID']! as int]!.errors.add('${event['error']}');
      case 'print':
        tests[event['testID']! as int]!.prints.add('${event['message']}');
    }
  }

  /// The test named [name]. Fails if there is not exactly one.
  ReportedTest test(String name) {
    final matches = [
      for (final t in tests.values)
        if (t.name == name) t,
    ];
    if (matches.length != 1) {
      throw StateError(
        'Expected one test named "$name", found ${matches.length}.\n'
        '${describe()}',
      );
    }
    return matches.single;
  }

  /// The group named [name]. Fails if there is not exactly one.
  Reported group(String name) =>
      groups.values.singleWhere((g) => g.name == name);

  /// Everything printed by the tests named [name] (such as `(tearDownAll)`).
  String printsOf(String name) => [
    for (final t in tests.values)
      if (t.name == name) ...t.prints,
  ].join('\n');

  /// A description for failure messages.
  String describe() =>
      'exit code $exitCode\n'
      '${tests.values.map((t) => '  ${t.outcome} ${t.name}').join('\n')}\n'
      'stderr:\n$stderr';
}

/// A group or test reported by the JSON reporter.
class Reported {
  /// Reads [json].
  Reported(Map<String, Object?> json)
    : name = json['name']! as String,
      url = json['url'] as String?,
      line = json['line'] as int?,
      rootUrl = json['root_url'] as String?,
      rootLine = json['root_line'] as int?;

  /// The full name.
  final String name;

  /// The location's URL.
  final String? url;

  /// The location's line.
  final int? line;

  /// The URL of the outermost frame in the test file, when the location is
  /// outside it.
  final String? rootUrl;

  /// The line of [rootUrl].
  final int? rootLine;
}

/// A test reported by the JSON reporter.
final class ReportedTest extends Reported {
  /// Reads [json].
  ReportedTest(super.json);

  /// `success`, `failure` or `error`; `null` if it never finished.
  String? result;

  /// Whether it was skipped.
  bool skipped = false;

  /// The reported errors.
  final List<String> errors = [];

  /// The printed messages. Under `flutter test`, they include the
  /// exceptions that failed the test.
  final List<String> prints = [];

  /// The errors and the printed messages.
  String get output => [...errors, ...prints].join('\n');

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

/// The messages of [type] in [envelopes].
List<Map<String, Object?>> ofType(
  List<Map<String, Object?>> envelopes,
  String type,
) => [
  for (final envelope in envelopes)
    if (envelope[type] case final Map<String, Object?> message) message,
];
